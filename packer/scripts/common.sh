#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

timezone="America/New_York"
max_files="100000"

########################################

mkdir -p /tmp/sources/

echo "### Configuring Timezone..."

sudo timedatectl set-timezone $timezone

echo "### Installing common packages..."

sudo yum -y -q update
sudo yum -y -q install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
sudo yum -y -q install jq unzip net-snmp net-snmp-utils git pytz dstat htop sysstat nmap-ncat tree sshpass tmux

echo "### Configuring Net-SNMP..."

snmp_cfg=/etc/snmp/snmpd.conf
sudo cp $snmp_cfg $snmp_cfg.original
cat <<EOF | sudo tee -a $snmp_cfg
rocommunity public default
syslocation AWS
syscontact Account Manager
dontLogTCPWrappersConnects yes
disk /
EOF
sudo chmod 600 $snmp_cfg
sudo systemctl enable snmpd

echo "### Configuring Kernel..."

sudo sed -i 's/^\(.*swap\)/#\1/' /etc/fstab

cat <<EOF | sudo tee -a /etc/sysctl.d/application.conf
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
vm.zone_reclaim_mode=0
vm.max_map_count=1048575
EOF

cat <<EOF > | sudo tee -a /etc/security/limits.d/application.conf
* soft nofile $max_files
* hard nofile $max_files
EOF

cat <<EOF | sudo tee -a /etc/systemd/system/disable-thp.service
[Unit]
Description=Disable Transparent Huge Pages (THP)

[Service]
Type=simple
ExecStart=/bin/sh -c "echo 'never' > /sys/kernel/mm/transparent_hugepage/enabled && echo 'never' > /sys/kernel/mm/transparent_hugepage/defrag"

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable disable-thp
