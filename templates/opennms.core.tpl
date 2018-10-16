#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

# AWS Template Variables

hostname="${hostname}"
domainname="${domainname}"
dependencies="${dependencies}"
postgres_onms_url="${postgres_onms_url}"
activemq_url="${activemq_url}"
kafka_servers="${kafka_servers}"
kafka_security_protocol="${kafka_security_protocol}"
kafka_security_module="${kafka_security_module}"
kafka_client_mechanism="${kafka_client_mechanism}"
kafka_user_name="${kafka_user_name}"
kafka_user_password="${kafka_user_password}"
cassandra_seed="${cassandra_seed}"
cassandra_datacenter="${cassandra_datacenter}"
cassandra_repfactor="${cassandra_repfactor}"
opennms_ui_servers="${opennms_ui_servers}"
elastic_url="${elastic_url}"
elastic_user="${elastic_user}"
elastic_password="${elastic_password}"
use_redis="${use_redis}"
use_30sec_frequency="${use_30sec_frequency}"

echo "### Configuring Hostname and Domain..."

ip_address=`curl http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null`
hostnamectl set-hostname --static $hostname
echo "preserve_hostname: true" > /etc/cloud/cloud.cfg.d/99_hostname.cfg
sed -i -r "s/^[#]?Domain =.*/Domain = $domainname/" /etc/idmapd.conf

# Redis

if [[ "$use_redis" == "true" ]]; then
  echo "### Configuring Redis..."

  echo "vm.overcommit_memory=1" > /etc/sysctl.d/redis.conf
  sysctl -w vm.overcommit_memory=1
  redis_conf=/etc/redis.conf
  cp $redis_conf $redis_conf.bak
  sed -i -r "s/^bind .*/bind 0.0.0.0/" $redis_conf
  sed -i -r "s/^protected-mode .*/protected-mode no/" $redis_conf
  sed -i -r "s/^save /# save /" $redis_conf
  sed -i -r "s/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/" $redis_conf

  systemctl enable redis
  systemctl start redis
fi

echo "### Configuring OpenNMS..."

opennms_home=/opt/opennms
opennms_etc=$opennms_home/etc

# Database connections

postgres_tmpl_url=`echo $postgres_onms_url | sed 's|/opennms|/template1|'`
onms_url=`echo $postgres_onms_url | sed 's|[&]|\\\\&|'`
tmpl_url=`echo $postgres_tmpl_url | sed 's|[&]|\\\\&|'`
sed -r -i "/jdbc.*opennms/s|url=\".*\"|url=\"$onms_url\"|" $opennms_etc/opennms-datasources.xml
sed -r -i "/jdbc.*template1/s|url=\".*\"|url=\"$tmpl_url\"|" $opennms_etc/opennms-datasources.xml

# JVM Settings

num_of_cores=`cat /proc/cpuinfo | grep "^processor" | wc -l`
half_of_cores=`expr $num_of_cores / 2`
total_mem_in_mb=`free -m | awk '/:/ {print $2;exit}'`
mem_in_mb=`expr $total_mem_in_mb / 2`
if [ "$mem_in_mb" -gt "30720" ]; then
  mem_in_mb="30720"
fi
sed -i -r "/JAVA_HEAP_SIZE/s/=1024/=$mem_in_mb/" $opennms_etc/opennms.conf
sed -i -r "/GCThreads/s/=2/=$half_of_cores/" $opennms_etc/opennms.conf
sed -i -r "/rmi.server.hostname/s/=0.0.0.0/=$hostname/" $opennms_etc/opennms.conf

# JMX Polling/Collection Settings

IFS=',' read -r -a ip_list <<< "$opennms_ui_servers"
ip_list+=($ip_address)
echo "<jmx-config>" > $opennms_etc/jmx-config.xml
for ip in "$${ip_list[@]}"
do
  cat <<EOF >> $opennms_etc/jmx-config.xml
  <mbean-server ipAddress="$ip" port="18980">
    <parameter key="factory" value="PASSWORD-CLEAR"/>
    <parameter key="username" value="admin"/>
    <parameter key="password" value="admin"/>
  </mbean-server>
EOF
done
echo "</jmx-config>" >> $opennms_etc/jmx-config.xml

cat <<EOF > onmsjvm.txt
         <parameter key="factory" value="PASSWORD-CLEAR"/>
         <parameter key="username" value="admin"/>
         <parameter key="password" value="admin"/>
EOF
sed -r -i '/service name="OpenNMS-JVM"/r onmsjvm.txt' $opennms_etc/poller-configuration.xml
rm -f onmsjvm.txt

# Adding additional Karaf Features

features="opennms-es-rest, opennms-kafka-producer"
sed -r -i "s/opennms-bundle-refresher.*/opennms-bundle-refresher, $features/" $opennms_etc/org.apache.karaf.features.cfg

# Exposing Karaf Console

sed -r -i '/sshHost/s/127.0.0.1/0.0.0.0/' $opennms_etc/org.apache.karaf.shell.cfg

# Sink Pattern with Kafka

cat <<EOF > $opennms_etc/opennms.properties.d/kafka-sink.properties
org.opennms.core.ipc.sink.initialSleepTime=60000
org.opennms.core.ipc.sink.strategy=kafka
org.opennms.core.ipc.sink.kafka.bootstrap.servers=$kafka_servers
org.opennms.core.ipc.sink.kafka.group.id=OpenNMS
org.opennms.core.ipc.sink.kafka.security.protocol=$kafka_security_protocol
org.opennms.core.ipc.sink.kafka.sasl.mechanism=$kafka_client_mechanism
org.opennms.core.ipc.sink.kafka.sasl.jaas.config=$kafka_security_module required username="$kafka_user_name" password="$kafka_user_password";
EOF

# RPC Threads

cat <<EOF > $opennms_etc/opennms.properties.d/rpc.properties
org.opennms.jms.timeout=60000
org.opennms.ipc.rpc.threads=1
org.opennms.ipc.rpc.queue.max=50000
org.opennms.ipc.rpc.threads.max=100
EOF

# RPC Pattern

if [ "$activemq_url" != "" ]; then
  if [ "$activemq_url" == "127.0.0.1" ]; then
    amq_file=$opennms_etc/opennms-activemq.xml
    sed -r -i '/0.0.0.0:61616/s/[<][!]--//' $amq_file
    sed -r -i '/0.0.0.0:61616/s/--[>]//' $amq_file
    sed -r -i '/memoryUsage limit/s/=".*"/="512 mb"/' $amq_file
    sed -r -i '/tempUsage limit/s/=".*"/="512 mb"/' $amq_file
  else
    cat <<EOF > $opennms_etc/opennms.properties.d/amq.properties
org.opennms.activemq.broker.disable=true
org.opennms.activemq.broker.url=$activemq_url
org.opennms.activemq.broker.username=admin
org.opennms.activemq.broker.password=admin
EOF
  fi
  cat <<EOF >> $opennms_etc/opennms.properties.d/amq.properties
# For pooledConnectionFactory from applicationContext-daemon.xml
org.opennms.activemq.client.max-connections=8
org.opennms.activemq.client.idle-timeout=30000
org.opennms.activemq.client.reconnect-on-exception=true
org.opennms.activemq.client.concurrent-consumers=10
EOF
else
  # TODO: Verify if this is possible, to avoid waste resources if ActiveMQ won't be used 
  cat <<EOF > $opennms_etc/opennms.properties.d/amq.properties
org.opennms.activemq.broker.disable=true
EOF
  cat <<EOF > $opennms_etc/opennms.properties.d/kafka-rpc.properties
org.opennms.core.ipc.rpc.strategy=kafka
org.opennms.core.ipc.rpc.kafka.bootstrap.servers=$kafka_servers
org.opennms.core.ipc.rpc.kafka.ttl=30000
org.opennms.core.ipc.rpc.kafka.security.protocol=$kafka_security_protocol
org.opennms.core.ipc.rpc.kafka.sasl.mechanism=$kafka_client_mechanism
org.opennms.core.ipc.rpc.kafka.sasl.jaas.config=$kafka_security_module required username="$kafka_user_name" password="$kafka_user_password";
EOF
fi

# Kafka Producer

cat <<EOF > $opennms_etc/org.opennms.features.kafka.producer.client.cfg
bootstrap.servers=$kafka_servers
sasl.mechanism=$kafka_client_mechanism
sasl.jaas.config=$kafka_security_module required username="$kafka_user_name" password="$kafka_user_password";
EOF

cat <<EOF > $opennms_etc/org.opennms.features.kafka.producer.cfg
nodeTopic=OpenNMS.Nodes
alarmTopic=OpenNMS.Alarms
eventTopic=
metricTopic=OpenNMS.Metrics
forward.metrics=true
nodeRefreshTimeoutMs=300000
alarmSyncIntervalMs=300000
EOF

# External Cassandra

newts_cfg=$opennms_etc/opennms.properties.d/newts.properties
cat <<EOF > $newts_cfg
org.opennms.timeseries.strategy=newts
org.opennms.newts.config.hostname=$cassandra_seed
org.opennms.newts.config.keyspace=newts
org.opennms.newts.config.port=9042
org.opennms.newts.config.read_consistency=ONE
org.opennms.newts.config.write_consistency=ANY
org.opennms.newts.config.resource_shard=604800
org.opennms.newts.config.ttl=31540000
org.opennms.newts.config.writer_threads=$num_of_cores
org.opennms.newts.config.ring_buffer_size=131072
org.opennms.newts.config.cache.max_entries=131072
org.opennms.newts.config.cache.priming.enable=true
org.opennms.newts.config.cache.priming.block_ms=120000
EOF
if [[ "$use_redis" == "true" ]]; then
  cat <<EOF >> $newts_cfg
org.opennms.newts.config.cache.strategy=org.opennms.netmgt.newts.support.RedisResourceMetadataCache
org.opennms.newts.config.cache.redis_hostname=127.0.0.1
org.opennms.newts.config.cache.redis_port=6379
EOF
fi
if [ "$use_30sec_frequency" == "true" ]; then
  cat <<EOF >> $newts_cfg
org.opennms.newts.query.minimum_step=30000
org.opennms.newts.query.heartbeat=450000
EOF
fi
sed -r -i 's/cassandra-username/cassandra/g' $opennms_etc/poller-configuration.xml 
sed -r -i 's/cassandra-password/cassandra/g' $opennms_etc/poller-configuration.xml 
sed -r -i 's/cassandra-username/cassandra/g' $opennms_etc/collectd-configuration.xml 
sed -r -i 's/cassandra-password/cassandra/g' $opennms_etc/collectd-configuration.xml 

# Enable NX-OS

sed -r -i '/"NXOS"/s/false/true/' $opennms_etc/telemetryd-configuration.xml

# Configure Elasticsearch forwarder

cat <<EOF > $opennms_etc/org.opennms.plugin.elasticsearch.rest.forwarder.cfg
elasticUrl=$elastic_url
elasticGlobalUser=$elastic_user
elasticGlobalPassword=$elastic_password
archiveRawEvents=true
archiveAlarms=true
archiveAlarmChangeEvents=false
logAllEvents=false
retries=1
connTimeout=3000
EOF

# Enable Path Outages

sed -r -i 's/pathOutageEnabled="false"/pathOutageEnabled="true"/' $opennms_etc/poller-configuration.xml

# Fix PostgreSQL service (to be consistent with Collectd)

sed -r -i 's/"Postgres"/"PostgreSQL"/g' $opennms_etc/poller-configuration.xml 

# Updating the Default Foreign Source

cat <<EOF > $opennms_etc/default-foreign-source.xml
<foreign-source xmlns="http://xmlns.opennms.org/xsd/config/foreign-source" name="default" date-stamp="2018-01-01T00:00:00.000-05:00">
   <scan-interval>1d</scan-interval>
   <detectors>
      <detector name="ICMP" class="org.opennms.netmgt.provision.detector.icmp.IcmpDetector"/>
      <detector name="SNMP" class="org.opennms.netmgt.provision.detector.snmp.SnmpDetector"/>
   </detectors>
   <policies/>
</foreign-source>
EOF

# Updating Logging to provide more context for Pollerd and Collectd

cat <<EOF > logging.txt
        <Route key="collectd">
          <RollingFile name="Rolling-Collectd" fileName="\$${logdir}/collectd.log"
                       filePattern="\$${logdir}/collectd.%i.log.gz">
            <PatternLayout>
              <pattern>%d %-5p [%t] SRC:%X{nodeLabel}:%X{ipAddress} %c{1.}: %m%n</pattern>
            </PatternLayout>
            <SizeBasedTriggeringPolicy size="100MB" />
            <DefaultRolloverStrategy max="4" fileIndex="min" />
          </RollingFile>
        </Route>
        <Route key="poller">
          <RollingFile name="Rolling-Collectd" fileName="\$${logdir}/poller.log"
                       filePattern="\$${logdir}/poller.%i.log.gz">
            <PatternLayout>
              <pattern>%d %-5p [%t] SRC:%X{nodeLabel}:%X{ipAddress} %c{1.}: %m%n</pattern>
            </PatternLayout>
            <SizeBasedTriggeringPolicy size="100MB" />
            <DefaultRolloverStrategy max="4" fileIndex="min" />
          </RollingFile>
        </Route>
EOF
sed -r -i '/Routes pattern=/r logging.txt' $opennms_etc/log4j2.xml
rm -f logging.txt

# WARNING: The following section is for testing purposes only
# Change collection and polling interval to 30 seconds

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

echo "### Waiting for OpenNMS dependencies to be ready..."

if [ "$dependencies" != "" ]; then
  for service in $${dependencies//,/ }; do
    data=($${service//:/ })
    echo "Waiting for server $${data[0]} on port $${data[1]}..."
    until printf "" 2>>/dev/null >>/dev/tcp/$${data[0]}/$${data[1]}; do printf '.'; sleep 1; done
  done
fi

echo "### Running OpenNMS install script..."

$opennms_home/bin/runjava -S /usr/java/latest/bin/java
$opennms_home/bin/install -dis

echo "### Initializing Newts keyspace..."

newts=$opennms_etc/newts.cql
sed -r -i "s/'DC1' : 2/'$cassandra_datacenter' : $cassandra_repfactor/" $newts
cqlsh -f $newts $cassandra_seed 

echo "### Enabling and starting OpenNMS Core..."

systemctl daemon-reload
systemctl enable opennms
systemctl start opennms
