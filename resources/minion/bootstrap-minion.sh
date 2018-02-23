#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

# External variables with defaults
repo=${1-stable};
version=${2--latest-};
location=${3-Vagrant};
opennms_url=${4-http://opennms1:8980/opennms};
activemq_url=${5-failover:(tcp://activemq1:61616,tcp://activemq2:61616)?randomize=false};
kafka_svr=${6-kafka1:9092,kafka2:9092,kafka3:9092};

# Internal Variables
java_url=http://download.oracle.com/otn-pub/java/jdk/8u161-b12/2f38c3b165be4555a1fa6e98c45e0808/jdk-8u161-linux-x64.rpm
git_user_name="Alejandro Galue"
git_user_email="agalue@opennms.org"

# Fix Network
nmcli connection reload
systemctl restart network

# Update /etc/hosts
cp /vagrant/hosts /etc/hosts

# Install basic packages and dependencies
if ! rpm -qa | grep -q wget; then
  echo "### Installing common packages..."
  rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
  yum install -y -q epel-release
  rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
  yum install -y -q jq ntp ntpdate net-tools vim-enhanced net-snmp net-snmp-utils wget curl git pytz dstat htop sysstat nmap-ncat
fi

# Calculated variables
ip_address=`ifconfig eth1 | grep "inet " | awk '{print $2}'`
hostname=`hostname`

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

# Setup timezone
if ! grep --quiet EST /etc/localtime; then
  echo "### Configuring timezone..."
  rm -f /etc/localtime
  ln -s /usr/share/zoneinfo/America/New_York /etc/localtime
  ntpdate -u pool.ntp.org

  # Enable and start ntp
  systemctl enable ntpd
  systemctl start ntpd
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

# Install OpenNMS Minion packages
if [ ! -d "/opt/opennms" ]; then
  echo "### Installing OpenNMS Minion..."
  yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-$repo-rhel7.noarch.rpm
  rpm --import /etc/yum.repos.d/opennms-repo-$repo-rhel7.gpg
  if [ "$version" == "-latest-" ]; then
    yum install -y -q opennms-minion
  else
    yum install -y -q opennms-minion-$version
  fi
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

  cat <<EOF > featuresBoot.d/hawtio.boot
hawtio-offline
EOF

  cat <<EOF > featuresBoot.d/kafka.boot
!opennms-core-ipc-sink-camel
opennms-core-ipc-sink-kafka
EOF

  minion_id=`hostname`
  cat <<EOF > org.opennms.minion.controller.cfg
location=$location
id=$minion_id
http-url=$opennms_url
broker-url=$activemq_url
EOF

  cat <<EOF > org.opennms.core.ipc.sink.kafka.cfg
bootstrap.servers=$kafka_svr
acks=1
EOF

  cat <<EOF > org.opennms.netmgt.trapd.cfg
trapd.listen.interface=0.0.0.0
trapd.listen.port=162
trapd.queue.size=100000
EOF

  cat <<EOF > org.opennms.netmgt.syslog.cfg
syslog.listen.interface=0.0.0.0
syslog.listen.port=514
syslog.queue.size=100000
EOF

  cat <<EOF > org.opennms.features.telemetry.listeners-udp-50001.cfg
name=NXOS
class-name=org.opennms.netmgt.telemetry.listeners.udp.UdpListener
listener.port=50001
EOF

  cat <<EOF > org.opennms.features.telemetry.listeners-udp-8877.cfg
name=Netflow-5
class-name=org.opennms.netmgt.telemetry.listeners.udp.UdpListener
listener.port=8877
EOF

  cat <<EOF > org.opennms.features.telemetry.listeners-udp-4729.cfg
name=Netflow-9
class-name=org.opennms.netmgt.telemetry.listeners.udp.UdpListener
listener.port=4729
EOF

  systemctl enable minion
  systemctl start minion
fi

