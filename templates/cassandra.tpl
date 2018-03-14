#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# Warning: This is intended to be used through Terraform's template plugin only

# AWS Template Variables
# - node_id = ${node_id}
# - hostname = ${hostname}
# - domainname = ${domainname}
# - cluster_name = ${cluster_name}
# - seed_name = ${seed_name}

echo "### Configuring Hostname and Domain..."

sed -i -r "s/HOSTNAME=.*/HOSTNAME=${hostname}.${domainname}/" /etc/sysconfig/network
hostname ${hostname}.${domainname}
domainname ${domainname}

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
jvm_file=$conf_dir/jvm.options
jmx_passwd=/etc/cassandra/jmxremote.password
jmx_access=/etc/cassandra/jmxremote.access

total_mem_in_mb=`free -m | awk '/:/ {print $2;exit}'`
mem_in_mb=`expr $total_mem_in_mb / 2`
if [ "$mem_in_mb" -gt "30720" ]; then
  mem_in_mb="30720"
fi

sed -r -i "/rmi.server.hostname/s/^\#//" $env_file
sed -r -i "/rmi.server.hostname/s/.public name./$ip_address/" $env_file
sed -r -i "/jmxremote.access/s/#//" $env_file
sed -r -i "/LOCAL_JMX=/s/yes/no/" $env_file
sed -r -i "s/[#]?MAX_HEAP_SIZE=\".*\"/MAX_HEAP_SIZE=\"$${mem_in_mb}m\"/" $env_file
sed -r -i "s/[#]?HEAP_NEWSIZE=\".*\"/HEAP_NEWSIZE=\"$${mem_in_mb}m\"/" $env_file

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
  until echo -n > /dev/tcp/${seed_name}/9042; do
    echo "### ${seed_name} is unavailable - sleeping"
    sleep 5
  done
  echo "### Waiting $start_delay seconds prior starting Cassandra..."
  sleep $start_delay
fi

echo "### Enabling and starting Cassandra..."

systemctl enable cassandra
systemctl start cassandra

echo "### Enabling and starting SNMP..."

systemctl enable snmpd
systemctl start snmpd
