#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

timezone="America/New_York"

########################################

tmp_file=/tmp/_temp.tmp
mkdir -p /tmp/sources/

echo "### Configuring Timezone..."

sudo timedatectl set-timezone $timezone

echo "### Installing common packages..."

sudo yum -y -q update
sudo yum -y -q install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
sudo yum -y -q install jq unzip net-snmp net-snmp-utils git pytz dstat htop sysstat nmap-ncat tree

echo "### Configuring Net-SNMP..."

snmp_cfg=/etc/snmp/snmpd.conf
sudo cp $snmp_cfg $snmp_cfg.original
cat <<EOF > $tmp_file
rocommunity public default
syslocation AWS
syscontact Account Manager
dontLogTCPWrappersConnects yes
disk /
EOF
sudo mv $tmp_file $snmp_cfg
sudo chmod 600 $snmp_cfg
sudo systemctl enable snmpd
