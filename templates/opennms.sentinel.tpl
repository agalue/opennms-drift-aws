#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
#
# Guide:
# https://github.com/OpenNMS/opennms/blob/develop/opennms-doc/guide-admin/src/asciidoc/text/sentinel/sentinel.adoc
# https://github.com/OpenNMS/oce/blob/master/INSTALL.md

# AWS Template Variables

hostname="${hostname}"
domainname="${domainname}"
dependencies="${dependencies}"
postgres_onms_url="${postgres_onms_url}"
kafka_servers="${kafka_servers}"
kafka_security_protocol="${kafka_security_protocol}"
kafka_security_module="${kafka_security_module}"
kafka_client_mechanism="${kafka_client_mechanism}"
kafka_user_name="${kafka_user_name}"
kafka_user_password="${kafka_user_password}"
cassandra_servers="${cassandra_servers}"
elastic_url="${elastic_url}"
elastic_user="${elastic_user}"
elastic_password="${elastic_password}"
elastic_index_strategy="${elastic_index_strategy}"
opennms_url="${opennms_url}"
sentinel_location="${sentinel_location}"

echo "### Configuring Hostname and Domain..."

ip_address=$(curl http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null)
hostnamectl set-hostname --static $hostname
echo "preserve_hostname: true" > /etc/cloud/cloud.cfg.d/99_hostname.cfg
sed -i -r "s/^[#]?Domain =.*/Domain = $domainname/" /etc/idmapd.conf

echo "### Configuring Sentinel..."

sentinel_home=/opt/sentinel
sentinel_etc=$sentinel_home/etc
telemedry_dir=$sentinel_etc/telemetryd-adapters
sysconfig=/etc/sysconfig/sentinel

num_of_cores=$(cat /proc/cpuinfo | grep "^processor" | wc -l)
total_mem_in_mb=$(free -m | awk '/:/ {print $2;exit}')
mem_in_mb=$(expr $total_mem_in_mb / 2)
if [ "$mem_in_mb" -gt "30720" ]; then
  mem_in_mb="30720"
fi

sasl_security=""
if [[ $kafka_security_protocol == *"SASL"* ]]; then
  read -r -d '' sasl_security <<- EOF
security.protocol = $kafka_security_protocol
sasl.mechanism = $kafka_client_mechanism
sasl.jaas.config = $kafka_security_module required username="$kafka_user_name" password="$kafka_user_password";
EOF
fi

# JVM

sed -r -i '/export JAVA_MAX_MEM/s/^# //' $sysconfig
sed -i -r "/export JAVA_MAX_MEM/s/=.*/=$${mem_in_mb}M/" $sysconfig

sed -r -i '/JAVA_OPTS/i ADDITIONAL_MANAGER_OPTIONS="-d64" \
ADDITIONAL_MANAGER_OPTIONS="$ADDITIONAL_MANAGER_OPTIONS -Djava.net.preferIPv4Stack=true" \
ADDITIONAL_MANAGER_OPTIONS="$ADDITIONAL_MANAGER_OPTIONS -XX:+PrintGCTimeStamps -XX:+PrintGCDetails" \
ADDITIONAL_MANAGER_OPTIONS="$ADDITIONAL_MANAGER_OPTIONS -Xloggc:/opt/sentinel/data/log/gc.log" \
ADDITIONAL_MANAGER_OPTIONS="$ADDITIONAL_MANAGER_OPTIONS -XX:+UseGCLogFileRotation" \
ADDITIONAL_MANAGER_OPTIONS="$ADDITIONAL_MANAGER_OPTIONS -XX:NumberOfGCLogFiles=10" \
ADDITIONAL_MANAGER_OPTIONS="$ADDITIONAL_MANAGER_OPTIONS -XX:GCLogFileSize=10M" \
ADDITIONAL_MANAGER_OPTIONS="$ADDITIONAL_MANAGER_OPTIONS -XX:+UseStringDeduplication" \
ADDITIONAL_MANAGER_OPTIONS="$ADDITIONAL_MANAGER_OPTIONS -XX:+UseG1GC"' $sysconfig
sed -r -i "/JAVA_OPTS/s/^# //" $sysconfig
sed -i -r "/JAVA_OPTS/s/=.*/=\$ADDITIONAL_MANAGER_OPTIONS/" $sysconfig

# Basic Configuration

cat <<EOF > $sentinel_etc/org.opennms.sentinel.controller.cfg
location = $sentinel_location
id = $hostname.$domainname
http-url = $opennms_url
EOF

cat <<EOF > $sentinel_etc/org.opennms.netmgt.distributed.datasource.cfg
datasource.url = $postgres_onms_url
datasource.username = opennms
datasource.password = opennms
datasource.databaseName = opennms
EOF

cat <<EOF > $sentinel_etc/org.opennms.features.flows.persistence.elastic.cfg
elasticUrl = $elastic_url
globalElasticUser = $elastic_user
globalElasticPassword = $elastic_password
elasticIndexStrategy = $elastic_index_strategy
settings.index.number_of_shards = 6
settings.index.number_of_replicas = 1
EOF

cat <<EOF > $sentinel_etc/org.opennms.core.ipc.sink.kafka.consumer.cfg
group.id = OpenNMS
bootstrap.servers = $kafka_servers
$sasl_security
EOF

# Streaming Telemetry Persistence

cat <<EOF > $sentinel_etc/org.opennms.newts.config.cfg
hostname = $cassandra_servers
keyspace = newts
port = 9042
read_consistency = ONE
write_consistency = ANY
resource_shard = 604800
ttl = 31540000
writer_threads = $num_of_cores
ring_buffer_size = 131072
cache.max_entries = 131072
cache.strategy = org.opennms.netmgt.newts.support.GuavaSearchableResourceMetadataCache
EOF

# Flows/Telemetry Adapters

cat <<EOF > $sentinel_etc/org.opennms.features.telemetry.adapters-sflow-telemetry.cfg
adapters.1.name = SFlow
adapters.1.class-name = org.opennms.netmgt.telemetry.protocols.sflow.adapter.SFlowAdapter
adapters.2.name = SFlow-Telemetry
adapters.2.class-name = org.opennms.netmgt.telemetry.protocols.sflow.adapter.SFlowTelemetryAdapter
adapters.2.parameters.script = $telemedry_dir/sflow-host.groovy
EOF

cat <<EOF > $sentinel_etc/org.opennms.features.telemetry.adapters-nxos.cfg
name = NXOS
class-name = org.opennms.netmgt.telemetry.protocols.nxos.adapter.NxosGpbAdapter
parameters.script = $telemedry_dir/cisco-nxos-telemetry-interface.groovy
EOF

cat <<EOF > $sentinel_etc/org.opennms.features.telemetry.adapters-jti.cfg
name = JTI
class-name = org.opennms.netmgt.telemetry.protocols.jti.adapter.JtiGpbAdapter
parameters.script = $telemedry_dir/junos-telemetry-interface.groovy
EOF

cat <<EOF > $sentinel_etc/org.opennms.features.telemetry.adapters-ipfix.cfg
name = IPFIX
class-name = org.opennms.netmgt.telemetry.protocols.netflow.adapter.ipfix.IpfixAdapter
EOF

cat <<EOF > $sentinel_etc/org.opennms.features.telemetry.adapters-netflow5.cfg
name = Netflow-5
class-name = org.opennms.netmgt.telemetry.protocols.netflow.adapter.netflow5.Netflow5Adapter
EOF

cat <<EOF > $sentinel_etc/org.opennms.features.telemetry.adapters-netflow9.cfg
name = Netflow-9
class-name = org.opennms.netmgt.telemetry.protocols.netflow.adapter.netflow9.Netflow9Adapter
EOF

cat <<EOF > $sentinel_etc/featuresBoot.d/sentinel.boot
sentinel-kafka
sentinel-flows
sentinel-newts
sentinel-telemetry-nxos
sentinel-telemetry-jti
EOF

# OCE

cat <<EOF > $sentinel_etc/org.opennms.oce.datasource.opennms.kafka.cfg
alarmTopic=OpenNMS.Alarms
nodeTopic=OpenNMS.Nodes
eventSinkTopic=OpenNMS.Sink.Events
inventoryTopic=OpenNMS.OCE.Inventory
EOF

cat <<EOF > $sentinel_etc/org.opennms.oce.datasource.opennms.kafka.streams.cfg
bootstrap.servers = $kafka_servers
commit.interval.ms = 5000
$sasl_security
EOF

cat <<EOF > $sentinel_etc/org.opennms.oce.datasource.opennms.kafka.producer.cfg
bootstrap.servers = $kafka_servers
$sasl_security
EOF

cat <<EOF > $sentinel_etc/featuresBoot.d/oce.boot
oce-datasource-opennms-kafka wait-for-kar=opennms-oce-plugin
oce-datasource-shell wait-for-kar=opennms-oce-plugin
oce-engine-cluster wait-for-kar=opennms-oce-plugin
oce-processor-standalone wait-for-kar=opennms-oce-plugin
oce-driver-main wait-for-kar=opennms-oce-plugin
oce-features-graph-shell wait-for-kar=opennms-oce-plugin
EOF

# Workaround annoying harmless error associated with Kafka Consumer
cat <<EOF >> $sentinel_etc/org.ops4j.pax.logging.cfg

log4j2.logger.kafka_scala.name = kafka.consumer
log4j2.logger.kafka_scala.level = ERROR

log4j2.logger.org_opennms_oce.level = DEBUG
log4j2.logger.org_opennms_oce.name = org.opennms.oce
EOF

# Exposing Karaf Console
sed -r -i "/^sshHost/s/=.*/= 0.0.0.0/" $sentinel_etc/org.apache.karaf.shell.cfg

# Expose the RMI registry and server
sed -r -i "/^rmiRegistryHost/s/=.*/= 0.0.0.0/" $sentinel_etc/org.apache.karaf.management.cfg
sed -r -i "/^rmiServerHost/s/=.*/= 0.0.0.0/" $sentinel_etc/org.apache.karaf.management.cfg

# The following should match OpenNMS in order to properly store telemetry metrics on Cassandra
cat <<EOF >> $sentinel_etc/system.properties 

org.opennms.rrd.storeByGroup=true
org.opennms.rrd.storeByForeignSource=true
EOF

chown -R sentinel:sentinel $sentinel_etc

echo "### Enabling and starting Sentinel..."

if [ "$dependencies" != "" ]; then
  for service in $${dependencies//,/ }; do
    data=($${service//:/ })
    echo "Waiting for server $${data[0]} on port $${data[1]}..."
    until printf "" 2>>/dev/null >>/dev/tcp/$${data[0]}/$${data[1]}; do printf '.'; sleep 1; done
    echo " ok"
  done
fi

systemctl daemon-reload
systemctl enable sentinel
systemctl start sentinel

# Workaround for failed initializations
sleep 20
bundles=$(sshpass -p admin ssh -o StrictHostKeyChecking=no -p 8301 admin@localhost list 2>/dev/null | wc -l)
if [ "$bundles" -lt "170" ]; then
  echo "### Restarting Sentinel, as it doesn't look it was initialized correctly"
  systemctl restart sentinel
fi
