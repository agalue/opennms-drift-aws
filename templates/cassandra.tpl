#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

# AWS Template Variables

node_id="${node_id}"
hostname="${hostname}"
domainname="${domainname}"
cluster_name="${cluster_name}"
seed_name="${seed_name}"
datacenter="${datacenter}"
rack="${rack}"

echo "### Configuring Hostname and Domain..."

ip_address=$(curl http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null)
hostnamectl set-hostname --static $hostname
echo "preserve_hostname: true" > /etc/cloud/cloud.cfg.d/99_hostname.cfg
sed -i -r "s/^[#]?Domain =.*/Domain = $domainname/" /etc/idmapd.conf

echo "### Configuring Cassandra..."

conf_dir=/etc/cassandra/conf
conf_file=$conf_dir/cassandra.yaml
conf_rackdc=$conf_dir/cassandra-rackdc.properties

sed -r -i "/cluster_name/s/Test Cluster/$cluster_name/" $conf_file
sed -r -i "/seeds/s/127.0.0.1/$seed_name/" $conf_file
sed -r -i "/listen_address/s/localhost/$ip_address/" $conf_file
sed -r -i "/rpc_address/s/localhost/$ip_address/" $conf_file
sed -r -i "/endpoint_snitch/s/SimpleSnitch/GossipingPropertyFileSnitch/" $conf_file

echo "### Configuring JMX..."

env_file=$conf_dir/cassandra-env.sh
jvm_file=$conf_dir/jvm.options

jmx_passwd=/etc/cassandra/jmxremote.password
jmx_access=/etc/cassandra/jmxremote.access

total_mem_in_mb=$(free -m | awk '/:/ {print $2;exit}')
mem_in_mb=$(expr $total_mem_in_mb / 2)
if [ "$mem_in_mb" -gt "30720" ]; then
  mem_in_mb="30720"
fi

# Update Rack Properties
sed -r -i "s/dc1/$datacenter/" $conf_rackdc
sed -r -i "s/rack1/$rack/" $conf_rackdc

# Cassandra JVM Environment Configuration
sed -r -i "/rmi.server.hostname/s/^\#//" $env_file
sed -r -i "/rmi.server.hostname/s/.public name./$ip_address/" $env_file
sed -r -i "/jmxremote.access/s/#//" $env_file
sed -r -i "/LOCAL_JMX=/s/yes/no/" $env_file
sed -r -i "s/^[#]?MAX_HEAP_SIZE=\".*\"/MAX_HEAP_SIZE=\"$${mem_in_mb}m\"/" $env_file
sed -r -i "s/^[#]?HEAP_NEWSIZE=\".*\"/HEAP_NEWSIZE=\"$${mem_in_mb}m\"/" $env_file

# Disable CMSGC
sed -r -i "/UseParNewGC/s/-XX/#-XX/" $jvm_file
sed -r -i "/UseConcMarkSweepGC/s/-XX/#-XX/" $jvm_file
sed -r -i "/CMSParallelRemarkEnabled/s/-XX/#-XX/" $jvm_file
sed -r -i "/SurvivorRatio/s/-XX/#-XX/" $jvm_file
sed -r -i "/MaxTenuringThreshold/s/-XX/#-XX/" $jvm_file
sed -r -i "/CMSInitiatingOccupancyFraction/s/-XX/#-XX/" $jvm_file
sed -r -i "/UseCMSInitiatingOccupancyOnly/s/-XX/#-XX/" $jvm_file
sed -r -i "/CMSWaitDuration/s/-XX/#-XX/" $jvm_file
sed -r -i "/CMSParallelInitialMarkEnabled/s/-XX/#-XX/" $jvm_file
sed -r -i "/CMSEdenChunksRecordAlways/s/-XX/#-XX/" $jvm_file
sed -r -i "/CMSClassUnloadingEnabled/s/-XX/#-XX/" $jvm_file

# Enable G1GC
sed -r -i "/UseG1GC/s/#-XX/-XX/" $jvm_file
sed -r -i "/G1RSetUpdatingPauseTimePercent/s/#-XX/-XX/" $jvm_file
sed -r -i "/MaxGCPauseMillis/s/#-XX/-XX/" $jvm_file
sed -r -i "/InitiatingHeapOccupancyPercent/s/#-XX/-XX/" $jvm_file
sed -r -i "/ParallelGCThreads/s/#-XX/-XX/" $jvm_file

# JMX Auth: passwords
cat <<EOF > $jmx_passwd
monitorRole QED
controlRole R&D
cassandra cassandra
EOF
chmod 0400 $jmx_passwd
chown cassandra:cassandra $jmx_passwd

# JMX Auth: access
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

start_delay=$((45*($node_id-1)))
if [[ $start_delay != 0 ]]; then
  until echo -n > /dev/tcp/$seed_name/9042; do
    echo "### $seed_name is unavailable - sleeping"
    sleep 5
  done
  echo "### Waiting $start_delay seconds prior starting Cassandra..."
  sleep $start_delay
fi

echo "### Enabling and starting Cassandra..."

systemctl enable cassandra
systemctl start cassandra
