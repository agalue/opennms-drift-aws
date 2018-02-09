#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# Warning: This is intended to be used through Terraform's template plugin only

# AWS Template Variables
# - node_id
# - vpc_cidr
# - hostname
# - domainname
# - onms_repo
# - onms_version
# - pg_repo_version
# - postgres_server
# - opennms_server
# - nfs_server
# - cassandra_servers
# - webui_endpoint

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
yum -y -q install jq net-snmp net-snmp-utils git pytz dstat htop sysstat

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

echo "### Creating and configuring external mount point for OpenNMS configuration..."

opennms_home=/opt/opennms
opennms_etc=$opennms_home/etc
nfs_dir=/data/onms-etc
nfs_options="nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2"
mkdir -p $nfs_dir
echo "${nfs_server}:$opennms_etc $nfs_dir nfs4 $nfs_options 0 0" >> /etc/fstab
mount $nfs_dir

echo "### Installing PostgreSQL tools..."

pg_version=`echo ${pg_repo_version} | sed 's/-.//'`
pg_family=`echo $pg_version | sed 's/\.//'`

yum install -y -q https://download.postgresql.org/pub/repos/yum/$pg_version/redhat/rhel-7-x86_64/pgdg-centos$pg_family-${pg_repo_version}.noarch.rpm
sed -i -r 's/[$]releasever/7/g' /etc/yum.repos.d/pgdg-$pg_family-centos.repo
yum install -y -q postgresql$pg_family

echo "### Installing OpenNMS Dependencies from stable repository..."

sed -r -i '/name=Amazon Linux 2/a exclude=rrdtool-*' /etc/yum.repos.d/amzn2-core.repo
yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-stable-rhel7.noarch.rpm
rpm --import /etc/yum.repos.d/opennms-repo-stable-rhel7.gpg
yum install -y -q jicmp jicmp6 jrrd jrrd2 rrdtool 'perl(LWP)' 'perl(XML::Twig)'

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

yum install -y -q opennms-helm R

echo "### Installing Hawtio..."

hawtio_url=https://oss.sonatype.org/content/repositories/public/io/hawt/hawtio-default/1.4.63/hawtio-default-1.4.63.war
wget -qO $opennms_home/jetty-webapps/hawtio.war $hawtio_url && \
  unzip -qq $opennms_home/jetty-webapps/hawtio.war -d $opennms_home/jetty-webapps/hawtio && \
  rm -f $opennms_home/jetty-webapps/hawtio.war

echo "### Building OpenNMS configuration files on $opennms_etc..."

mv $opennms_etc $opennms_etc.bak
mkdir $opennms_etc
ln -s $nfs_dir/* $opennms_etc/
rm -f $opennms_etc/events
mkdir $opennms_etc/events
rsync -ar $nfs_dir/events/ $opennms_etc/events/
rm -f $opennms_etc/opennms.properties.d
mkdir $opennms_etc/opennms.properties.d
rm -f $opennms_etc/opennms.conf
rm -f $opennms_etc/java.conf
rm -f $opennms_etc/configured
rm -f $opennms_etc/opennms-upgrade-status.properties
rm -f $opennms_etc/org.apache.karaf.features.cfg
rm -f $opennms_etc/eventconf.xml
rm -f $opennms_etc/scriptd-configuration.xml
rm -f $opennms_etc/service-configuration.xml

cp /var/opennms/etc-pristine/org.apache.karaf.features.cfg $opennms_etc/
cp $nfs_dir/opennms.properties.d/newts.properties $opennms_etc/opennms.properties.d/
cp $nfs_dir/opennms.properties.d/rrd.properties $opennms_etc/opennms.properties.d/

echo "### Configuring OpenNMS..."

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

files=(`ls -l $opennms_etc/events/opennms.*.xml | awk '{print $9}'`)
for f in "$${files[@]}"; do
  sed -r -i '/logmsg/s/logndisplay/donotpersist/' $f
  sed -r -i '/logmsg/s/logonly/donotpersist/' $f
done

cat <<EOF > $opennms_etc/opennms.properties.d/webui.properties
org.opennms.web.console.centerUrl=/geomap/map-box.jsp,/heatmap/heatmap-box.jsp
EOF

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
EOF

sed -r -i '/datachoices/d' $opennms_etc/org.apache.karaf.features.cfg

echo "### Configuring OpenNMS Jetty Server..."

webxml=$opennms_home/jetty-webapps/opennms/WEB-INF/web.xml
cp $webxml $webxml.bak
sed -r -i '/[<][!]--/{$!{N;s/[<][!]--\n  ([<]filter-mapping)/\1/}}' $webxml
sed -r -i '/nrt/{$!{N;N;s/(nrt.*\n  [<]\/filter-mapping[>])\n  --[>]/\1/}}' $webxml

echo "### Running OpenNMS install script..."

$opennms_home/bin/runjava -S /usr/java/latest/bin/java
touch $opennms_etc/configured

echo "### Enabling and starting OpenNMS Core..."

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

echo "### Starting and enabling Grafana server..."

systemctl enable grafana-server
systemctl start grafana-server
