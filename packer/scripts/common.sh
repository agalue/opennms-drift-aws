#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

timezone="America/New_York"

########################################

mkdir -p /tmp/sources/

echo "### Configuring Timezone..."

sudo timedatectl set-timezone $timezone

echo "### Installing common packages..."

sudo yum -y -q update
sudo yum -y -q install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
sudo yum -y -q install jq unzip net-snmp net-snmp-utils git pytz dstat htop sysstat nmap-ncat tree sshpass tmux

echo "### Configuring GIT..."

sudo git config --global user.name "OpenNMS"
sudo git config --global user.email "support@opennms.org"

echo "### Configuring Net-SNMP..."

snmp_cfg=/etc/snmp/snmpd.conf
if [ ! -f $snmp_cfg.original ]; then
  sudo mv $snmp_cfg $snmp_cfg.original
fi
sudo rm -f $snmp_cfg
cat <<EOF | sudo tee -a $snmp_cfg
rocommunity public default
syslocation AWS
syscontact Account Manager
dontLogTCPWrappersConnects yes
disk /
EOF
sudo chmod 600 $snmp_cfg
sudo systemctl enable snmpd

