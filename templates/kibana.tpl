#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

# AWS Template Variables

hostname="${hostname}"
domainname="${domainname}"
es_servers="${es_servers}"
es_user="${es_user}"
es_password="${es_password}"
es_monsrv="${es_monsrv}"

echo "### Configuring Hostname and Domain..."

ip_address=`curl http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null`
hostnamectl set-hostname --static $hostname
echo "preserve_hostname: true" > /etc/cloud/cloud.cfg.d/99_hostname.cfg
sed -i -r "s/^[#]?Domain =.*/Domain = $domainname/" /etc/idmapd.conf

echo "### Configuring Kibana..."

kb_dir=/etc/kibana
kb_yaml=$kb_dir/kibana.yml

sed -i -r "s/[#]?server.host:.*/server.host: \"$hostname\"/" $kb_yaml
sed -i -r "s/[#]?server.name:.*/server.name: \"$hostname\"/"  $kb_yaml
sed -i -r "s|[#]?elasticsearch.url:.*|elasticsearch.url: \"http://127.0.0.1:9200\"|" $kb_yaml
sed -i -r "s/[#]?elasticsearch.username:.*/elasticsearch.username: \"$es_user\"/" $kb_yaml
sed -i -r "s/[#]?elasticsearch.password:.*/elasticsearch.password: \"$es_password\"/" $kb_yaml

if [[ "$es_monsrv" != "" ]]; then
  echo >> $kb_yaml
  echo xpack.monitoring.elasticsearch.url: "http://$es_monsrv:9200" >> $kb_yaml
fi

echo "### Waiting for Elasticsearch..."

for server in $${es_servers//,/ }; do
  data=($${server//:/ })
  echo "Waiting for server $${data[0]} on port $${data[1]}..."
  until printf "" 2>>/dev/null >>/dev/tcp/$${data[0]}/$${data[1]}; do printf '.'; sleep 1; done
done

echo "### Creating a NGinx load balancer for Elasticsearch..."

yum install -y -q nginx

lb_cfg=/etc/nginx/conf.d/elasticsearch.conf
echo "upstream elasticsearch {" > $lb_cfg
for server in $${es_servers//,/ }; do
  echo "server $server;" >> $lb_cfg
done
cat <<EOF >> $lb_cfg
}
server {
  listen 9200;
  location / {
    proxy_pass http://elasticsearch;
  }
}
EOF

echo "### Enabling and starting NGinx..."

systemctl enable nginx
systemctl start nginx

echo "### Enabling and starting Kibana..."

systemctl enable kibana
systemctl start kibana
