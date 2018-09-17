#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
#
# Guide:
# https://github.com/OpenNMS/opennms/blob/jira/HZN-1338/opennms-doc/guide-admin/src/asciidoc/text/sentinel/sentinel.adoc

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
elastic_url="${elastic_url}"
elastic_user="${elastic_user}"
elastic_password="${elastic_password}"
elastic_index_strategy="${elastic_index_strategy}"
opennms_url="${opennms_url}"
sentinel_location="${sentinel_location}"

echo "### Configuring Hostname and Domain..."

ip_address=`curl http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null`
hostnamectl set-hostname --static $hostname
echo "preserve_hostname: true" > /etc/cloud/cloud.cfg.d/99_hostname.cfg
sed -i -r "s/^[#]?Domain =.*/Domain = $domainname/" /etc/idmapd.conf

echo "### Configuring Sentinel..."

sentinel_home=/opt/sentinel
sentinel_etc=$sentinel_home/etc

project_version=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}' opennms-sentinel)
cat <<EOF > $sentinel_home/deploy/features.xml
<?xml version="1.0" encoding="UTF-8"?>
<features
  name="opennms-$project_version"
  xmlns="http://karaf.apache.org/xmlns/features/v1.4.0"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://karaf.apache.org/xmlns/features/v1.4.0 http://karaf.apache.org/xmlns/features/v1.4.0"
>

  <feature name="autostart-sentinel-telemetry-flows" description="OpenNMS :: Features :: Sentinel :: Auto-Start" version="$project_version" start-level="200" install="auto">
    <config name="org.opennms.sentinel.controller">
      location = $sentinel_location
      id = $hostname.$domainname
      http-url = $opennms_url
    </config>
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
      elasticGlobalUser = $elastic_user
      elasticGlobalPassword = $elastic_password
      elasticIndexStrategy = $elastic_index_strategy
      settings.index.number_of_shards = 6
      settings.index.number_of_replicas = 1
    </config>
    <config name="org.opennms.core.ipc.sink.kafka.consumer">
      group.id = Sentinel
      bootstrap.servers = $kafka_servers
      security.protocol = $kafka_security_protocol
      sasl.mechanism = $kafka_client_mechanism
      sasl.jaas.config = $kafka_security_module required username="$kafka_user_name" password="$kafka_user_password";
    </config>
    <feature>sentinel-kafka</feature>
    <feature>sentinel-flows</feature>
  </feature>

</features>
EOF

# Exposing Karaf Console
sed -r -i '/sshHost/s/127.0.0.1/0.0.0.0/' $sentinel_etc/org.apache.karaf.shell.cfg

# TODO Temporal fix
sed -i -r "/^RUNAS=/s/sentinel/root/" /etc/init.d/sentinel

echo "### Enabling and starting Sentinel..."

if [ "$dependencies" != "" ]; then
  for service in $${dependencies//,/ }; do
    data=($${service//:/ })
    echo "Waiting for server $${data[0]} on port $${data[1]}..."
    until printf "" 2>>/dev/null >>/dev/tcp/$${data[0]}/$${data[1]}; do printf '.'; sleep 1; done
  done
fi

systemctl daemon-reload
systemctl enable sentinel
systemctl start sentinel
