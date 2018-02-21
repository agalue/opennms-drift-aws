#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# Warning: This is intended to be used through Terraform's template plugin only

# AWS Template Variables
# - vpc_cidr = ${vpc_cidr}
# - hostname = ${hostname}
# - domainname = ${domainname}
# - onms_repo = ${onms_repo}
# - onms_version = ${onms_version}
# - postgres_server = ${postgres_server}
# - kafka_servers = ${kafka_servers}
# - cassandra_servers = ${cassandra_servers}
# - cassandra_repfactor = ${cassandra_repfactor}
# - activemq_url = ${activemq_url}
# - elastic_url = ${elastic_url}
# - elastic_user = ${elastic_user}
# - elastic_password = ${elastic_password}

echo "### Configuring Hostname and Domain..."

sed -i -r "s/HOSTNAME=.*/HOSTNAME=${hostname}.${domainname}/" /etc/sysconfig/network
hostname ${hostname}.${domainname}
domainname ${domainname}
sed -i -r "s/#Domain =.*/Domain = ${domainname}/" /etc/idmapd.conf

echo "### Configuring Timezone..."

timezone=America/New_York
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
sed -i -r "s|ZONE=.*|ZONE=$timezone|" /etc/sysconfig/clock

echo "### Installing common packages..."

yum -y -q update
yum -y -q install jq net-snmp net-snmp-utils git pytz dstat htop sysstat nmap-ncat

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
systemctl enable snmpd
systemctl start snmpd

echo "### Downloading and installing Oracle JDK..."

java_url="http://download.oracle.com/otn-pub/java/jdk/8u161-b12/2f38c3b165be4555a1fa6e98c45e0808/jdk-8u161-linux-x64.rpm"
java_rpm=/tmp/jdk8-linux-x64.rpm
wget -c --quiet --header "Cookie: oraclelicense=accept-securebackup-cookie" -O $java_rpm $java_url
if [ ! -s $java_rpm ]; then
  echo "FATAL: Cannot download Java from $java_url. Using OpenNMS default ..."
else
  yum install -y -q $java_rpm
  rm -f $java_rpm
fi

echo "### Installing OpenNMS Dependencies from stable repository..."

sed -r -i '/name=Amazon Linux 2/a exclude=rrdtool-*' /etc/yum.repos.d/amzn2-core.repo
yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-stable-rhel7.noarch.rpm
rpm --import /etc/yum.repos.d/opennms-repo-stable-rhel7.gpg
yum install -y -q jicmp jicmp6 jrrd jrrd2 rrdtool 'perl(LWP)' 'perl(XML::Twig)'

if [ "${onms_repo}" != "stable" ]; then
  echo "### Installing OpenNMS ${onms_repo} Repository..."
  yum remove -y -q opennms-repo-stable
  yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-${onms_repo}-rhel7.noarch.rpm
  rpm --import /etc/yum.repos.d/opennms-repo-${onms_repo}-rhel7.gpg
fi

if [ "${onms_version}" == "-latest-" ]; then
  echo "### Installing latest OpenNMS from ${onms_repo} Repository..."
  yum install -y -q opennms-core opennms-webapp-jetty
else
  echo "### Installing OpenNMS version ${onms_version} from ${onms_repo} Repository..."
  yum install -y -q opennms-core-${onms_version} opennms-webapp-jetty-${onms_version}
fi

echo "### Installing GIT..."

opennms_home=/opt/opennms
opennms_etc=$opennms_home/etc

cd $opennms_etc
git config --global user.name "Alejandro Galue"
git config --global user.email "agalue@opennms.org"
git init .
git add .
git commit -m "OpenNMS Installed."
cd

echo "### Installing Hawtio..."

hawtio_url=https://oss.sonatype.org/content/repositories/public/io/hawt/hawtio-default/1.4.63/hawtio-default-1.4.63.war
wget -qO $opennms_home/jetty-webapps/hawtio.war $hawtio_url && \
  unzip -qq $opennms_home/jetty-webapps/hawtio.war -d $opennms_home/jetty-webapps/hawtio && \
  rm -f $opennms_home/jetty-webapps/hawtio.war

echo "### Configuring OpenNMS..."

# Database connections
cat <<EOF > $opennms_etc/opennms-datasources.xml
<?xml version="1.0" encoding="UTF-8"?>
<datasource-configuration xmlns:this="http://xmlns.opennms.org/xsd/config/opennms-datasources"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://xmlns.opennms.org/xsd/config/opennms-datasources
  http://www.opennms.org/xsd/config/opennms-datasources.xsd ">

  <connection-pool factory="org.opennms.core.db.HikariCPConnectionFactory"
    idleTimeout="600"
    loginTimeout="3"
    minPool="50"
    maxPool="50"
    maxSize="50" />

  <jdbc-data-source name="opennms"
                    database-name="opennms"
                    class-name="org.postgresql.Driver"
                    url="jdbc:postgresql://${postgres_server}:5432/opennms"
                    user-name="opennms"
                    password="opennms">
    <param name="connectionTimeout" value="0"/>
  </jdbc-data-source>

  <jdbc-data-source name="opennms-admin"
                    database-name="template1"
                    class-name="org.postgresql.Driver"
                    url="jdbc:postgresql://${postgres_server}:5432/template1"
                    user-name="postgres"
                    password="postgres" />
</datasource-configuration>
EOF

# Eventd settings
sed -r -i 's/127.0.0.1/0.0.0.0/g' $opennms_etc/eventd-configuration.xml

# JVM Settings
mem_in_mb=`free -m | awk '/:/ {print $2;exit}'`
half_mem_in_mb=`expr $mem_in_mb / 2`
jmxport=18980
cat <<EOF > $opennms_etc/opennms.conf
START_TIMEOUT=0
JAVA_HEAP_SIZE=$half_mem_in_mb
MAXIMUM_FILE_DESCRIPTORS=204800

ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+UseG1GC -XX:+UseStringDeduplication"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -d64 -XX:+PrintGCTimeStamps -XX:+PrintGCDetails"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Xloggc:$opennms_home/logs/gc.log"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+UnlockCommercialFeatures -XX:+FlightRecorder"

# Configure Remote JMX
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.port=$jmxport"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.rmi.port=$jmxport"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.local.only=false"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.ssl=false"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.authenticate=true"

# Listen on all interfaces
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dopennms.poller.server.serverHost=0.0.0.0"

# Accept remote RMI connections on this interface
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Djava.rmi.server.hostname=${hostname}"

# If you enable Flight Recorder, be aware of the implications since it is a commercial feature of the Oracle JVM.
#ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:StartFlightRecording=duration=600s,filename=opennms.jfr,delay=1h"
EOF

# JMX Groups
cat <<EOF > $opennms_etc/jmxremote.access
admin readwrite
jmx   readonly
EOF

# External ActiveMQ
cat <<EOF > $opennms_etc/opennms.properties.d/amq.properties
org.opennms.activemq.broker.disable=true
org.opennms.activemq.broker.url=${activemq_url}
org.opennms.activemq.broker.username=admin
org.opennms.activemq.broker.password=admin
EOF

# External Kafka
cat <<EOF > $opennms_etc/opennms.properties.d/kafka.properties
org.opennms.core.ipc.sink.initialSleepTime=60000
org.opennms.core.ipc.sink.strategy=kafka
org.opennms.core.ipc.sink.kafka.bootstrap.servers=${kafka_servers}
org.opennms.core.ipc.sink.kafka.group.id=OpenNMS
EOF

# External Cassandra
cat <<EOF > $opennms_etc/opennms.properties.d/newts.properties
org.opennms.timeseries.strategy=newts
org.opennms.newts.config.hostname=${cassandra_servers}
org.opennms.newts.config.keyspace=newts
org.opennms.newts.config.port=9042
org.opennms.newts.query.minimum_step=30000
org.opennms.newts.query.heartbeat=45000
EOF
sed -r -i 's/cassandra-username/cassandra/g' $opennms_etc/poller-configuration.xml 
sed -r -i 's/cassandra-password/cassandra/g' $opennms_etc/poller-configuration.xml 
sed -r -i 's/cassandra-username/cassandra/g' $opennms_etc/collectd-configuration.xml 
sed -r -i 's/cassandra-password/cassandra/g' $opennms_etc/collectd-configuration.xml 

# RRD Settings
cat <<EOF > $opennms_etc/opennms.properties.d/rrd.properties
org.opennms.rrd.storeByGroup=true
org.opennms.rrd.storeByForeignSource=true
EOF

# Enable NetFlow
sed -r -i '/"Netflow-5"/s/false/true/' $opennms_etc/telemetryd-configuration.xml

# Enable NX-OS
sed -r -i '/"NXOS"/s/false/true/' $opennms_etc/telemetryd-configuration.xml

# Configure Flow persistence
cat <<EOF > $opennms_etc/org.opennms.features.flows.persistence.elastic.cfg
elasticUrl=${elastic_url}
elasticGlobalUser=${elastic_user}
elasticGlobalPassword=${elastic_password}
EOF

# Configure Event Exporter
sed -r -i 's/opennms-bundle-refresher/opennms-bundle-refresher, \\\n  opennms-es-rest\n/' $opennms_etc/org.apache.karaf.features.cfg
cat <<EOF > $opennms_etc/org.opennms.plugin.elasticsearch.rest.forwarder.cfg
elasticsearchUrl=${elastic_url}
esusername=${elastic_user}
espassword=${elastic_password}
archiveRawEvents=true
archiveAlarms=false
archiveAlarmChangeEvents=false
retries=1
timeout=3000
EOF

# Enable Path Outages
sed -r -i 's/pathOutageEnabled="false"/pathOutageEnabled="true"/' $opennms_etc/poller-configuration.xml

# Fix PostgreSQL service
sed -r -i 's/"Postgres"/"PostgreSQL"/g' $opennms_etc/poller-configuration.xml 

# WARNING: For testing purposes only
# Lab collection and polling interval (30 seconds)
sed -r -i 's/step="300"/step="30"/g' $opennms_etc/telemetryd-configuration.xml 
sed -r -i 's/interval="300000"/interval="30000"/g' $opennms_etc/collectd-configuration.xml 
sed -r -i 's/interval="300000" user/interval="30000" user/g' $opennms_etc/poller-configuration.xml 
sed -r -i 's/step="300"/step="30"/g' $opennms_etc/poller-configuration.xml 
files=(`ls -l $opennms_etc/*datacollection-config.xml | awk '{print $9}'`)
for f in "$${files[@]}"; do
  if [ -f $f ]; then
    sed -r -i 's/step="300"/step="30"/g' $f
  fi
done

# TODO: the following is due to some issues with the datachoices plugin
cat <<EOF > $opennms_etc/org.opennms.features.datachoices.cfg
enabled=false
acknowledged-by=admin
acknowledged-at=Mon Jan 01 00\:00\:00 EDT 2018
EOF

echo "### Configuring OpenNMS Jetty Server..."

# Enabling CORS...
webxml=$opennms_home/jetty-webapps/opennms/WEB-INF/web.xml
cp $webxml $webxml.bak
sed -r -i '/[<][!]--/{$!{N;s/[<][!]--\n  ([<]filter-mapping)/\1/}}' $webxml
sed -r -i '/nrt/{$!{N;N;s/(nrt.*\n  [<]\/filter-mapping[>])\n  --[>]/\1/}}' $webxml

echo "### Configuring NFS..."

# TODO Using the server itself as NFS server
cat <<EOF > /etc/exports
/opt/opennms/etc ${vpc_cidr}(rw,sync,no_root_squash)
EOF
systemctl enable nfs
systemctl start nfs

echo "### Running OpenNMS install script..."

$opennms_home/bin/runjava -S /usr/java/latest/bin/java
$opennms_home/bin/install -dis
$opennms_home/bin/newts init -r ${cassandra_repfactor}

echo "### Enabling and starting OpenNMS Core..."

systemctl daemon-reload
systemctl enable opennms
systemctl start opennms
