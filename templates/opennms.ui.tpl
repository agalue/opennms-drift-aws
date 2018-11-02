#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

# AWS Template Variables

hostname="${hostname}"
domainname="${domainname}"
domainname_public="${domainname_public}"
dependencies="${dependencies}"
redis_server="${redis_server}"
postgres_onms_url="${postgres_onms_url}"
postgres_server="${postgres_server}"
cassandra_seed="${cassandra_seed}"
elastic_url="${elastic_url}"
elastic_user="${elastic_user}"
elastic_password="${elastic_password}"
elastic_index_strategy="${elastic_index_strategy}"
use_30sec_frequency="${use_30sec_frequency}"

echo "### Configuring Hostname and Domain..."

ip_address=$(curl http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null)
hostnamectl set-hostname --static $hostname
echo "preserve_hostname: true" > /etc/cloud/cloud.cfg.d/99_hostname.cfg
sed -i -r "s/^[#]?Domain =.*/Domain = $domainname/" /etc/idmapd.conf

echo "### Configuring OpenNMS..."

opennms_home=/opt/opennms
opennms_etc=$opennms_home/etc

# Database connections
postgres_tmpl_url=$(echo $postgres_onms_url | sed 's|/opennms|/template1|')
onms_url=$(echo $postgres_onms_url | sed 's|[&]|\\&|')
tmpl_url=$(echo $postgres_tmpl_url | sed 's|[&]|\\&|')
sed -r -i "/jdbc.*opennms/s|url=\".*\"|url=\"$onms_url\"|" $opennms_etc/opennms-datasources.xml
sed -r -i "/jdbc.*template1/s|url=\".*\"|url=\"$tmpl_url\"|" $opennms_etc/opennms-datasources.xml

# JVM Settings
num_of_cores=$(cat /proc/cpuinfo | grep "^processor" | wc -l)
half_of_cores=$(expr $num_of_cores / 2)
total_mem_in_mb=$(free -m | awk '/:/ {print $2;exit}')
mem_in_mb=$(expr $total_mem_in_mb / 2)
if [ "$mem_in_mb" -gt "30720" ]; then
  mem_in_mb="30720"
fi
sed -i -r "/JAVA_HEAP_SIZE/s/=1024/=$mem_in_mb/" $opennms_etc/opennms.conf
sed -i -r "/GCThreads/s/=2/=$half_of_cores/" $opennms_etc/opennms.conf
sed -i -r "/rmi.server.hostname/s/=0.0.0.0/=$hostname/" $opennms_etc/opennms.conf

# Exposing Karaf Console
sed -r -i '/sshHost/s/127.0.0.1/0.0.0.0/' $opennms_etc/org.apache.karaf.shell.cfg

# External Cassandra
newts_cfg=$opennms_etc/opennms.properties.d/newts.properties
cat <<EOF > $newts_cfg
org.opennms.timeseries.strategy=newts
org.opennms.newts.config.hostname=$cassandra_seed
org.opennms.newts.config.keyspace=newts
org.opennms.newts.config.port=9042
org.opennms.newts.config.read_consistency=ONE
EOF
if [[ "$redis_server" != "" ]]; then
  cat <<EOF >> $newts_cfg
org.opennms.newts.config.cache.strategy=org.opennms.netmgt.newts.support.RedisResourceMetadataCache
org.opennms.newts.config.cache.redis_hostname=$redis_server
org.opennms.newts.config.cache.redis_port=6379
EOF
fi
if [ "$use_30sec_frequency" == "true" ]; then
  cat <<EOF >> $newts_cfg
org.opennms.newts.query.minimum_step=30000
org.opennms.newts.query.heartbeat=450000
EOF
fi

# External Elasticsearch for Flows
cat <<EOF > $opennms_etc/org.opennms.features.flows.persistence.elastic.cfg
elasticUrl=$elastic_url
globalElasticUser=$elastic_user
globalElasticPassword=$elastic_password
elasticIndexStrategy=$elastic_index_strategy
EOF

# Simplify Eventd
cat <<EOF > $opennms_etc/eventconf.xml
<?xml version="1.0"?>
<events xmlns="http://xmlns.opennms.org/xsd/eventconf">
  <global>
    <security>
      <doNotOverride>logmsg</doNotOverride>
      <doNotOverride>operaction</doNotOverride>
      <doNotOverride>autoaction</doNotOverride>
      <doNotOverride>tticket</doNotOverride>
      <doNotOverride>script</doNotOverride>
    </security>
  </global>
  <event-file>events/opennms.ackd.events.xml</event-file>
  <event-file>events/opennms.alarm.events.xml</event-file>
  <event-file>events/opennms.alarmChangeNotifier.events.xml</event-file>
  <event-file>events/opennms.bsm.events.xml</event-file>
  <event-file>events/opennms.capsd.events.xml</event-file>
  <event-file>events/opennms.config.events.xml</event-file>
  <event-file>events/opennms.correlation.events.xml</event-file>
  <event-file>events/opennms.default.threshold.events.xml</event-file>
  <event-file>events/opennms.discovery.events.xml</event-file>
  <event-file>events/opennms.internal.events.xml</event-file>
  <event-file>events/opennms.linkd.events.xml</event-file>
  <event-file>events/opennms.mib.events.xml</event-file>
  <event-file>events/opennms.pollerd.events.xml</event-file>
  <event-file>events/opennms.provisioning.events.xml</event-file>
  <event-file>events/opennms.minion.events.xml</event-file>
  <event-file>events/opennms.remote.poller.events.xml</event-file>
  <event-file>events/opennms.reportd.events.xml</event-file>
  <event-file>events/opennms.syslogd.events.xml</event-file>
  <event-file>events/opennms.ticketd.events.xml</event-file>
  <event-file>events/opennms.tl1d.events.xml</event-file>
  <event-file>events/opennms.catch-all.events.xml</event-file>
</events>
EOF

# WebUI Services
cat <<EOF > $opennms_etc/service-configuration.xml
<?xml version="1.0"?>
<service-configuration xmlns="http://xmlns.opennms.org/xsd/config/vmmgr">
  <service>
    <name>OpenNMS:Name=Manager</name>
    <class-name>org.opennms.netmgt.vmmgr.Manager</class-name>
    <invoke at="stop" pass="1" method="doSystemExit"/>
  </service>
  <service>
    <name>OpenNMS:Name=TestLoadLibraries</name>
    <class-name>org.opennms.netmgt.vmmgr.Manager</class-name>
    <invoke at="start" pass="0" method="doTestLoadLibraries"/>
  </service>
  <service>
    <name>OpenNMS:Name=Eventd</name>
    <class-name>org.opennms.netmgt.eventd.jmx.Eventd</class-name>
    <invoke at="start" pass="0" method="init"/>
    <invoke at="start" pass="1" method="start"/>
    <invoke at="status" pass="0" method="status"/>
    <invoke at="stop" pass="0" method="stop"/>
  </service>
  <service>
    <name>OpenNMS:Name=JettyServer</name>
    <class-name>org.opennms.netmgt.jetty.jmx.JettyServer</class-name>
    <invoke at="start" pass="0" method="init"/>
    <invoke at="start" pass="1" method="start"/>
    <invoke at="status" pass="0" method="status"/>
    <invoke at="stop" pass="0" method="stop"/>
  </service>
</service-configuration>
EOF

# WebUI Settings
cat <<EOF >> $opennms_etc/opennms.properties.d/webui.properties
org.opennms.web.console.centerUrl=/status/status-box.jsp,/geomap/map-box.jsp,/heatmap/heatmap-box.jsp
EOF

# Configuring Deep Dive Tool
cat <<EOF > $opennms_etc/org.opennms.netmgt.flows.rest.cfg
flowGraphUrl=http://$hostname.$domainname_public/grafana/dashboard/flows?node=\$nodeId&interface=\$ifIndex
EOF

echo "### Forcing OpenNMS to be read-only in terms of administrative changes..."

security_cfg=$opennms_home/jetty-webapps/opennms/WEB-INF/applicationContext-spring-security.xml
cp $security_cfg $security_cfg.bak
sed -r -i 's/ROLE_ADMIN/ROLE_DISABLED/' $security_cfg
sed -r -i 's/ROLE_PROVISION/ROLE_DISABLED/' $security_cfg

echo "### Checking dependencies..."

if [ "$dependencies" != "" ]; then
  for service in $${dependencies//,/ }; do
    data=($${service//:/ })
    echo "Waiting for server $${data[0]} on port $${data[1]}..."
    until printf "" 2>>/dev/null >>/dev/tcp/$${data[0]}/$${data[1]}; do printf '.'; sleep 1; done
    echo " ok"
  done
fi

echo "### Configurng Grafana..."

grafana_cfg=/etc/grafana/grafana.ini
cp $grafana_cfg $grafana_cfg.bak
sed -r -i "s/;domain = localhost/domain = $hostname.$domainname_public/" $grafana_cfg
sed -r -i "s/;root_url = .*/root_url = %(protocol)s:\/\/%(domain)s:\/grafana/" $grafana_cfg
sed -r -i "s/;type = sqlite3/type = postgres/" $grafana_cfg
sed -r -i "s/;host = 127.0.0.1:3306/host = $postgres_server:5432/" $grafana_cfg
sed -r -i "/;name = grafana/s/;//" $grafana_cfg
sed -r -i "s/;user = root/user = grafana/" $grafana_cfg
sed -r -i "s/;password =/password = grafana/" $grafana_cfg
sed -r -i "s/;provider = file/provider = postgres/" $grafana_cfg
sed -r -i "s/;provider_config = sessions/provider_config = user=grafana password=grafana host=$postgres_server port=5432 dbname=grafana sslmode=disable/" $grafana_cfg

echo "### Configurng PostgreSQL database for Grafana..."
echo "### WARNING - Grafana doesn't support multi-host database configuration..."

export PGHOST="$postgres_server"
export PGPORT=5432
export PGUSER=postgres
export PGPASSWORD=postgres

if ! psql -lqt | cut -d \| -f 1 | grep -qw grafana; then
  echo "Creating grafana user and database in PostgreSQL..."
  createdb -E UTF-8 grafana
  createuser grafana
  psql -c "alter role grafana with password 'grafana';"
  psql -c "grant all on database grafana to grafana;"
fi

echo "### Enabling and starting Grafana server..."

systemctl enable grafana-server
systemctl start grafana-server
sleep 10

grafana_key=$(curl -X POST -H "Content-Type: application/json" -d '{"name":"opennms-ui", "role": "Viewer"}' http://admin:admin@localhost:3000/api/auth/keys 2>/dev/null | jq .key - | sed 's/"//g')
if [ "$grafana_key" != "null" ]; then
  cat <<EOF > $opennms_etc/opennms.properties.d/grafana.properties
org.opennms.grafanaBox.show=true
org.opennms.grafanaBox.hostname=$hostname.$domainname_public
org.opennms.grafanaBox.port=80
org.opennms.grafanaBox.basePath=/grafana
org.opennms.grafanaBox.apiKey=$grafana_key
EOF
fi

echo "### Enabling Helm..."

helm_url="http://localhost:3000/api/plugins/opennms-helm-app/settings"
helm_enabled=$(curl -u admin:admin "$helm_url" 2>/dev/null | jq '.enabled')
if [ "$helm_enabled" != "true" ]; then
  curl -u admin:admin -XPOST "$helm_url" -d "id=opennms-helm-app&enabled=true" 2>/dev/null
  cat <<EOF > data.json
{
  "name": "opennms-performance",
  "type": "opennms-helm-performance-datasource",
  "access": "proxy",
  "url": "http://localhost:8980/opennms",
  "basicAuth": true,
  "basicAuthUser": "admin",
  "basicAuthPassword": "admin"
}
EOF
  ds_url="http://localhost:3000/api/datasources"
  curl -u admin:admin -H 'Content-Type: application/json' -XPOST -d @data.json $ds_url
  sed -i -r 's/-performance/-fault/g' data.json
  curl -u admin:admin -H 'Content-Type: application/json' -XPOST -d @data.json $ds_url
  sed -i -r 's/-fault/-flow/g' data.json
  curl -u admin:admin -H 'Content-Type: application/json' -XPOST -d @data.json $ds_url
  rm -f data.json
fi

echo "### Configuring HTTP Proxy..."

cat <<EOF > /etc/httpd/conf.d/opennms.conf
<VirtualHost *:80>
  ServerName $hostname
  ErrorLog "logs/opennms-error_log"
  CustomLog "logs/opennms-access_log" common
  <Location /opennms>
    Order deny,allow
    Allow from all
    ProxyPass http://127.0.0.1:8980/opennms
    ProxyPassReverse http://127.0.0.1:8980/opennms
  </Location>
  <Location /hawtio>
    Order deny,allow
    Allow from all
    ProxyPass http://127.0.0.1:8980/hawtio
    ProxyPassReverse http://127.0.0.1:8980/hawtio
  </Location>
  <Location /grafana>
    Order deny,allow
    Allow from all
    ProxyPass http://127.0.0.1:3000
    ProxyPassReverse http://127.0.0.1:3000
  </Location>
</VirtualHost>
EOF

systemctl enable httpd
systemctl start httpd

echo "### Enabling and starting OpenNMS..."

systemctl daemon-reload
$opennms_home/bin/runjava -S /usr/java/latest/bin/java
touch $opennms_etc/configured
systemctl enable opennms
systemctl start opennms
