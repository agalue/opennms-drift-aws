#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# IMPORTANT: It is impossible to downgrade Kafka when using 2.1.

######### CUSTOMIZED VARIABLES #########

scala_version="2.12"
kafka_version="2.1.0"

########################################

echo "### Downloading and installing Kafka version $kafka_version with Scala $scala_version..."

kafka_name=kafka_${scala_version}-${kafka_version}
kafka_file=$kafka_name.tgz
kafka_mirror=$(curl --stderr /dev/null https://www.apache.org/dyn/closer.cgi\?as_json\=1 | jq -r '.preferred')
kafka_url="${kafka_mirror}kafka/$kafka_version/$kafka_file"
kafka_cfg=/opt/kafka/config

cd /opt
sudo wget -q "$kafka_url" -O "$kafka_file"
sudo tar xzf $kafka_file
sudo chown -R root:root $kafka_name
sudo ln -s $kafka_name kafka
sudo rm -f $kafka_file
cd

echo "### Initializing GIT at $kafka_cfg..."

cd $kafka_cfg
sudo git init .
sudo git add .
sudo git commit -m "Kafka $kafka_version installed."
cd

echo "### Configuring Systemd..."

systemd_kafka=/etc/systemd/system/kafka.service
cat <<EOF | sudo tee -a $systemd_kafka
[Unit]
Description=Apache Kafka Server
Documentation=http://kafka.apache.org
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
Group=root
Environment="KAFKA_HEAP_OPTS=-Xmx1g -Xms1g"
Environment="KAFKA_JMX_OPTS=-Dcom.sun.management.jmxremote=true -Dcom.sun.management.jmxremote.rmi.port=9999 -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Djava.rmi.server.hostname=%H -Djava.net.preferIPv4Stack=true"
Environment="JMX_PORT=9999"
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties
ExecStop=/opt/kafka/bin/kafka-server-stop.sh

[Install]
WantedBy=multi-user.target
EOF
sudo chmod 0644 $systemd_kafka

systemd_connect=/etc/systemd/system/connect-distributed.service
cat <<EOF | sudo tee -a $systemd_connect
[Unit]
Description=Apache Kafka Connect: Distributed Mode
Documentation=http://kafka.apache.org
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
Group=root
Environment="KAFKA_HEAP_OPTS=-Xmx1g -Xms1g"
Environment="KAFKA_JMX_OPTS=-Dcom.sun.management.jmxremote=true -Dcom.sun.management.jmxremote.rmi.port=9998 -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Djava.rmi.server.hostname=%H -Djava.net.preferIPv4Stack=true"
Environment="JMX_PORT=9998"
ExecStart=/opt/kafka/bin/connect-distributed.sh /opt/kafka/config/connect-distributed.properties
ExecStop=/opt/kafka/bin/kafka-server-stop.sh

[Install]
WantedBy=multi-user.target
EOF
sudo chmod 0644 $systemd_connect

systemd_zoo=/etc/systemd/system/zookeeper.service
cat <<EOF | sudo tee -a $systemd_zoo
[Unit]
Description=Apache Zookeeper server
Documentation=http://zookeeper.apache.org
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
Group=root
Environment="KAFKA_HEAP_OPTS=-Xmx1g -Xms1g"
Environment="KAFKA_JMX_OPTS=-Dcom.sun.management.jmxremote=true -Dcom.sun.management.jmxremote.rmi.port=9997 -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Djava.rmi.server.hostname=%H -Djava.net.preferIPv4Stack=true"
Environment="JMX_PORT=9997"
ExecStart=/opt/kafka/bin/zookeeper-server-start.sh /opt/kafka/config/zookeeper.properties
ExecStop=/opt/kafka/bin/zookeeper-server-stop.sh

[Install]
WantedBy=multi-user.target
EOF
sudo chmod 0644 $systemd_zoo

sudo systemctl daemon-reload

cat <<EOF | sudo tee -a /etc/profile.d/kafka.sh
PATH=/opt/kafka/bin:\$PATH
EOF

echo "### Configuring Kernel..."

nofile=100000
echo <<EOF | sudo tee -a /etc/security/limits.d/kafka.conf
* - nofile $nofile
EOF
