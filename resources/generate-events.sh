#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

nodeid=${1-1}
server=${2-onmscore.aws.opennms.org:8980}

echo "Updating and importing requisition $requisition on server $server ..."

endpoint="http://$server/opennms/rest/events"
header="Content-Type: application/json"
for i in $(seq 1 10); do
  echo "Sending request $i...";
  curl -s -o /dev/null -u admin:admin -H "$header" -d "{ \"uei\": \"uei.opennms.org/node/nodeDown", \"nodeid\": $nodeid }" "$endpoint" &
done

