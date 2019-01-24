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

device=/dev/xvdb

echo "### Waiting on device $device..."
while [ ! -e $device ]; do
  printf '.'
  sleep 1
done

(
echo o
echo n
echo p
echo 1
echo
echo
echo w
) | fdisk $device
mkfs.xfs -f $device

mount_point=/var/lib/scylla
mv $mount_point $mount_point.empty
mkdir $mount_point
chown scylla:scylla $mount_point
mount -t xfs $device $mount_point
rsync -avr $mount_point.empty/ $mount_point/
echo "$device $mount_point xfs defaults 0 0" >> /etc/fstab

echo "### Configuring ScyllaDB..."

scylla_io_setup

conf_dir=/etc/scylla
conf_file=$conf_dir/scylla.yaml
conf_rackdc=$conf_dir/cassandra-rackdc.properties

sed -r -i "/cluster_name/s/#//" $conf_file
sed -r -i "/cluster_name/s/Test Cluster/$cluster_name/" $conf_file
sed -r -i "/seeds/s/127.0.0.1/$seed_name/" $conf_file
sed -r -i "/listen_address/s/localhost/$ip_address/" $conf_file
sed -r -i "/rpc_address/s/localhost/$ip_address/" $conf_file
sed -r -i "/api_address/s/127.0.0.1/$ip_address/" $conf_file
sed -r -i "/endpoint_snitch/s/SimpleSnitch/GossipingPropertyFileSnitch/" $conf_file

echo "dc=$datacenter" >> $conf_rackdc
echo "rack=$rack" >> $conf_rackdc

echo "### Configuring JMX..."

env_file=$conf_dir/cassandra/cassandra-env.sh
env_default=/etc/default/scylla-jmx
jmx_passwd=/etc/cassandra/jmxremote.password
jmx_access=/etc/cassandra/jmxremote.access

sed -r -i "/SCYLLA_JMX_ADDR/s/^\#//" $env_default
sed -r -i "/SCYLLA_JMX_ADDR/s/localhost/$ip_address/" $env_default
sed -r -i "/SCYLLA_JMX_REMOTE/s/^\#//" $env_default

sed -r -i "/rmi.server.hostname/s/^\#//" $env_file
sed -r -i "/rmi.server.hostname/s/.public name./$ip_address/" $env_file
sed -r -i "/LOCAL_JMX=/s/yes/no/" $env_file

cat <<EOF > $jmx_passwd
monitorRole QED
controlRole R&D
cassandra cassandra
EOF
chmod 0400 $jmx_passwd

cat <<EOF > $jmx_access
monitorRole   readonly
cassandra     readwrite
controlRole   readwrite \
              create javax.management.monitor.*,javax.management.timer.* \
              unregister
EOF
chmod 0400 $jmx_access

echo "### Fixing permissions on $conf_dir..."

chown -R scylla $conf_dir
chown -R scylla /etc/cassandra

echo "### Checking cluster prior start..."

start_delay=$((45*($node_id-1)))
if [[ $start_delay != 0 ]]; then
  until echo -n > /dev/tcp/$seed_name/9042; do
    echo "### $seed_name is unavailable - sleeping"
    sleep 5
  done
  echo "### Waiting $start_delay seconds prior starting ScyllaDB..."
  sleep $start_delay
fi

echo "### Enabling and starting ScyllaDB..."

systemctl enable scylla-server
systemctl start scylla-server
