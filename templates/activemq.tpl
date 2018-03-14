#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# Warning: This is intended to be used through Terraform's template plugin only

# AWS Template Variables
# - node_id = ${node_id}
# - hostname = ${hostname}
# - domainname = ${domainname}
# - amq_sibling = ${amq_sibling}

echo "### Configuring Hostname and Domain..."

sed -i -r "s/HOSTNAME=.*/HOSTNAME=${hostname}.${domainname}/" /etc/sysconfig/network
hostname ${hostname}.${domainname}
domainname ${domainname}

echo "### Configuring ActiveMQ..."

total_mem_in_mb=`free -m | awk '/:/ {print $2;exit}'`
mem_in_mb=`expr $total_mem_in_mb / 2`
if [ "$mem_in_mb" -gt "8192" ]; then
  mem_in_mb="8192"
fi
sed -i -r "/^ACTIVEMQ_OPTS_MEMORY/s/\"-Xm.*\"/\"-Xms$${mem_in_mb}m -Xmx$${mem_in_mb}m\"/" /opt/activemq/bin/env

ln -s /opt/activemq/bin/activemq /etc/init.d/activemq

cat <<EOF > /opt/activemq/conf/activemq.xml
<beans
  xmlns="http://www.springframework.org/schema/beans"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://www.springframework.org/schema/beans http://www.springframework.org/schema/beans/spring-beans.xsd
  http://activemq.apache.org/schema/core http://activemq.apache.org/schema/core/activemq-core.xsd">

    <bean class="org.springframework.beans.factory.config.PropertyPlaceholderConfigurer">
        <property name="locations">
            <value>file:\$${activemq.conf}/credentials.properties</value>
        </property>
    </bean>

    <bean id="logQuery" class="io.fabric8.insight.log.log4j.Log4jLogQuery"
          lazy-init="false" scope="singleton"
          init-method="start" destroy-method="stop">
    </bean>

    <broker xmlns="http://activemq.apache.org/schema/core" brokerName="${hostname}" brokerId="${hostname}" dataDirectory="\$${activemq.data}">

        <destinationPolicy>
            <policyMap>
              <policyEntries>
                <policyEntry topic=">" >
                  <pendingMessageLimitStrategy>
                    <constantPendingMessageLimitStrategy limit="1000"/>
                  </pendingMessageLimitStrategy>
                </policyEntry>
              </policyEntries>
            </policyMap>
        </destinationPolicy>

        <managementContext>
            <managementContext createConnector="false"/>
        </managementContext>

        <persistenceAdapter>
            <kahaDB directory="\$${activemq.data}/kahadb"/>
        </persistenceAdapter>

        <systemUsage>
            <systemUsage>
                <memoryUsage>
                    <memoryUsage percentOfJvmHeap="70" />
                </memoryUsage>
                <storeUsage>
                    <storeUsage limit="100 gb"/>
                </storeUsage>
                <tempUsage>
                    <tempUsage limit="50 gb"/>
                </tempUsage>
            </systemUsage>
        </systemUsage>

        <networkConnectors>
            <networkConnector name="LinkTo -> ${amq_sibling}"
                uri="static:(tcp://${amq_sibling}:61616)"
                networkTTL="3"
            />            
        </networkConnectors>

        <transportConnectors>
            <transportConnector name="openwire" uri="tcp://0.0.0.0:61616?maximumConnections=1000&amp;wireFormat.maxFrameSize=104857600"/>
        </transportConnectors>

        <shutdownHooks>
            <bean xmlns="http://www.springframework.org/schema/beans" class="org.apache.activemq.hooks.SpringContextHook" />
        </shutdownHooks>

    </broker>

    <import resource="jetty.xml"/>

</beans>
EOF

echo "### Enabling and starting ActiveMQ..."

systemctl enable activemq
systemctl start activemq

echo "### Enabling and starting SNMP..."

systemctl enable snmpd
systemctl start snmpd
