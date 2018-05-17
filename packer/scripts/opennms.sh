#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

onms_repo="bleeding"
onms_version="-latest-"
helm_branch="develop"
grafana_version="5.1.0"
hawtio_version="1.4.63"

########################################

opennms_home=/opt/opennms
opennms_etc=$opennms_home/etc
tmp_file=/tmp/_onms_temp_file

echo "### Installing EPEL Repository..."

sudo yum -y -q install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm

echo "### Installing Common Packages..."

sudo yum -y -q install haveged redis httpd
sudo systemctl enable haveged

echo "### Installing Grafana $grafana_version..."

sudo yum install -y -q https://s3-us-west-2.amazonaws.com/grafana-releases/release/grafana-$grafana_version-1.x86_64.rpm

echo "### Installing NodeJS & Yarn..."

sudo curl --silent --location https://rpm.nodesource.com/setup_8.x | sudo bash -
sudo yum -y -q install gcc-c++ nodejs
sudo npm install -g yarn

echo "### Installing Helm for Drift from branch $helm_branch..."

sudo mkdir ~/development
cd ~/development
sudo git clone https://github.com/OpenNMS/opennms-helm.git
cd opennms-helm
if [[ `git branch | grep "^[*] $helm_branch" | sed -e 's/[* ]*//'` == "$helm_branch" ]]; then
  echo "### Already in branch $helm_branch"
else
  echo "### Checking out branch $helm_branch"
  sudo git checkout -b $helm_branch origin/$helm_branch
fi
sudo yarn
sudo yarn build
sudo mkdir -p /var/lib/grafana/plugins/opennms-helm-app/
sudo rsync -ar --delete ~/development/opennms-helm/ /var/lib/grafana/plugins/opennms-helm-app/
cd

echo "### Installing OpenNMS Dependencies from stable repository..."

sudo sed -r -i '/name=Amazon Linux 2/a exclude=rrdtool-*' /etc/yum.repos.d/amzn2-core.repo
sudo yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-stable-rhel7.noarch.rpm
sudo rpm --import /etc/yum.repos.d/opennms-repo-stable-rhel7.gpg
sudo yum install -y -q jicmp jicmp6 jrrd jrrd2 rrdtool 'perl(LWP)' 'perl(XML::Twig)'

echo "### Installing OpenNMS..."

if [ "$onms_repo" != "stable" ]; then
  echo "### Installing OpenNMS $onms_repo Repository..."
  sudo yum remove -y -q opennms-repo-stable
  sudo yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-$onms_repo-rhel7.noarch.rpm
  sudo rpm --import /etc/yum.repos.d/opennms-repo-$onms_repo-rhel7.gpg
fi

if [ "$onms_version" == "-latest-" ]; then
  echo "### Installing latest OpenNMS from $onms_repo Repository..."
  sudo yum install -y -q opennms-core opennms-webapp-jetty
else
  echo "### Installing OpenNMS version $onms_version from $onms_repo Repository..."
  sudo yum install -y -q opennms-core-$onms_version opennms-webapp-jetty-$onms_version
fi

echo "### Initializing GIT at $opennms_etc..."

cd $opennms_etc
sudo git config --global user.name "OpenNMS"
sudo git config --global user.email "support@opennms.org"
sudo git init .
sudo git add .
sudo git commit -m "OpenNMS Installed."
cd

echo "### Copying external configuration files..."

src_dir=/tmp/sources
sudo chown -R root:root $src_dir/
sudo rsync -avr $src_dir/ /opt/opennms/etc/

echo "### Apply common configuration changes..."

cat <<EOF > $tmp_file
org.opennms.rrd.storeByGroup=true
org.opennms.rrd.storeByForeignSource=true
EOF
sudo mv -f $tmp_file $opennms_etc/opennms.properties.d/rrd.properties

cat <<EOF > $tmp_file
org.opennms.security.disableLoginSuccessEvent=true
EOF
sudo mv -f $tmp_file $opennms_etc/opennms.properties.d/webui.properties

cat <<EOF > $tmp_file
enabled=false
acknowledged-by=admin
acknowledged-at=Mon Jan 01 00\:00\:00 EDT 2018
EOF
sudo mv -f $tmp_file $opennms_etc/org.opennms.features.datachoices.cfg

sudo sed -r -i 's/value="DEBUG"/value="WARN"/' $opennms_etc/log4j2.xml
sudo sed -r -i '/manager/s/WARN/DEBUG/' $opennms_etc/log4j2.xml

cat <<EOF > $tmp_file
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
                    url="jdbc:postgresql://localhost:5432/opennms"
                    user-name="opennms"
                    password="opennms">
    <param name="connectionTimeout" value="0"/>
    <param name="maxLifetime" value="600000"/>
  </jdbc-data-source>

  <jdbc-data-source name="opennms-admin"
                    database-name="template1"
                    class-name="org.postgresql.Driver"
                    url="jdbc:postgresql://localhost:5432/template1"
                    user-name="postgres"
                    password="postgres" />
</datasource-configuration>
EOF
sudo mv -f $tmp_file $opennms_etc/opennms-datasources.xml

cat <<EOF > $tmp_file
START_TIMEOUT=0
JAVA_HEAP_SIZE=1024
MAXIMUM_FILE_DESCRIPTORS=204800

ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -d64 -Djava.net.preferIPv4Stack=true"

# GC Logging
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+PrintGCTimeStamps -XX:+PrintGCDetails"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Xloggc:/opt/opennms/logs/gc.log"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+UseGCLogFileRotation"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:NumberOfGCLogFiles=10"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:GCLogFileSize=10M"

# GC Settings
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+UseStringDeduplication"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+UseG1GC"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:G1RSetUpdatingPauseTimePercent=5"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:MaxGCPauseMillis=500"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:InitiatingHeapOccupancyPercent=70"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:ParallelGCThreads=2"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:ConcGCThreads=2"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+ParallelRefProcEnabled"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+AlwaysPreTouch"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+UseTLAB"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+ResizeTLAB"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:-UseBiasedLocking"

# Java Flight Recorder
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+UnlockCommercialFeatures -XX:+FlightRecorder"

# Configure Remote JMX
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.port=18980"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.rmi.port=18980"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.local.only=false"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.ssl=false"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.authenticate=true"

# Listen on all interfaces
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dopennms.poller.server.serverHost=0.0.0.0"

# Accept remote RMI connections on this interface
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Djava.rmi.server.hostname=0.0.0.0"

# If you enable Flight Recorder, be aware of the implications since it is a commercial feature of the Oracle JVM.
#ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:StartFlightRecording=duration=600s,filename=opennms.jfr,delay=1h"
EOF
sudo mv -f $tmp_file $opennms_etc/opennms.conf

cat <<EOF > $tmp_file
admin readwrite
jmx   readonly
EOF
sudo mv -f $tmp_file $opennms_etc/jmxremote.access

sudo chown -R root:root $opennms_etc/

echo "### Installing Hawtio version $hawtio_version..."

hawtio_url=https://oss.sonatype.org/content/repositories/public/io/hawt/hawtio-default/$hawtio_version/hawtio-default-$hawtio_version.war
hawtio_war=$opennms_home/jetty-webapps/hawtio.war
sudo wget -qO $hawtio_war $hawtio_url
sudo unzip -qq $hawtio_war -d $opennms_home/jetty-webapps/hawtio
sudo rm -f $hawtio_war

echo "### Enabling CORS..."

webxml=$opennms_home/jetty-webapps/opennms/WEB-INF/web.xml
sudo cp $webxml $webxml.bak
sudo sed -r -i '/[<][!]--/{$!{N;s/[<][!]--\n  ([<]filter-mapping)/\1/}}' $webxml
sudo sed -r -i '/nrt/{$!{N;N;s/(nrt.*\n  [<]\/filter-mapping[>])\n  --[>]/\1/}}' $webxml
