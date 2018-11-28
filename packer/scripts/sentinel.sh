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
sudo git init .
sudo git add .
sudo git commit -m "Sentinel Installed."
cd

echo "### Copying external configuration files..."

src_dir=/tmp/sources
sudo chown -R root:root $src_dir/
sudo rsync -avr $src_dir/ $sentinel_etc/
sudo chown sentinel:sentinel $sentinel_etc

echo "### Increasing file descriptors for the sentinel user..."

cat <<EOF > /etc/security/limits.d/sentinel.conf
sentinel soft nofile 300000
sentinel hard nofile 300000
EOF

echo "### Install OpenNMS Correlation Engine (OCE)..."

for rpm in $(find ~/oce/assembly/sentinel-rpm -name *.rpm); do
  echo "Installing $rpm..."
  sudo yum -y -q install $rpm
done

sudo chown -R sentinel:sentinel $sentinel_home
