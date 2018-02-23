#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# Warning: This is intended to be used through Terraform's template plugin only

# AWS Template Variables
# - node_id = ${node_id}
# - hostname = ${hostname}
# - domainname = ${domainname}
# - zookeeper_connect = ${zookeeper_connect}
# - num_partitions = ${num_partitions}
# - replication_factor = ${replication_factor}
# - min_insync_replicas = ${min_insync_replicas}

echo "### Configuring Hostname and Domain..."

sed -i -r "s/HOSTNAME=.*/HOSTNAME=${hostname}.${domainname}/" /etc/sysconfig/network
hostname ${hostname}.${domainname}
domainname ${domainname}

echo "### Configuring Timezone..."

timezone=America/New_York
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime

echo "### Configuring Kafka..."

kafka_data=/data/kafka
mkdir -p $kafka_data

listener_name=`curl http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null`
kafka_cfg=/opt/kafka/config/server.properties
cp $kafka_cfg $kafka_cfg.bak
cat <<EOF > $kafka_cfg
broker.id=${node_id}
advertised.listeners=PLAINTEXT://$listener_name:9092
listeners=PLAINTEXT://0.0.0.0:9092
log.dirs=$kafka_data
num.partitions=${num_partitions}
default.replication.factor=${replication_factor}
min.insync.replicas=${min_insync_replicas}
log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000
zookeeper.connect=${zookeeper_connect}
zookeeper.connection.timeout.ms=6000
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

systemctl daemon-reload
systemctl enable kafka
systemctl start kafka

systemctl enable snmpd
systemctl start snmpd
