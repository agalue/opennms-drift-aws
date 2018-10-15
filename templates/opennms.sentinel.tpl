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
    <config name="org.opennms.features.telemetry.adapters-sflow">
      name = SFlow
      class-name = org.opennms.netmgt.telemetry.adapters.netflow.sflow.SFlowAdapter
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
      elasticGlobalUser = $elastic_user
      elasticGlobalPassword = $elastic_password
      elasticIndexStrategy = $elastic_index_strategy
      settings.index.number_of_shards = 6
      settings.index.number_of_replicas = 1
    </config>
    <config name="org.opennms.core.ipc.sink.kafka.consumer">
      group.id = Sentinel
      bootstrap.servers = $kafka_servers
    </config>
    <feature>sentinel-kafka</feature>
    <feature>sentinel-flows</feature>
  </feature>

</features>
EOF

# Exposing Karaf Console
sed -r -i '/sshHost/s/127.0.0.1/0.0.0.0/' $sentinel_etc/org.apache.karaf.shell.cfg

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

# Workaround for failed initializations
sleep 20
bundles=$(sshpass -p admin ssh -o StrictHostKeyChecking=no -p 8301 admin@localhost list 2>/dev/null | wc -l)
if [ "$bundles" -lt "170" ]; then
  echo "### Restarting Sentinel, as it doesn't look it was initialized correctly"
  systemctl restart sentinel
fi
