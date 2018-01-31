#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# Warning: This is intended to be used through Terraform's template plugin only

# AWS Template Variables
# - node_id
# - vpc_cidr
# - hostname
# - domainname
# - total_servers
# - zookeeper_version

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

echo "### Downloading and installing Zookeeper..."

cd /opt
zk_name=zookeeper-${zookeeper_version}
zk_file=$zk_name.tar.gz
zk_mirror=$$(curl --stderr /dev/null https://www.apache.org/dyn/closer.cgi\?as_json\=1 | jq -r '.preferred')
zk_url="$${zk_mirror}zookeeper/zookeeper-${zookeeper_version}/$zk_file"
wget -q "$zk_url" -O "$zk_file"
tar xzf $zk_file
chown -R root:root $zk_name
ln -s $zk_name zookeeper
rm -f $zk_file

echo "### Configuring Zookeeper..."

zoo_init_d=/etc/init.d/zookeeper
cat <<EOF > $zoo_init_d
#!/bin/sh
#
# chkconfig: 345 99 01
# description: Zookeeper Server
#
### BEGIN INIT INFO
# Provides: zookeeper
# Required-Start: $local_fs $network
# Required-Stop: $local_fs $network
# Default-Start: 3 5
# Default-Stop: 0 1 2 6
# Description: Zookeeper Server
# Short-Description: Zookeeper Server
### END INIT INFO

USER=root
PROG=zookeeper
DAEMON_PATH=/opt/zookeeper/bin
DAEMON_NAME=zkServer.sh
PATH=\$PATH:\$DAEMON_PATH

pid=\`ps ax | grep -i 'zookeeper.server' | grep -v grep | awk '{print \$1}'\`

case "\$1" in
  start)
    if [ -n "\$pid" ]; then
      echo "\$PROG is already running"
    else
      echo -n "Starting \$PROG: ";echo
      /bin/su \$USER \$DAEMON_PATH/\$DAEMON_NAME start
    fi
    ;;
  stop)
    echo -n "Stopping \$PROG: ";echo
    /bin/su \$USER \$DAEMON_PATH/\$DAEMON_NAME stop
    ;;
  status)
    if [ -n "\$pid" ]; then
      echo "\$PROG is Running as PID: \$pid"
    else
      echo "\$PROG is not Running"
    fi
    /bin/su \$USER \$DAEMON_PATH/\$DAEMON_NAME status
    ;;
  restart)
    \$0 stop
    sleep 5
    \$0 start
    ;;
  *)
    echo "Usage: \$0 {start|stop|status|restart}"
    exit 1
esac
exit 0
EOF
chmod +x $zoo_init_d

zoo_data=/data/zookeeper
mkdir -p $zoo_data
echo ${node_id} > $zoo_data/myid

zoo_cfg=/opt/zookeeper/conf/zoo.cfg
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

jmxport=9998
cat <<EOF > /opt/zookeeper/conf/zookeeper-env.sh
JMXLOCALONLY=false
JMXDISABLE=false
JMXPORT=$jmxport
JMXAUTH=false
JMXSSL=false
JVMFLAGS="-Djava.rmi.server.hostname=${hostname} -Dcom.sun.management.jmxremote.rmi.port=$jmxport"
EOF

echo "### Enabling and starting Zookeeper..."

start_delay=$((60*(${node_id}-1)))
echo "### Waiting $start_delay seconds prior starting Zookeeper..."
sleep $start_delay

chkconfig zookeeper on
service zookeeper start
