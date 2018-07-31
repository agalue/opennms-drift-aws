#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

# AWS Template Variables

hostname="${hostname}"
domainname="${domainname}"
postgres_onms_url="${postgres_onms_url}"
kafka_servers="${kafka_servers}"
cassandra_seed="${cassandra_seed}"
elastic_url="${elastic_url}"
elastic_user="${elastic_user}"
elastic_password="${elastic_password}"
elastic_index_strategy="${elastic_index_strategy}"
sentinel_location="${sentinel_location}"
opennms_url="${opennms_url}"

echo "### Configuring Hostname and Domain..."

ip_address=`curl http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null`
hostnamectl set-hostname --static $hostname
echo "preserve_hostname: true" > /etc/cloud/cloud.cfg.d/99_hostname.cfg
sed -i -r "s/^[#]?Domain =.*/Domain = $domainname/" /etc/idmapd.conf

echo "### Configuring Sentinel..."

sentinel_home=/opt/sentinel
sentinel_etc=$sentinel_home/etc

sentinel_id=$(hostname -f)
repository_version=23.0.0-SNAPSHOT
cat <<EOF > $sentinel_home/deploy/features.xml
<?xml version="1.0" encoding="UTF-8"?>
<features
  name="opennms-\$${project.version}"
  xmlns="http://karaf.apache.org/xmlns/features/v1.4.0"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://karaf.apache.org/xmlns/features/v1.4.0 http://karaf.apache.org/xmlns/features/v1.4.0"
>

  <feature name="autostart-sentinel-bootstrap-modules" version="\$${project.version}" start-level="100" install="auto">
    <config name="org.opennms.sentinel.controller">
      location = $sentinel_location
      id = $sentinel_id
      http-url = $opennms_url
    </config>
    <feature>scv</feature>
    <feature>opennms-spring-extender</feature>
  </feature>

  <feature name="autostart-sentinel-telemetry-flows" version="\$${project.version}" start-level="200" install="auto">
    <config name="org.opennms.netmgt.distributed.datasource">
      datasource.url = $postgres_onms_url
      datasource.username = postgres
      datasource.password = postgres
      datasource.databaseName = opennms
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
      elasticGlobalUser=$elastic_user
      elasticGlobalPassword=$elastic_password
      elasticIndexStrategy=$elastic_index_strategy
      settings.index.number_of_shards=6
      settings.index.number_of_replicas=1
    </config>
    <config name="org.opennms.core.ipc.sink.kafka.consumer">
      group.id = OpenNMS
      bootstrap.servers = $kafka_servers
    </config>
    <feature>sentinel-core</feature>
    <feature>sentinel-persistence</feature>
    <feature>sentinel-kafka</feature>
    <feature>sentinel-flows</feature>
  </feature>

</features>
EOF

# TODO Temporal fix
sed -i -r "/^RUNAS=/s/sentinel/root/" /etc/init.d/sentinel

echo "### Enabling and starting Sentinel..."

systemctl daemon-reload
systemctl enable sentinel
systemctl start sentinel
