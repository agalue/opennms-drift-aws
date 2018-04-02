#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

# AWS Template Variables

hostname="${hostname}"
domainname="${domainname}"
postgres_onms_url="${postgres_onms_url}"
kafka_servers="${kafka_servers}"
cassandra_servers="${cassandra_servers}"
activemq_url="${activemq_url}"
elastic_url="${elastic_url}"
elastic_user="${elastic_user}"
elastic_password="${elastic_password}"
use_30sec_frequency="${use_30sec_frequency}"

echo "### Configuring Hostname and Domain..."

sed -i -r "s/HOSTNAME=.*/HOSTNAME=$hostname.$domainname/" /etc/sysconfig/network
hostname $hostname.$domainname
domainname $domainname
sed -i -r "s/^[#]?Domain =.*/Domain = $domainname/" /etc/idmapd.conf

echo "### Configuring OpenNMS..."

opennms_home=/opt/opennms
opennms_etc=$opennms_home/etc

# Database connections
postgres_tmpl_url=`echo $postgres_onms_url | sed 's|/opennms|/template1|'`
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
                    url="$postgres_onms_url"
                    user-name="opennms"
                    password="opennms">
    <param name="connectionTimeout" value="0"/>
    <param name="maxLifetime" value="600000"/>
  </jdbc-data-source>

  <jdbc-data-source name="opennms-admin"
                    database-name="template1"
                    class-name="org.postgresql.Driver"
                    url="$postgres_tmpl_url"
                    user-name="postgres"
                    password="postgres" />
</datasource-configuration>
EOF

# Eventd settings
sed -r -i 's/127.0.0.1/0.0.0.0/g' $opennms_etc/eventd-configuration.xml

# JVM Settings
total_mem_in_mb=`free -m | awk '/:/ {print $2;exit}'`
mem_in_mb=`expr $total_mem_in_mb / 2`
if [ "$mem_in_mb" -gt "30720" ]; then
  mem_in_mb="30720"
fi
jmxport=18980
cat <<EOF > $opennms_etc/opennms.conf
START_TIMEOUT=0
JAVA_HEAP_SIZE=$mem_in_mb
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
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Djava.rmi.server.hostname=$hostname"

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
org.opennms.activemq.broker.url=$activemq_url
org.opennms.activemq.broker.username=admin
org.opennms.activemq.broker.password=admin
EOF

# External Kafka
cat <<EOF > $opennms_etc/opennms.properties.d/kafka.properties
org.opennms.core.ipc.sink.initialSleepTime=60000
org.opennms.core.ipc.sink.strategy=kafka
org.opennms.core.ipc.sink.kafka.bootstrap.servers=$kafka_servers
org.opennms.core.ipc.sink.kafka.group.id=OpenNMS
EOF

# External Cassandra
cat <<EOF > $opennms_etc/opennms.properties.d/newts.properties
org.opennms.timeseries.strategy=newts
org.opennms.newts.config.hostname=$cassandra_servers
org.opennms.newts.config.keyspace=newts
org.opennms.newts.config.port=9042
EOF
if [ "$use_30sec_frequency" == "true" ]; then
  cat <<EOF >> $opennms_etc/opennms.properties.d/newts.properties
org.opennms.newts.query.minimum_step=30000
org.opennms.newts.query.heartbeat=45000
EOF
fi
sed -r -i 's/cassandra-username/cassandra/g' $opennms_etc/poller-configuration.xml 
sed -r -i 's/cassandra-password/cassandra/g' $opennms_etc/poller-configuration.xml 
sed -r -i 's/cassandra-username/cassandra/g' $opennms_etc/collectd-configuration.xml 
sed -r -i 's/cassandra-password/cassandra/g' $opennms_etc/collectd-configuration.xml 

# RRD Settings
cat <<EOF > $opennms_etc/opennms.properties.d/rrd.properties
org.opennms.rrd.storeByGroup=true
org.opennms.rrd.storeByForeignSource=true
EOF

# WebUI Settings
cat <<EOF > $opennms_etc/opennms.properties.d/webui.properties
org.opennms.security.disableLoginSuccessEvent=true
EOF

# Enable NetFlow
sed -r -i '/"Netflow-5"/s/false/true/' $opennms_etc/telemetryd-configuration.xml
sed -r -i '/"Netflow-9"/s/false/true/' $opennms_etc/telemetryd-configuration.xml

# Enable IPFIX
sed -r -i '/"IPFIX"/s/false/true/' $opennms_etc/telemetryd-configuration.xml

# Enable SFlow
sed -r -i '/"SFlow"/s/false/true/' $opennms_etc/telemetryd-configuration.xml

# Enable NX-OS
sed -r -i '/"NXOS"/s/false/true/' $opennms_etc/telemetryd-configuration.xml

# Configure Flow persistence
cat <<EOF > $opennms_etc/org.opennms.features.flows.persistence.elastic.cfg
elasticUrl=$elastic_url
elasticGlobalUser=$elastic_user
elasticGlobalPassword=$elastic_password
elasticIndexStrategy=hourly
settings.index.number_of_shards=6
settings.index.number_of_replicas=1
EOF

# Configure Event Exporter
sed -r -i 's/opennms-bundle-refresher/opennms-bundle-refresher, \\\n  opennms-es-rest\n/' $opennms_etc/org.apache.karaf.features.cfg
cat <<EOF > $opennms_etc/org.opennms.plugin.elasticsearch.rest.forwarder.cfg
elasticsearchUrl=$elastic_url
esusername=$elastic_user
espassword=$elastic_password
archiveRawEvents=true
archiveAlarms=false
archiveAlarmChangeEvents=false
logAllEvents=true
retries=1
timeout=3000
EOF

# Enable Path Outages
sed -r -i 's/pathOutageEnabled="false"/pathOutageEnabled="true"/' $opennms_etc/poller-configuration.xml

# Fix PostgreSQL service
sed -r -i 's/"Postgres"/"PostgreSQL"/g' $opennms_etc/poller-configuration.xml 

# Logging
sed -r -i 's/value="DEBUG"/value="WARN"/' $opennms_etc/log4j2.xml
sed -r -i '/manager/s/WARN/DEBUG/' $opennms_etc/log4j2.xml

# WARNING: For testing purposes only
# Lab collection and polling interval (30 seconds)
if [ "$use_30sec_frequency" == "true" ]; then
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
fi

# TODO: the following is due to some issues with the datachoices plugin
cat <<EOF > $opennms_etc/org.opennms.features.datachoices.cfg
enabled=false
acknowledged-by=admin
acknowledged-at=Mon Jan 01 00\:00\:00 EDT 2018
EOF

echo "### Running OpenNMS install script..."

sleep 60
$opennms_home/bin/runjava -S /usr/java/latest/bin/java
$opennms_home/bin/install -dis
$opennms_home/bin/newts init -r ${cassandra_repfactor}

echo "### Enabling and starting OpenNMS Core..."

sleep 120
systemctl daemon-reload
systemctl enable opennms
systemctl start opennms

echo "### Enabling and starting SNMP..."

systemctl enable snmpd
systemctl start snmpd
