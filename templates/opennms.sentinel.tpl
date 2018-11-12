#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
#
# Guide:
# https://github.com/OpenNMS/opennms/blob/develop/opennms-doc/guide-admin/src/asciidoc/text/sentinel/sentinel.adoc

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
kafka_max_message_size="${kafka_max_message_size}"
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

num_of_cores=$(cat /proc/cpuinfo | grep "^processor" | wc -l)

sentinel_home=/opt/sentinel
sentinel_etc=$sentinel_home/etc
features=$sentinel_home/deploy/features.xml

sasl_security = "";
if [[ $kafka_security_protocol == *"SASL"* ]]; then
  read -r -d '' sasl_security <<- EOF
      security.protocol = $kafka_security_protocol
      sasl.mechanism = $kafka_client_mechanism
      sasl.jaas.config = $kafka_security_module required username="$kafka_user_name" password="$kafka_user_password";
EOF
fi

telemedry_dir=/opt/sentinel/etc/telemetryd-adapters

project_version=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}' opennms-sentinel)
cat <<EOF > $features
<?xml version="1.0" encoding="UTF-8"?>
<features
  name="opennms-$project_version"
  xmlns="http://karaf.apache.org/xmlns/features/v1.4.0"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://karaf.apache.org/xmlns/features/v1.4.0 http://karaf.apache.org/xmlns/features/v1.4.0"
>

  <repository>mvn:io.hawt/hawtio-karaf/2.0.0/xml/features</repository>

  <feature name="autostart-hawtio" description="Hawtio :: Auto-Start" version="2.0.0" start-level="200" install="auto">
    <feature>hawtio-offline</feature>
  </feature>

  <feature name="autostart-sentinel-telemetry-flows" description="OpenNMS :: Features :: Sentinel :: Auto-Start" version="$project_version" start-level="200" install="auto">
    <config name="org.opennms.sentinel.controller">
      location = $sentinel_location
      id = $hostname.$domainname
      http-url = $opennms_url
    </config>
    <config name="org.opennms.netmgt.distributed.datasource">
      datasource.url = $postgres_onms_url
      datasource.username = opennms
      datasource.password = opennms
      datasource.databaseName = opennms
    </config>
    <config name="org.opennms.newts.config">
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
    </config>
    <config name="org.opennms.features.telemetry.adapters-sflow-telemetry">
      adapters.1.name = SFlow
      adapters.1.class-name = org.opennms.netmgt.telemetry.adapters.netflow.sflow.SFlowAdapter
      adapters.2.name = SFlow-Telemetry
      adapters.2.class-name = org.opennms.netmgt.telemetry.adapters.netflow.sflow.SFlowTelemetryAdapter
      adapters.2.parameters.script = $telemedry_dir/sflow-host.groovy
    </config>
    <config name="org.opennms.features.telemetry.adapters-nxos">
      name = NXOS
      class-name = org.opennms.netmgt.telemetry.adapters.nxos.NxosGpbAdapter
      parameters.script = $telemedry_dir/cisco-nxos-telemetry-interface.groovy
    </config>
    <config name="org.opennms.features.telemetry.adapters-jti">
      name = JTI
      class-name = org.opennms.netmgt.telemetry.adapters.jti.JtiGpbAdapter
      parameters.script = $telemedry_dir/junos-telemetry-interface.groovy
    </config>
    <config name="org.opennms.features.telemetry.adapters-ipfix">
      name = IPFIX
      class-name = org.opennms.netmgt.telemetry.adapters.netflow.ipfix.IpfixAdapter
    </config>
    <config name="org.opennms.features.telemetry.adapters-netflow5">
      name = Netflow-5
      class-name = org.opennms.netmgt.telemetry.adapters.netflow.v5.Netflow5Adapter
    </config>
    <config name="org.opennms.features.telemetry.adapters-netflow9">
      name = Netflow-9
      class-name = org.opennms.netmgt.telemetry.adapters.netflow.v9.Netflow9Adapter
    </config>
    <config name="org.opennms.features.flows.persistence.elastic">
      elasticUrl = $elastic_url
      globalElasticUser = $elastic_user
      globalElasticPassword = $elastic_password
      elasticIndexStrategy = $elastic_index_strategy
      settings.index.number_of_shards = 6
      settings.index.number_of_replicas = 1
    </config>
    <config name="org.opennms.core.ipc.sink.kafka.consumer">
      group.id = OpenNMS
      bootstrap.servers = $kafka_servers
      $sasl_security
    </config>
    <feature>sentinel-kafka</feature>
    <feature>sentinel-flows</feature>
    <feature>sentinel-newts</feature>
    <feature>sentinel-telemetry-nxos</feature>
    <feature>sentinel-telemetry-jti</feature>
  </feature>

</features>
EOF

# Workaround annoying harmless error associated with Kafka Consumer
cat <<EOF >> $sentinel_etc/org.ops4j.pax.logging.cfg

log4j2.logger.kafka_scala.name = kafka.consumer
log4j2.logger.kafka_scala.level = ERROR
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

chown -R sentinel:sentinel $features
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
