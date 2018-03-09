#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# Warning: This is intended to be used through Terraform's template plugin only

# AWS Template Variables
# - hostname = ${hostname}
# - domainname = ${domainname}
# - postgres_server = ${postgres_server}
# - opennms_server = ${opennms_server}
# - cassandra_servers = ${cassandra_servers}
# - webui_endpoint = ${webui_endpoint}

echo "### Configuring Hostname and Domain..."

sed -i -r "s/HOSTNAME=.*/HOSTNAME=${hostname}.${domainname}/" /etc/sysconfig/network
hostname ${hostname}.${domainname}
domainname ${domainname}
sed -i -r "s/#Domain =.*/Domain = ${domainname}/" /etc/idmapd.conf

echo "### Configuring OpenNMS..."

opennms_home=/opt/opennms
opennms_etc=$opennms_home/etc

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
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Djava.rmi.server.hostname=${hostname}"
EOF

# JMX Groups
cat <<EOF > $opennms_etc/jmxremote.access
admin readwrite
jmx   readonly
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

# RRD Settings
cat <<EOF > $opennms_etc/opennms.properties.d/rrd.properties
org.opennms.rrd.storeByGroup=true
org.opennms.rrd.storeByForeignSource=true
EOF

# Event Forwarding Logic
cat <<EOF > $opennms_etc/event-forwarder.sh
import java.net.InetAddress;
import java.net.InetSocketAddress;
import org.opennms.netmgt.events.api.support.EventProxyException;
import org.opennms.netmgt.events.api.support.TcpEventProxy;
import org.opennms.netmgt.xml.event.Event;

targetIpaddr = "${opennms_server}";
eventSource = "WebUI-Server";

void forwardEvent(Event event) {
  // Skip unwanted events:
  switch (event.uei) {
    case "uei.opennms.org/internal/rtc/subscribe":
    case "uei.opennms.org/internal/authentication/successfulLogin":
      return;
      break;
  }
  // Set event source
  event.setSource(eventSource);
  proxy  = new TcpEventProxy(new InetSocketAddress(targetIpaddr,5817),6000);
  // Forward event
  try {
    log.info("Sending event " + event.uei + "(" + event.dbid + ") to " + targetIpaddr);
    proxy.send(event);
  } catch(Exception e) {
    log.error("Unable to send event to remote eventd on " + targetIpaddr, e);
  }
}
EOF

# Event Forwarding Configuration
cat <<EOF > $opennms_etc/scriptd-configuration.xml
<?xml version="1.0"?>
<scriptd-configuration>
  <engine language="beanshell" className="bsh.util.BeanShellBSFEngine" extensions="bsh"/>
  <start-script language="beanshell">
    log = bsf.lookupBean("log");
    source("/opt/opennms/etc/event-forwarder.bsh");
  </start-script>
  <event-script language="beanshell">
    event = bsf.lookupBean("event");
    forwardEvent(event);
  </event-script>
</scriptd-configuration>
EOF

# Event Forwarding Configuration to avoid duplicates
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
  <event-file>events/opennms.ncs-component.events.xml</event-file>
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
    <name>OpenNMS:Name=Scriptd</name>
    <class-name>org.opennms.netmgt.scriptd.jmx.Scriptd</class-name>
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

# Force donotpersist on all internal events
files=(`ls -l $opennms_etc/events/opennms.*.xml | awk '{print $9}'`)
for f in "$${files[@]}"; do
  sed -r -i '/logmsg/s/logndisplay/donotpersist/' $f
  sed -r -i '/logmsg/s/logonly/donotpersist/' $f
done

# WebUI Settings
cat <<EOF > $opennms_etc/opennms.properties.d/webui.properties
org.opennms.web.console.centerUrl=/status/status-box.jsp,/geomap/map-box.jsp,/heatmap/heatmap-box.jsp
org.opennms.web.graphs.engine=backshift
EOF

# TODO: the following is due to some issues with the datachoices plugin
cat <<EOF > $opennms_etc/org.opennms.features.datachoices.cfg
enabled=false
acknowledged-by=admin
acknowledged-at=Mon Jan 01 00\:00\:00 EDT 2018
EOF

# Logging
sed -r -i 's/value="DEBUG"/value="WARN"/' $opennms_etc/log4j2.xml

echo "### Forcing OpenNMS to be read-only in terms of administrative changes..."

security_cfg=$opennms_home/jetty-webapps/opennms/WEB-INF/applicationContext-spring-security.xml
cp $security_cfg $security_cfg.bak
sed -r -i 's/ROLE_ADMIN/ROLE_DISABLED/' $security_cfg
sed -r -i 's/ROLE_PROVISION/ROLE_DISABLED/' $security_cfg

echo "### Running OpenNMS install script..."

$opennms_home/bin/runjava -S /usr/java/latest/bin/java
touch $opennms_etc/configured

echo "### Enabling and starting OpenNMS Core..."

sleep 180
systemctl daemon-reload
systemctl enable opennms
systemctl start opennms

echo "### Configurng Grafana..."

grafana_cfg=/etc/grafana/grafana.ini
cp $grafana_cfg $grafana_cfg.bak
sed -r -i 's/;domain = localhost/domain = ${webui_endpoint}/' $grafana_cfg
sed -r -i 's/;root_url = .*/root_url = %(protocol)s:\/\/%(domain)s' $grafana_cfg
sed -r -i 's/;type = sqlite3/type = postgres/' $grafana_cfg
sed -r -i 's/;host = 127.0.0.1:3306/host = ${postgres_server}:5432/' $grafana_cfg
sed -r -i '/;name = grafana/s/;//' $grafana_cfg
sed -r -i 's/;user = root/user = grafana/' $grafana_cfg
sed -r -i 's/;password =/password = grafana/' $grafana_cfg
sed -r -i "s/;provider = file/provider = postgres/" $grafana_cfg
sed -r -i "s/;provider_config = sessions/provider_config = user=grafana password=grafana host=${postgres_server} port=5432 dbname=grafana sslmode=disable/" $grafana_cfg

echo "*:*:*:postgres:postgres" > ~/.pgpass
chmod 0600 ~/.pgpass
if ! psql -U postgres -h ${postgres_server} -lqt | cut -d \| -f 1 | grep -qw grafana; then
  echo "Creating grafana user and database in PostgreSQL..."
  createdb -U postgres -h ${postgres_server} -E UTF-8 grafana
  createuser -U postgres -h ${postgres_server} grafana
  psql -U postgres -h ${postgres_server} -c "alter role grafana with password 'grafana';"
  psql -U postgres -h ${postgres_server} -c "grant all on database grafana to grafana;"
fi
rm -f ~/.pgpass

echo "### Enabling and starting Grafana server..."

systemctl enable grafana-server
systemctl start grafana-server

echo "### Enabling and starting SNMP..."

systemctl enable snmpd
systemctl start snmpd
