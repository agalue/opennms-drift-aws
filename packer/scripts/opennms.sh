#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

onms_repo="branches-features-drift"
onms_version="-latest-"

########################################

echo "### Installing OpenNMS Dependencies from stable repository..."

sudo sed -r -i '/name=Amazon Linux 2/a exclude=rrdtool-*' /etc/yum.repos.d/amzn2-core.repo
sudo yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-stable-rhel7.noarch.rpm
sudo rpm --import /etc/yum.repos.d/opennms-repo-stable-rhel7.gpg
sudo yum install -y -q jicmp jicmp6 jrrd jrrd2 rrdtool 'perl(LWP)' 'perl(XML::Twig)'

if [ "${onms_repo}" != "stable" ]; then
  echo "### Installing OpenNMS ${onms_repo} Repository..."
  sudo yum remove -y -q opennms-repo-stable
  sudo yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-${onms_repo}-rhel7.noarch.rpm
  sudo rpm --import /etc/yum.repos.d/opennms-repo-${onms_repo}-rhel7.gpg
fi

if [ "${onms_version}" == "-latest-" ]; then
  echo "### Installing latest OpenNMS from ${onms_repo} Repository..."
  sudo yum install -y -q opennms-core opennms-webapp-jetty
else
  echo "### Installing OpenNMS version ${onms_version} from ${onms_repo} Repository..."
  sudo yum install -y -q opennms-core-${onms_version} opennms-webapp-jetty-${onms_version}
fi

echo "### Initializing GIT..."

opennms_home=/opt/opennms
opennms_etc=$opennms_home/etc

cd $opennms_etc
sudo git config --global user.name "OpenNMS"
sudo git config --global user.email "support@opennms.org"
sudo git init .
sudo git add .
sudo git commit -m "OpenNMS Installed."
cd

echo "### Installing Hawtio..."

hawtio_url=https://oss.sonatype.org/content/repositories/public/io/hawt/hawtio-default/1.4.63/hawtio-default-1.4.63.war
sudo wget -qO $opennms_home/jetty-webapps/hawtio.war $hawtio_url && \
  sudo unzip -qq $opennms_home/jetty-webapps/hawtio.war -d $opennms_home/jetty-webapps/hawtio && \
  sudo rm -f $opennms_home/jetty-webapps/hawtio.war

echo "### Enabling CORS..."

webxml=$opennms_home/jetty-webapps/opennms/WEB-INF/web.xml
sudo cp $webxml $webxml.bak
sudo sed -r -i '/[<][!]--/{$!{N;s/[<][!]--\n  ([<]filter-mapping)/\1/}}' $webxml
sudo sed -r -i '/nrt/{$!{N;N;s/(nrt.*\n  [<]\/filter-mapping[>])\n  --[>]/\1/}}' $webxml
