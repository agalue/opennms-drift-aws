#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

scala_version="2.12"
kafka_version="1.0.0"

########################################

echo "### Downloading and installing Kafka..."

kafka_name=kafka_${scala_version}-${kafka_version}
kafka_file=$kafka_name.tgz
kafka_mirror=$(curl --stderr /dev/null https://www.apache.org/dyn/closer.cgi\?as_json\=1 | jq -r '.preferred')
kafka_url="${kafka_mirror}kafka/$kafka_version/$kafka_file"

cd /opt

sudo wget -q "$kafka_url" -O "$kafka_file"
sudo tar xzf $kafka_file
sudo chown -R root:root $kafka_name
sudo ln -s $kafka_name kafka
sudo rm -f $kafka_file

systemd_kafka=/etc/systemd/system/kafka.service
systemd_tmp=/tmp/kafka.service
cat <<EOF > $systemd_tmp
# Inspired by https://github.com/thmshmm/confluent-systemd

[Unit]
Description=Apache Kafka server (broker)
Documentation=http://kafka.apache.org/documentation.html
Requires=network.target remote-fs.target
After=network.target remote-fs.target zookeeper.service

[Service]
Type=forking
User=root
Group=root
Environment="KAFKA_JMX_OPTS=-Dcom.sun.management.jmxremote=true -Dcom.sun.management.jmxremote.rmi.port=9999 -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Djava.rmi.server.hostname=%H -Djava.net.preferIPv4Stack=true"
Environment="JMX_PORT=9999"
# Uncomment the following line to enable authentication for the broker
# Environment="KAFKA_OPTS=-Djava.security.auth.login.config=/etc/kafka/kafka-jaas.conf"
ExecStart=/opt/kafka/bin/kafka-server-start.sh -daemon /opt/kafka/config/server.properties
ExecStop=/opt/kafka/bin/kafka-server-stop.sh

[Install]
WantedBy=multi-user.target
EOF
sudo cp $systemd_tmp $systemd_kafka
sudo chmod 0644 $systemd_kafka

echo "### Configuring Kernel..."

limits=/tmp/kafka.conf
nofile=100000
echo <<EOF > $limits
* - nofile $nofile
EOF
sudo mv $limits /etc/security/limits.d/
