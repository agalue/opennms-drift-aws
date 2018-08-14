#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

max_files="100000"

########################################

tmp_file=/tmp/_temp.tmp

echo "### Configuring Kernel..."

sudo sed -i 's/^\(.*swap\)/#\1/' /etc/fstab

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
vm.zone_reclaim_mode=0
vm.max_map_count=1048575
EOF
sudo mv $tmp_file /etc/sysctl.d/application.conf

cat <<EOF > $tmp_file
* soft nofile $max_files
* hard nofile $max_files
EOF
sudo mv $tmp_file /etc/security/limits.d/application.conf

cat <<EOF > $tmp_file
[Unit]
Description=Disable Transparent Huge Pages (THP)

[Service]
Type=simple
ExecStart=/bin/sh -c "echo 'never' > /sys/kernel/mm/transparent_hugepage/enabled && echo 'never' > /sys/kernel/mm/transparent_hugepage/defrag"

[Install]
WantedBy=multi-user.target
EOF
sudo mv $tmp_file /etc/systemd/system/disable-thp.service
sudo systemctl daemon-reload
sudo systemctl enable disable-thp
