#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

onms_repo="stable"
onms_version="-latest-"
grafana_version="5.2.1"
hawtio_version="1.4.68"

########################################

opennms_home=/opt/opennms
opennms_etc=$opennms_home/etc
tmp_file=/tmp/_onms_temp_file

echo "### Installing Common Packages..."

sudo yum -y -q install haveged redis httpd
sudo systemctl enable haveged

echo "### Installing Grafana $grafana_version..."

sudo yum install -y -q https://s3-us-west-2.amazonaws.com/grafana-releases/release/grafana-$grafana_version-1.x86_64.rpm

echo "### Installing NodeJS & Yarn..."

sudo curl --silent --location https://rpm.nodesource.com/setup_10.x | sudo bash -
sudo yum -y -q install gcc-c++ nodejs
sudo npm install -g yarn

echo "### Installing OpenNMS Dependencies from stable repository..."

sudo sed -r -i '/name=Amazon Linux 2/a exclude=rrdtool-*' /etc/yum.repos.d/amzn2-core.repo
sudo yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-stable-rhel7.noarch.rpm
sudo rpm --import /etc/yum.repos.d/opennms-repo-stable-rhel7.gpg
sudo yum install -y -q jicmp jicmp6 jrrd jrrd2 rrdtool 'perl(LWP)' 'perl(XML::Twig)'
sudo yum install -y -q opennms-helm

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

sudo sed -r -i 's/value="DEBUG"/value="WARN"/' $opennms_etc/log4j2.xml
sudo sed -r -i '/manager/s/WARN/DEBUG/' $opennms_etc/log4j2.xml

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
