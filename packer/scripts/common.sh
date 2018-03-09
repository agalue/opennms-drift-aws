#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

timezone="America/New_York"
max_files="100000"

########################################

tmp_file=/tmp/_temp.tmp

echo "### Configuring Timezone..."

sudo ln -sf /usr/share/zoneinfo/$timezone /etc/localtime

echo "### Installing common packages..."

sudo yum -y -q update
sudo yum -y -q install jq net-snmp net-snmp-utils git pytz dstat htop sysstat nmap-ncat

echo "### Configuring Net-SNMP..."

snmp_cfg=/etc/snmp/snmpd.conf
sudo cp $snmp_cfg $snmp_cfg.original
cat <<EOF > $tmp_file
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
sudo mv $tmp_file $snmp_cfg
sudo chmod 600 $snmp_cfg

echo "### Configuring Kernel..."

sudo sed -i 's/^\(.*swap\)/#\1/' /etc/fstab

sysctl_cfg=/etc/sysctl.d/application.conf
cat <<EOF > $tmp_file
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_probes=3
net.ipv4.tcp_keepalive_intvl=10
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=16777216
net.core.wmem_default=16777216
net.core.optmem_max=40960
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216

net.ipv4.tcp_window_scaling=1
net.core.netdev_max_backlog=2500
net.core.somaxconn=65000

vm.swappiness=1
EOF
sudo mv $tmp_file $sysctl_cfg

limits_cfg=/etc/security/limits.d/application.conf
cat <<EOF > $tmp_file
* soft nofile $max_files
* hard nofile $max_files
EOF
sudo mv $tmp_file $limits_cfg