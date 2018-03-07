#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

zookeeper_version="3.4.11"

########################################

echo "### Downloading and installing Zookeeper..."

zk_name=zookeeper-$zookeeper_version
zk_file=$zk_name.tar.gz
zk_mirror=$(curl --stderr /dev/null https://www.apache.org/dyn/closer.cgi\?as_json\=1 | jq -r '.preferred')
zk_url="${zk_mirror}zookeeper/zookeeper-$zookeeper_version/$zk_file"

cd /opt

sudo wget -q "$zk_url" -O "$zk_file"
sudo tar xzf $zk_file
sudo chown -R root:root $zk_name
sudo ln -s $zk_name zookeeper
sudo rm -f $zk_file

echo "### Configuring Zookeeper..."

systemd_zoo=/etc/systemd/system/zookeeper.service
systemd_tmp=/tmp/zookeeper.service
cat <<EOF > $systemd_tmp
[Unit]
Description=Apache Zookeeper server (Kafka)
Documentation=http://zookeeper.apache.org
Requires=network.target remote-fs.target
After=network.target remote-fs.target

[Service]
Type=forking
User=root
Group=root
ExecStart=/opt/zookeeper/bin/zkServer.sh start
ExecStop=/opt/zookeeper/bin/zkServer.sh stop

[Install]
WantedBy=multi-user.target
EOF
sudo mv $systemd_tmp $systemd_zoo
sudo chmod 0644 $systemd_zoo
