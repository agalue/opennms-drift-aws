#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# Warning: This is intended to be used through Terraform's template plugin only

# AWS Template Variables
# - node_id
# - vpc_cidr
# - hostname
# - domainname
# - repo_version
# - cluster_name
# - seed_name

echo "### Configuring Hostname and Domain..."

sed -i -r "s/HOSTNAME=.*/HOSTNAME=${hostname}.${domainname}/" /etc/sysconfig/network
hostname ${hostname}.${domainname}
domainname ${domainname}

echo "### Configuring Timezone..."

timezone=America/New_York
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
sed -i -r "s|ZONE=.*|ZONE=$timezone|" /etc/sysconfig/clock

echo "### Installing common packages..."

yum -y -q update
yum -y -q install jq net-snmp net-snmp-utils git pytz dstat htop sysstat

echo "### Configuring and enabling SNMP..."

snmp_cfg=/etc/snmp/snmpd.conf
cp $snmp_cfg $snmp_cfg.original
cat <<EOF > $snmp_cfg
com2sec localUser ${vpc_cidr} public
group localGroup v1 localUser
group localGroup v2c localUser
view all included .1 80
access localGroup "" any noauth 0 all none none
syslocation AWS
syscontact Account Manager
dontLogTCPWrappersConnects yes
disk /
EOF

chmod 600 $snmp_cfg
systemctl enable snmpd
systemctl start snmpd

echo "### Downloading and installing Oracle JDK..."

yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-stable-rhel7.noarch.rpm
rpm --import /etc/yum.repos.d/opennms-repo-stable-rhel7.gpg
yum install -y -q jdk1.8.0_144
yum erase -y -q opennms-repo-stable

echo "### Downloading and installing Cassandra..."

cat <<EOF > /etc/yum.repos.d/cassandra.repo
[cassandra]
name=Apache Cassandra
baseurl=https://www.apache.org/dist/cassandra/redhat/${repo_version}/
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://www.apache.org/dist/cassandra/KEYS
EOF

yum install -y -q cassandra cassandra-tools

echo "### Configuring Cassandra..."

ip_address=`curl http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null`
conf_dir=/etc/cassandra/conf
conf_file=$conf_dir/cassandra.yaml
sed -r -i "/cluster_name/s/Test Cluster/${cluster_name}/" $conf_file
sed -r -i "/seeds/s/127.0.0.1/${seed_name}/" $conf_file
sed -r -i "/listen_address/s/localhost/$ip_address/" $conf_file
sed -r -i "/rpc_address/s/localhost/$ip_address/" $conf_file
sed -r -i "/endpoint_snitch/s/SimpleSnitch/Ec2Snitch/" $conf_file

echo "### Configuring Kernel..."

nofile=`grep nofile /etc/security/limits.d/cassandra.conf | sed 's/.*nofile //'`
ulimit -n $nofile

echo "### Configuring JMX..."

env_file=$conf_dir/cassandra-env.sh
jmx_passwd=/etc/cassandra/jmxremote.password
jmx_access=/etc/cassandra/jmxremote.access

sed -r -i "/rmi.server.hostname/s/^\#//" $env_file
sed -r -i "/rmi.server.hostname/s/.public name./$ip_address/" $env_file
sed -r -i "/jmxremote.access/s/#//" $env_file
sed -r -i "/LOCAL_JMX=/s/yes/no/" $env_file

cat <<EOF > $jmx_passwd
monitorRole QED
controlRole R&D
cassandra cassandra
EOF
chmod 0400 $jmx_passwd
chown cassandra:cassandra $jmx_passwd

cat <<EOF > $jmx_access
monitorRole   readonly
cassandra     readwrite
controlRole   readwrite \
              create javax.management.monitor.*,javax.management.timer.* \
              unregister
EOF
chmod 0400 $jmx_access
chown cassandra:cassandra $jmx_access

chown cassandra:cassandra $conf_dir/*

echo "### Checking cluster prior start..."

start_delay=$((60*(${node_id}-1)))
if [[ $start_delay != 0 ]]; then
  until nc -z ${seed_name} 9042; do
    echo "### ${seed_name} is unavailable - sleeping"
    sleep 5
  done
  echo "### Waiting $start_delay seconds prior starting Cassandra..."
  sleep $start_delay
fi

echo "### Enabling and starting Cassandra..."

systemctl enable cassandra
systemctl start cassandra
