#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
#
# This script doesn't support ActiveMQ. Kafka will be used for RPC and Sink.
# TODO: Apply JVM Runing based on available memory.
# TODO: Be able to choose the broker implementation for RPC and Sink.

# External variables with defaults
repo=${1-stable};
version=${2--latest-};
location=${3-Vagrant};
timezone=${4-America/New_York};
runas_root=${5-yes};
opennms_url=${6-http://onmscore.aws.opennms.org:8980/opennms};
kafka_servers=${7-kafka1.aws.opennms.org:9092,kafka2.aws.opennms.org:9092,kafka3.aws.opennms.org:9092};
kafka_security_protocol=${8-PLAINTEXT};
kafka_security_mechanism=${9-PLAIN};
kafka_security_module=${10-org.apache.kafka.common.security.plain.PlainLoginModule};
kafka_user_name=${11-opennms}
kafka_user_password=${12-0p3nNMS};

# Internal Variables
java_url="http://download.oracle.com/otn-pub/java/jdk/8u191-b12/2787e4a523244c269598db4e85c51e0c/jdk-8u191-linux-x64.rpm"
git_user_name="Alejandro Galue"
git_user_email="agalue@opennms.org"

# Fix Network (verify if this still necessary with latest CentOS 7, and latest VirtualBox)
nmcli connection reload
systemctl restart network

# Default ports
trap_port=162
syslog_port=514

# Kernel changes to run Minion as non-root
if [ "$runas_root" == "yes" ]; then
  if ! rpm -qa | grep -q kernel-ml; then
    echo "### Installing kernel 4.x in order to run Minion as non-root..."
    rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org 
    yum install -y -q https://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm 
    yum --enablerepo=elrepo-kernel -y -q install kernel-ml
    sed -r -i '/GRUB_DEFAULT/s/=.*/=0/' /etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg
  fi

  echo "### Kernel changes to run as non-root..."
  icmp_cmd=/etc/sysctl.d/99-zzz-non-root-icmp.conf
  echo "net.ipv4.ping_group_range=0 429496729" > $icmp_cmd
  sysctl -p $icmp_cmd

  echo "### Update firewall for SNMP Traps and Syslogs"
  systemctl start firewalld
  systemctl enable firewalld
  # enable masquerade to allow port-forwards
  firewall-cmd --zone="public" --add-masquerade
  firewall-cmd --zone="public" --add-masquerade --permanent
  # forward port 162 TCP and UDP to port 1162 on localhost
  firewall-cmd --zone="public" --add-forward-port=port=162:proto=udp:toport=1162:toaddr=127.0.0.1
  firewall-cmd --zone="public" --add-forward-port=port=162:proto=tcp:toport=1162:toaddr=127.0.0.1
  firewall-cmd --zone="public" --add-forward-port=port=162:proto=udp:toport=1162:toaddr=127.0.0.1 --permanent
  firewall-cmd --zone="public" --add-forward-port=port=162:proto=tcp:toport=1162:toaddr=127.0.0.1 --permanent
  # forward port 514 TCP and UDP to port 1514 on localhost
  firewall-cmd --zone="public" --add-forward-port=port=514:proto=udp:toport=1514:toaddr=127.0.0.1
  firewall-cmd --zone="public" --add-forward-port=port=514:proto=tcp:toport=1514:toaddr=127.0.0.1
  firewall-cmd --zone="public" --add-forward-port=port=514:proto=udp:toport=1514:toaddr=127.0.0.1 --permanent
  firewall-cmd --zone="public" --add-forward-port=port=514:proto=tcp:toport=1514:toaddr=127.0.0.1 --permanent

  # update ports
  trap_port=1162
  syslog_port=1514
fi

if ! rpm -qa | grep -q wget; then
  echo "### Installing common packages..."
  rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
  yum install -y -q epel-release
  rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
  yum install -y -q jq ntp ntpdate net-tools vim-enhanced net-snmp net-snmp-utils wget curl git pytz dstat htop sysstat nmap-ncat
fi

echo "### Configuring timezone..."
timedatectl set-timezone $timezone
ntpdate -u pool.ntp.org

echo "### Configuring NTP..."
ntp_cfg=/etc/ntpd.conf
if [ -e "$ntp_cfg.bak" ]; then
  cp $ntp_cfg $ntp_cfg.bak
fi
cat <<EOF > $ntp_cfg
driftfile /var/lib/ntp/drift
restrict default nomodify notrap nopeer noquery kod
restrict -6 default nomodify notrap nopeer noquery kod
restrict 127.0.0.1
restrict ::1
server 0.north-america.pool.ntp.org iburst
server 1.north-america.pool.ntp.org iburst
server 2.north-america.pool.ntp.org iburst
server 3.north-america.pool.ntp.org iburst
includefile /etc/ntp/crypto/pw
keys /etc/ntp/keys
disable monitor
EOF
systemctl enable ntpd
systemctl start ntpd

# Calculated variables
ip_address=$(ifconfig eth1 | grep "inet " | awk '{print $2}')
hostname=$(hostname)

# Install Oracle Java (not strictly necessary, but useful in order to have the latest version)
if ! rpm -qa | grep -q jdk1.8; then
  echo "### Downloading and installing Oracle JDK 8..."
  java_rpm=/tmp/jdk8-linux-x64.rpm
  wget -c --quiet --header "Cookie: oraclelicense=accept-securebackup-cookie" -O $java_rpm $java_url
  if [ ! -s $java_rpm ]; then
    echo "FATAL: Cannot download Java from $java_url. Using OpenNMS default ..."
    yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-stable-rhel7.noarch.rpm
    rpm --import /etc/yum.repos.d/opennms-repo-stable-rhel7.gpg
    yum install -y -q jdk1.8.0_144
    yum erase -y -q opennms-repo-stable
  else
    yum install -y -q $java_rpm
    rm -f $java_rpm
  fi
fi

# Install Haveged
if ! rpm -qa | grep -q haveged; then
  echo "### Installing Haveged..."
  yum install -y -q haveged
  systemctl enable haveged
  systemctl start haveged
fi

# Configure Net-SNMP Daemon
if [ ! -f "/etc/snmp/configured" ]; then
  echo "### Configuring net-SNMP..."
  cp /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.original
  cat <<EOF > /etc/snmp/snmpd.conf
com2sec localUser 127.0.0.1/32 public
com2sec localUser 192.168.205.0/24 public
group localGroup v1 localUser
group localGroup v2c localUser
view all included .1 80
access localGroup "" any noauth 0 all none none
syslocation VirtualBox
syscontact $git_user_name <$git_user_email>
dontLogTCPWrappersConnects yes
disk /
EOF
  chmod 600 /etc/snmp/snmpd.conf
  systemctl enable snmpd
  systemctl start snmpd
  touch /etc/snmp/configured
fi

# Install core OpenNMS dependencies

if ! rpm -qa | grep -q jicmp; then
  echo "Installing OpenNMS dependencies ..."
  yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-stable-rhel7.noarch.rpm
  rpm --import /etc/yum.repos.d/opennms-repo-stable-rhel7.gpg
  yum install -y -q jicmp jicmp6
  yum erase -y -q opennms-repo-stable
fi

# Install OpenNMS Minion packages
if [ ! -d "/opt/minion" ]; then
  echo "### Installing OpenNMS Minion..."
  yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-$repo-rhel7.noarch.rpm
  rpm --import /etc/yum.repos.d/opennms-repo-$repo-rhel7.gpg
  if [ "$version" == "-latest-" ]; then
    yum install -y -q opennms-minion
  else
    yum install -y -q opennms-minion-$version
  fi
fi

if ! rpm -qa | grep -q opennms-minion; then
  echo "### FATAL: The OpenNMS Minion RPMs have not been installed. Aborting ..."
  exit 1
fi

# Configure Minion
if [ ! -f "/opt/minion/etc/.git" ]; then
  echo "### Configuring OpenNMS Minion..."

  cd /opt/minion/etc
  git config --global user.name "$git_user_name"
  git config --global user.email "$git_user_email"
  git init .
  git add .
  git commit -m "Default Minion configuration for repository $repo version $version."

  sed -r -i '/sshHost/s/127.0.0.1/0.0.0.0/' org.apache.karaf.shell.cfg

  cat <<EOF > featuresBoot.d/hawtio.boot
hawtio-offline
EOF

  cat <<EOF > featuresBoot.d/kafka.boot
!opennms-core-ipc-sink-camel
!opennms-core-ipc-rpc-jms
opennms-core-ipc-sink-kafka
opennms-core-ipc-rpc-kafka
EOF

  minion_id=$(hostname)
  cat <<EOF > org.opennms.minion.controller.cfg
location=$location
id=$minion_id
http-url=$opennms_url
EOF

  kafka_files=("org.opennms.core.ipc.sink.kafka.cfg" "org.opennms.core.ipc.rpc.kafka.cfg")
  for kafka_file in "${kafka_files[@]}"; do
    cat <<EOF > $kafka_file
bootstrap.servers=$kafka_servers
acks=1
EOF
    if [[ $kafka_security_protocol == *"SASL"* ]]; then
      cat <<EOF >> $kafka_file
security.protocol=$kafka_security_protocol
sasl.mechanism=$kafka_security_mechanism
sasl.jaas.config=$kafka_security_module required username="$kafka_user_name" password="$kafka_user_password";
EOF
    fi
  done

  cat <<EOF > org.opennms.netmgt.trapd.cfg
trapd.listen.interface=0.0.0.0
trapd.listen.port=$trap_port
trapd.queue.size=100000
EOF

  cat <<EOF > org.opennms.netmgt.syslog.cfg
syslog.listen.interface=0.0.0.0
syslog.listen.port=$syslog_port
syslog.queue.size=100000
EOF

  cat <<EOF > org.opennms.features.telemetry.listeners-udp-50001.cfg
name=NXOS
class-name=org.opennms.netmgt.telemetry.listeners.udp.UdpListener
host=0.0.0.0
listener.port=50001
maxPacketSize=16192
EOF

  cat <<EOF > org.opennms.features.telemetry.listeners-udp-8877.cfg
name=Netflow-5
class-name=org.opennms.netmgt.telemetry.listeners.udp.UdpListener
host=0.0.0.0
listener.port=8877
maxPacketSize=8096
EOF

  cat <<EOF > org.opennms.features.telemetry.listeners-udp-4729.cfg
name=Netflow-9
class-name=org.opennms.netmgt.telemetry.listeners.flow.netflow9.UdpListener
host=0.0.0.0
listener.port=4729
maxPacketSize=8096
templateTimeout=1800000
EOF

  cat <<EOF > org.opennms.features.telemetry.listeners-udp-6343.cfg
name=SFlow
class-name=org.opennms.netmgt.telemetry.listeners.sflow.Listener
host=0.0.0.0
listener.port=6343
maxPacketSize=8096
EOF

  cat <<EOF > org.opennms.features.telemetry.listeners-udp-4738.cfg
name=IPFIX
class-name=org.opennms.netmgt.telemetry.listeners.flow.ipfix.UdpListener
host=0.0.0.0
listener.port=4738
maxPacketSize=8096
templateTimeout=1800000
EOF

  # Append the same relaxed SNMP4J options that OpenNMS has to make sure that broken SNMP devices still work with Minions.
  cat <<EOF >> system.properties

# Adding SNMP4J Options:
snmp4j.LogFactory=org.snmp4j.log.Log4jLogFactory
org.snmp4j.smisyntaxes=opennms-snmp4j-smisyntaxes.properties
org.opennms.snmp.snmp4j.allowSNMPv2InV1=false
org.opennms.snmp.snmp4j.forwardRuntimeExceptions=false
org.opennms.snmp.snmp4j.noGetBulk=false
org.opennms.snmp.workarounds.allow64BitIpAddress=true
org.opennms.snmp.workarounds.allowZeroLengthIpAddress=true
EOF

  if [ "$runas_root" == "yes" ]; then
    sed -r -i '/RUNAS/s/.*/export RUNAS=minion/' /etc/sysconfig/minion
    chown -R minion:minion .
  fi

  systemctl enable minion
fi

if [ "$runas_root" == "yes" ]; then
  echo "### Please reboot the VM in order to use the newer kernel and be able to run Minion as non-root."
else
  systemctl start minion
fi
