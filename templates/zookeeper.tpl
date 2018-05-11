#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

# AWS Template Variables

node_id="${node_id}"
hostname="${hostname}"
domainname="${domainname}"
total_servers="${total_servers}"

echo "### Configuring Hostname and Domain..."

ip_address=`curl http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null`
hostnamectl set-hostname --static $hostname
echo "preserve_hostname: true" > /etc/cloud/cloud.cfg.d/99_hostname.cfg
sed -i -r "s/^[#]?Domain =.*/Domain = $domainname/" /etc/idmapd.conf

echo "### Configuring Zookeeper..."

zoo_data=/data/zookeeper
mkdir -p $zoo_data
echo $node_id > $zoo_data/myid

zoo_cfg=/opt/kafka/config/zookeeper.properties

sed -i -r "s|dataDir=.*|dataDir=$zoo_data|" $zoo_cfg

cat <<EOF >> $zoo_cfg
# Additional Settings
tickTime=2000
initLimit=10
syncLimit=5
EOF

# TODO Assuming hostname prefix. Make sure it is consistent with zookeeper_ip_addresses in vars.tf
for i in `seq 1 $total_servers`;
do
  echo "server.$i=zookeeper$i:2888:3888" >> $zoo_cfg
done

password_file=/usr/java/latest/jre/lib/management/jmxremote.password
cat <<EOF > $password_file
monitorRole QED
controlRole R&D
zookeeper zookeeper
EOF
chmod 400 $password_file

total_mem_in_mb=`free -m | awk '/:/ {print $2;exit}'`
mem_in_mb=`expr $total_mem_in_mb / 2`
if [ "$mem_in_mb" -gt "4096" ]; then
  mem_in_mb="4096"
fi
sed -i -r "/KAFKA_HEAP_OPTS/s/1g/$${mem_in_mb}m/g" /etc/systemd/system/zookeeper.service

echo "### Enabling and starting Zookeeper..."

start_delay=$((30*($node_id-1)))
echo "### Waiting $start_delay seconds prior starting Zookeeper..."
sleep $start_delay

systemctl enable zookeeper
systemctl start zookeeper
