#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

# AWS Template Variables

node_id="${node_id}"
hostname="${hostname}"
domainname="${domainname}"
zookeeper_connect="${zookeeper_connect}"
num_partitions="${num_partitions}"
replication_factor="${replication_factor}"
min_insync_replicas="${min_insync_replicas}"

echo "### Configuring Hostname and Domain..."

ip_address=`curl http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null`
hostnamectl set-hostname --static $hostname
echo "preserve_hostname: true" > /etc/cloud/cloud.cfg.d/99_hostname.cfg
sed -i -r "s/^[#]?Domain =.*/Domain = $domainname/" /etc/idmapd.conf

echo "### Configuring Kafka..."

kafka_data=/data/kafka
mkdir -p $kafka_data

total_mem_in_mb=`free -m | awk '/:/ {print $2;exit}'`
mem_in_mb=`expr $total_mem_in_mb / 2`
if [ "$mem_in_mb" -gt "8192" ]; then
  mem_in_mb="8192"
fi
sed -i -r "/KAFKA_HEAP_OPTS/s/1g/$${mem_in_mb}m/g" /etc/systemd/system/kafka.service

listener_name=`curl http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null`
kafka_cfg=/opt/kafka/config/server.properties

sed -i -r "/^broker.id/s/0/$node_id/" $kafka_cfg
sed -i -r "s|^[#]?listeners=.*|listeners=PLAINTEXT://0.0.0.0:9092|" $kafka_cfg
sed -i -r "s|^[#]?advertised.listeners=.*|advertised.listeners=PLAINTEXT://$listener_name:9092|" $kafka_cfg
sed -i -r "s|^log.dirs=.*|log.dirs=$kafka_data|" $kafka_cfg
sed -i -r "/^num.partitions/s/1/$num_partitions/" $kafka_cfg
sed -i -r "s/^zookeeper.connect=.*/zookeeper.connect=$zookeeper_connect/" $kafka_cfg

cat <<EOF >> $kafka_cfg

# Additional Settings

default.replication.factor=$replication_factor
min.insync.replicas=$min_insync_replicas
auto.create.topics.enable=true
delete.topic.enable=false
controlled.shutdown.enable=true
EOF

password_file=/usr/java/latest/jre/lib/management/jmxremote.password
cat <<EOF > $password_file
monitorRole QED
controlRole R&D
kafka kafka
EOF
chmod 400 $password_file

echo "### Enabling and starting Kafka..."

start_delay=$((60*(${node_id})))
echo "### Waiting $start_delay seconds prior starting Kafka..."
sleep $start_delay

systemctl enable kafka
systemctl start kafka
