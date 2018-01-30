#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# Warning: This is intended to be used through Terraform's template plugin only

# AWS Template Variables
# - node_id
# - vpc_cidr
# - hostname
# - domainname
# - kafka_version
# - scala_version
# - zookeeper_connect
# - num_partitions
# - replication_factor
# - min_insync_replicas

echo "### Configuring Hostname and Domain..."

sed -i -r "s/HOSTNAME=.*/HOSTNAME=${hostname}.${domainname}/" /etc/sysconfig/network
hostname ${hostname}.${domainname}
domainname ${domainname}

echo "### Configuring Timezone..."

timezone=America/New_York
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
sed -i -r "s|ZONE=.*|ZONE=$timezone|" /etc/sysconfig/clock

echo "### Installing common packages..."

yum -y -q update
yum -y -q install jq net-snmp net-snmp-utils git pytz dstat htop sysstat

echo "### Configuring and enabling SNMP..."

snmp_cfg=/etc/snmp/snmpd.conf
cp $snmp_cfg $snmp_cfg.original
cat <<EOF > $snmp_cfg
com2sec localUser ${vpc_cidr} public
group localGroup v1 localUser
group localGroup v2c localUser
view all included .1 80
access localGroup "" any noauth 0 all none none
syslocation AWS
syscontact Account Manager
dontLogTCPWrappersConnects yes
disk /
EOF

chmod 600 $snmp_cfg
chkconfig snmpd on
service snmpd start snmpd

echo "### Downloading and installing Oracle JDK..."

java_url="http://download.oracle.com/otn-pub/java/jdk/8u161-b12/2f38c3b165be4555a1fa6e98c45e0808/jdk-8u161-linux-x64.rpm"
java_rpm=/tmp/jdk8-linux-x64.rpm
wget -c --quiet --header "Cookie: oraclelicense=accept-securebackup-cookie" -O $java_rpm $java_url
if [ ! -s $java_rpm ]; then
  echo "FATAL: Cannot download Java from $java_url. Using OpenNMS default ..."
  yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-stable-rhel7.noarch.rpm
  rpm --import /etc/yum.repos.d/opennms-repo-stable-rhel7.gpg
  yum install -y -q jdk1.8.0_144
  yum erase -y -q opennms-repo-stable
else
  yum install -y -q $java_rpm
  rm -f $java_rpm
fi

echo "### Downloading and installing Kafka..."

cd /opt
kafka_name=kafka_${scala_version}-${kafka_version}
kafka_file=$kafka_name.tgz
kafka_mirror=$$(curl --stderr /dev/null https://www.apache.org/dyn/closer.cgi\?as_json\=1 | jq -r '.preferred')
kafka_url="$${kafka_mirror}kafka/${kafka_version}/$kafka_file"
wget -q "$kafka_url" -O "$kafka_file"
tar xzf $kafka_file
chown -R root:root $kafka_name
ln -s $kafka_name kafka
rm -f $kafka_file

echo "### Configuring Kafka..."

kafka_data=/data/kafka
mkdir -p $kafka_data

listener_name=`curl http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null`
kafka_cfg=/opt/kafka/config/server.properties
cat <<EOF > $kafka_cfg
broker.id=${node_id}
advertised.listeners=PLAINTEXT://$listener_name:9092
listeners=PLAINTEXT://0.0.0.0:9092
delete.topic.enable=true
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
EOF

password_file=/usr/java/latest/jre/lib/management/jmxremote.password
cat <<EOF > $password_file
monitorRole QED
controlRole R&D
kafka kafka
EOF
chmod 400 $password_file

kafka_init_d=/etc/init.d/kafka
cat <<EOF > $kafka_init_d
#!/bin/bash
DAEMON_PATH=/opt/kafka/bin
PATH=\$PATH:\$DAEMON_PATH

export JMX_PORT=9999

pid=\`ps ax | grep -i 'kafka.Kafka' | grep -v grep | awk '{print \$1}'\`

case "\$1" in
  start)
    # Start daemon.
    if [ -n "\$pid" ]; then
      echo "Kafka is already running"
    else
      echo "Starting Kafka"
      \$DAEMON_PATH/kafka-server-start.sh -daemon /opt/kafka/config/server.properties
    fi
    ;;
  stop)
    echo "Shutting down Kafka"
    \$DAEMON_PATH/kafka-server-stop.sh
    ;;
  restart)
    \$0 stop
    sleep 5
    \$0 start
    ;;
  status)
    if [ -n "\$pid" ]; then
      echo "Kafka is Running as PID: \$pid"
    else
      echo "Kafka is not Running"
    fi
    ;;
  *)
    echo "Usage: \$0 {start|stop|restart|status}"
    exit 1
esac

exit 0
EOF

chmod +x $kafka_init_d

echo "### Configuring Kernel..."

nofile=100000
echo <<EOF > /etc/security/limits.d/kafka.conf
* - nofile $nofile
EOF
ulimit -n $nofile

echo "### Enabling and starting Kafka..."

start_delay=$((60*(${node_id}-1)))
echo "### Waiting $start_delay seconds prior starting Kafka..."
sleep $start_delay

chkconfig kafka on
service kafka start
