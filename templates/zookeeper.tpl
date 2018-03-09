#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# Warning: This is intended to be used through Terraform's template plugin only

# AWS Template Variables
# - node_id = ${node_id}
# - hostname = ${hostname}
# - domainname = ${domainname}
# - total_servers = ${total_servers}

echo "### Configuring Hostname and Domain..."

sed -i -r "s/HOSTNAME=.*/HOSTNAME=${hostname}.${domainname}/" /etc/sysconfig/network
hostname ${hostname}.${domainname}
domainname ${domainname}

echo "### Configuring Zookeeper..."

zoo_data=/data/zookeeper
mkdir -p $zoo_data
echo ${node_id} > $zoo_data/myid

zoo_cfg=/opt/zookeeper/conf/zoo.cfg
cp $zoo_cfg $zoo_cfg.bak
cat <<EOF > $zoo_cfg
dataDir=$zoo_data
clientPort=2181
maxClientCnxns=0
tickTime=2000
initLimit=10
syncLimit=5
EOF
# TODO Assuming hostname prefix. Make sure it is consistent with zookeeper_ip_addresses in vars.tf
for i in `seq 1 ${total_servers}`;
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

zoo_logs=/opt/zookeeper/logs
mkdir -p $zoo_logs

jmxport=9998

total_mem_in_mb=`free -m | awk '/:/ {print $2;exit}'`
mem_in_mb=`expr $total_mem_in_mb / 2`
if [ "$mem_in_mb" -gt "4096" ]; then
  mem_in_mb="4096"
fi

cat <<EOF > /opt/zookeeper/conf/zookeeper-env.sh
ZOO_LOG_DIR=$zoo_logs
JMXLOCALONLY=false
JMXDISABLE=false
JMXPORT=$jmxport
JMXAUTH=false
JMXSSL=false
JVMFLAGS="-Xmx$${mem_in_mb}m -Xms$${mem_in_mb}m -Djava.rmi.server.hostname=${hostname} -Dcom.sun.management.jmxremote.rmi.port=$jmxport"
EOF

echo "### Enabling and starting Zookeeper..."

start_delay=$((30*(${node_id}-1)))
echo "### Waiting $start_delay seconds prior starting Zookeeper..."
sleep $start_delay

systemctl daemon-reload
systemctl enable zookeeper
systemctl start zookeeper

echo "### Enabling and starting SNMP..."

systemctl enable snmpd
systemctl start snmpd
