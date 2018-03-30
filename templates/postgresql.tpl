#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# Warning: The version family should match the Packer image

# AWS Template Variables

node_id="${node_id}"
vpc_cidr="${vpc_cidr}"
hostname="${hostname}"
domainname="${domainname}"
pg_max_connections="${pg_max_connections}"
pg_version_family="${pg_version_family}"
pg_role="${pg_role}"
pg_rep_slots="${pg_rep_slots}"
pg_master_server="${pg_master_server}"

# Internal Variables

pg_version=`echo $pg_version_family | sed 's/-.//'`
pg_family=`echo $pg_version | sed 's/\.//'`
repmgr_cfg=/etc/repmgr/$pg_version/repmgr.conf
repmgr_bin=/usr/pgsql-$pg_version/bin/repmgr
data_dir=/var/lib/pgsql/$pg_version/data
hba_conf=$data_dir/pg_hba.conf
pg_conf=$data_dir/postgresql.conf

cat <<EOF > /etc/profile.d/postgresql.sh
PATH=/usr/pgsql-$pg_version/bin:\$PATH
EOF

source /etc/profile.d/postgresql.sh

echo "### Configuring Hostname and Domain..."

sed -i -r "s/HOSTNAME=.*/HOSTNAME=$hostname.$domainname/" /etc/sysconfig/network
hostname $hostname.$domainname
domainname $domainname
sed -i -r "s/#Domain =.*/Domain = $domainname/" /etc/idmapd.conf

echo "### Configuring repmgr..."

cat <<EOF > /etc/sudoers.d/postgres
Defaults:postgres !requiretty
postgres ALL = NOPASSWD: /bin/systemctl status postgresql-$pg_version, \
/bin/systemctl start postgresql-$pg_version, \
/bin/systemctl stop postgresql-$pg_version, \
/bin/systemctl reload postgresql-$pg_version, \
/bin/systemctl restart postgresql-$pg_version
EOF
chmod 440 /etc/sudoers.d/postgres

cp $repmgr_cfg $repmgr_cfg.bak
cat <<EOF > $repmgr_cfg
node_id=$node_id
node_name=$hostname
conninfo='host=$hostname user=repmgr dbname=repmgr'
data_directory=$data_dir
use_replication_slots=true
log_level=INFO
failover=automatic
pg_bindir='/usr/pgsql-$pg_version/bin'
promote_command='$repmgr_bin standby promote -f $repmgr_cfg --log-to-file'
follow_command='$repmgr_bin standby follow -f $repmgr_cfg --log-to-file --upstream-node-id=%n'
service_start_command='sudo systemctl start postgresql-$pg_version'
service_stop_command='sudo systemctl stop postgresql-$pg_version'
service_reload_command='sudo systemctl reload postgresql-$pg_version'
service_restart_command='sudo systemctl restart postgresql-$pg_version'
EOF
chown postgres:postgres $repmgr_cfg

echo "### Configuring PostgreSQL..."

pgpass=/var/lib/pgsql/.pgpass
cat <<EOF > $pgpass
*:*:*:repmgr:repmgr
*:*:replication:postgres:postgres
EOF
chown postgres:postgres $pgpass
chmod 600 $pgpass

if [ "$pg_role" == "master" ]; then

  echo "### Configuring Master Server..."

  /usr/pgsql-$pg_version/bin/postgresql$pg_family-setup initdb

  sed -r -i "s/(peer|ident)/trust/g" $hba_conf
  sed -r -i "s|127.0.0.1/32|$vpc_cidr|g" $hba_conf

  cat <<EOF >> $hba_conf

# repmgr
local   replication   repmgr                   trust
host    replication   repmgr    127.0.0.1/32   trust
host    replication   repmgr    $vpc_cidr      trust
local   repmgr        repmgr                   trust
host    repmgr        repmgr    127.0.0.1/32   trust
host    repmgr        repmgr    $vpc_cidr      trust
EOF

  sed -r -i "s/[#]?listen_addresses =.*/listen_addresses = '*'/" $pg_conf
  sed -r -i "s/[#]?max_connections =.*/max_connections = $pg_max_connections/" $pg_conf
  sed -r -i "s/[#]?wal_level =.*/wal_level = 'hot_standby'/" $pg_conf
  sed -r -i "s/[#]?wal_log_hints =.*/wal_log_hints = on/" $pg_conf
  sed -r -i "s/[#]?wal_sender_timeout =.*/wal_sender_timeout = 1s/" $pg_conf
  sed -r -i "s/[#]?max_wal_senders =.*/max_wal_senders = 16/" $pg_conf
  sed -r -i "s/[#]?max_replication_slots =.*/max_replication_slots = $pg_rep_slots/" $pg_conf
  sed -r -i "s/[#]?checkpoint_completion_target =.*/checkpoint_completion_target = 0.7/" $pg_conf
  sed -r -i "s/[#]?hot_standby =.*/hot_standby = on/" $pg_conf
  sed -r -i "s/[#]?log_connections =.*/log_connections = on/" $pg_conf
  sed -r -i "s/[#]?default_statistics_target =.*/default_statistics_target = 100/" $pg_conf
  sed -r -i "s/[#]?shared_preload_libraries =.*/shared_preload_libraries = 'repmgr'/" $pg_conf

  echo "### Starting PostgreSQL..."

  systemctl enable postgresql-$pg_version
  systemctl start postgresql-$pg_version
  sleep 10

  echo "### Configuring repmgr..."

  sudo -u postgres psql -c "CREATE USER repmgr SUPERUSER REPLICATION LOGIN ENCRYPTED PASSWORD 'repmgr';"
  sudo -u postgres psql -c "CREATE DATABASE repmgr OWNER repmgr;"
  sudo -u postgres psql -c "ALTER USER postgres WITH ENCRYPTED PASSWORD 'postgres';"

  echo "### Registering master node through repmgr..."

  sudo -u postgres $repmgr_bin -f $repmgr_cfg -v master register
  sudo -u postgres $repmgr_bin -f $repmgr_cfg cluster show

else

  echo "### Configuring Slave Server..."
  sleep 30

  sudo -u postgres $repmgr_bin -h $pg_master_server -U repmgr -d repmgr -f $repmgr_cfg -W --dry-run standby clone
  if [ $? -eq 0 ]; then
    echo "### Cloning data from master node..."

    sudo -u postgres $repmgr_bin -h $pg_master_server -U repmgr -d repmgr -f $repmgr_cfg -W standby clone

    echo "### Starting PostgreSQL..."

    systemctl enable postgresql-$pg_version
    systemctl start postgresql-$pg_version
    sleep 10

    echo "### Registering slave node through repmgr..."

    sudo -u postgres $repmgr_bin -f $repmgr_cfg -v standby register
    sudo -u postgres $repmgr_bin -f $repmgr_cfg cluster show
  else
    echo "### ERROR: There was a problem and repmgr was not able to setup the standby server $hostname ..."
  fi

fi

echo "### Starting repmgrd..."

systemctl enable repmgr$pg_family
systemctl start repmgr$pg_family

echo "### Enabling and starting SNMP..."

systemctl enable snmpd
systemctl start snmpd
