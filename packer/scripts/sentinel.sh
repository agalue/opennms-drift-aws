#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

sentinel_repo="bleeding"
sentinel_version="-latest-"
maven_version="3.6.0"

########################################

sentinel_home=/opt/sentinel
sentinel_etc=$sentinel_home/etc

echo "### Installing Common Packages..."

sudo yum -y -q install haveged
sudo systemctl enable haveged

echo "### Installing Sentinel $sentinel_repo Repository..."
sudo yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-$sentinel_repo-rhel7.noarch.rpm
sudo rpm --import /etc/yum.repos.d/opennms-repo-$sentinel_repo-rhel7.gpg

echo "### Installing Sentinel Packages..."
sudo yum install -y -q opennms-sentinel*

echo "### Initializing GIT at $sentinel_etc..."

cd $sentinel_etc
sudo git config --global user.name "OpenNMS"
sudo git config --global user.email "support@opennms.org"
sudo git init .
sudo git add .
sudo git commit -m "Sentinel Installed."
cd

echo "### Copying external configuration files..."

src_dir=/tmp/sources
sudo chown -R root:root $src_dir/
sudo rsync -avr $src_dir/ $sentinel_etc/
sudo chown sentinel:sentinel $sentinel_etc

echo "### Installing Maven version $maven_version..."

maven_name=apache-maven-$maven_version
maven_file=$maven_name-bin.zip
maven_mirror=$(curl --stderr /dev/null https://www.apache.org/dyn/closer.cgi\?as_json\=1 | jq -r '.preferred')
maven_url="${maven_mirror}maven/maven-3/$maven_version/binaries/$maven_file"

cd /opt
sudo wget -q "$maven_url" -O "$maven_file"
sudo unzip -q $maven_file
sudo chown -R root:root $maven_name
sudo ln -s $maven_name maven
sudo rm -f $maven_file
cd

echo "### Compiling OpenNMS Correlation Engine (OCE)..."

export PATH=/opt/maven/bin:$PATH
git clone https://github.com/OpenNMS/oce.git
cd oce
mvn -q package install
sudo rsync -avr ~/.m2/repository/ $sentinel_home/system/
sudo chown -R sentinel:sentinel $sentinel_home/system
cd
