#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

echo "### Installing common packages..."

sudo yum -y -q update
sudo yum -y -q install jq net-snmp net-snmp-utils git pytz dstat htop sysstat nmap-ncat

echo "### Configuring and enabling SNMP..."

snmp_tmp=/tmp/snmpd.conf
snmp_cfg=/etc/snmp/snmpd.conf
sudo cp $snmp_cfg $snmp_cfg.original
cat <<EOF > $snmp_tmp
com2sec localUser default public
group localGroup v1 localUser
group localGroup v2c localUser
view all included .1 80
access localGroup "" any noauth 0 all none none
syslocation AWS
syscontact Account Manager
dontLogTCPWrappersConnects yes
disk /
EOF
sudo cp $snmp_tmp $snmp_cfg
sudo chmod 600 $snmp_cfg

