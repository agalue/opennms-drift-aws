#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

server=${1-localhost}
requisition=${1-OpenNMS}

echo "Updating and importing requisition $requisition on server $server ..."

endpoint="http://$server:8980/opennms/rest/requisitions"
update=$(curl -s -o /dev/null -w '%{http_code}' -u admin:admin -H 'Content-Type: application/xml' -d @$requisition.xml $endpoint)
if [ $update -eq 202 ]; then
  import=$(curl -s -o /dev/null -w '%{http_code}' -u admin:admin -v -XPUT $endpoint/$requisition/import)
  if [ $import -eq 202 ]; then
    echo "Success!"
  else
    echo "ERROR: Cannot request an import of requisition $requisition."
  fi
else
  echo "ERROR: Cannot update requisition $requisition."
fi

