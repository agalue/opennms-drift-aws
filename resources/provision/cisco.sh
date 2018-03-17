#!/bin/bash

server=${1-localhost}
curl -u admin:admin -v -H 'Content-Type: application/xml' -d @Cisco.definition.xml http://$server:8980/opennms/rest/foreignSources
curl -u admin:admin -v -H 'Content-Type: application/xml' -d @Cisco.requisition.xml http://$server:8980/opennms/rest/requisitions
curl -u admin:admin -v -XPUT http://$server:8980/opennms/rest/requisitions/Cisco/import

