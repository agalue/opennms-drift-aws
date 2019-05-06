#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# The Elasticsearch version cannot be changed due to required dependencies:
# https://github.com/OpenNMS/elasticsearch-drift-plugin

######### CUSTOMIZED VARIABLES #########

es_version="6.7.0"
curator_version="5.4.1"
maven_version="3.5.3"
plugin_branch="master"
compile_plugin="yes"

########################################

es_config=/etc/elasticsearch

echo "### Downloading and installing Elasticsearch version $es_version..."

sudo yum install -y -q https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$es_version.rpm

echo "### Initializing GIT at $es_config..."

sudo cd $es_config
sudo git init .
sudo git add .
sudo git commit -m "Elasticsearch $es_version installed."
cd

echo "### Downloading and installing Curator version $curator_version..."

sudo yum install -y -q https://packages.elastic.co/curator/5/centos/7/Packages/elasticsearch-curator-$curator_version-1.x86_64.rpm

if [ "$compile_plugin" == "yes" ]; then

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

  echo "### Installing the OpenNMS Drift Plugin from branch $plugin_branch..."

  sudo yum install -y -q rpm-build

  mkdir ~/development
  cd ~/development
  sudo git clone https://github.com/OpenNMS/elasticsearch-drift-plugin.git

  cd elasticsearch-drift-plugin

  if [[ `git branch | grep "^[*] $plugin_branch" | sed -e 's/[* ]*//'` == "$plugin_branch" ]]; then
    echo "### Already in branch $plugin_branch"
  else
    echo "### Checking out branch $plugin_branch"
    sudo git checkout -b $plugin_branch origin/$plugin_branch
  fi

  sudo sed -r -i "s/elasticsearch.version[>][0-9.]*[<]/elasticsearch.version>$es_version</" pom.xml
  sudo /opt/maven/bin/mvn install -q -DskipTests=true rpm:rpm

  rpmfile=`find target -name *.rpm`
  sudo yum install -y -q $rpmfile
  cd

else

  echo "### Installing the OpenNMS Drift Plugin..."

  sudo yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-stable-rhel7.noarch.rpm
  sudo rpm --import /etc/yum.repos.d/opennms-repo-stable-rhel7.gpg
  sudo yum install -y -q elasticsearch-drift-plugin

fi