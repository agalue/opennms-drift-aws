#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

repo_version="2.3"
timezone="America/New_York"
ubuntu="bionic"
max_files="100000"

########################################

echo "### Configuring Timezone..."

sudo timedatectl set-timezone $timezone

echo "### Installing common packages..."

sudo apt-get update
#sudo apt-get upgrade -y
sudo apt-get install jq unzip snmp snmpd snmp-mibs-downloader dstat htop sysstat tree -y

echo "### Configuring Net-SNMP..."

snmp_cfg=/etc/snmp/snmpd.conf
sudo cp $snmp_cfg $snmp_cfg.original
cat <<EOF | sudo tee -a $snmp_cfg
agentaddress udp:161
view all included .1
rocommunity public default -V all
syslocation AWS
syscontact Account Manager
dontLogTCPWrappersConnects yes
disk /
EOF
sudo chmod 600 $snmp_cfg
sudo systemctl enable snmpd

echo "### Downloading and installing ScyllaDB..."

sudo wget -qO /etc/apt/sources.list.d/scylla-$repo_version-$ubuntu.list  http://downloads.scylladb.com.s3.amazonaws.com/deb/ubuntu/scylla-$repo_version-$ubuntu.list
wget -qO - http://downloads.scylladb.com.s3.amazonaws.com/deb/scylladb.gpg.pubkey | sudo apt-key add -
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 6B2BFD3660EF3F5B
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 17723034C56D4B19
sudo apt-get update
sudo apt-get install scylla -y

scylladb_config=/etc/scylla

echo "### Initializing GIT at $scylladb_config..."

cd $scylladb_config
sudo git config --global user.name "OpenNMS"
sudo git config --global user.email "support@opennms.org"
sudo git init .
sudo git add .
sudo git commit -m "ScyllaDB installed."
cd
