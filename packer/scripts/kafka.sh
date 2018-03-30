#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

scala_version="2.11"
kafka_version="1.1.0"

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
[Unit]
Description=Apache Kafka server
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
sudo cp $systemd_tmp $systemd_kafka
sudo chmod 0644 $systemd_kafka

systemd_zoo=/etc/systemd/system/zookeeper.service
systemd_tmp=/tmp/zookeeper.service
cat <<EOF > $systemd_tmp
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
Environment="KAFKA_JMX_OPTS=-Dcom.sun.management.jmxremote=true -Dcom.sun.management.jmxremote.rmi.port=9998 -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Djava.rmi.server.hostname=%H -Djava.net.preferIPv4Stack=true"
Environment="JMX_PORT=9998"
ExecStart=/opt/kafka/bin/zookeeper-server-start.sh /opt/kafka/config/zookeeper.properties
ExecStop=/opt/kafka/bin/zookeeper-server-stop.sh

[Install]
WantedBy=multi-user.target
EOF
sudo mv $systemd_tmp $systemd_zoo
sudo chmod 0644 $systemd_zoo

sudo systemctl daemon-reload

echo "### Configuring Kernel..."

limits=/tmp/kafka.conf
nofile=100000
echo <<EOF > $limits
* - nofile $nofile
EOF
sudo mv $limits /etc/security/limits.d/
