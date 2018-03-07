#!/bin/bash

region=${1-us-east-2};
source_ami=${2-ami-710e2414};

echo "AWS Region: $region"
echo "AWS Source AMI: $source_ami"
echo

if hash packer 2>/dev/null; then
  packer build activemq.json       -var "region=$region" -var "source_ami=$source_ami" && \
  packer build cassandra.json      -var "region=$region" -var "source_ami=$source_ami" && \
  packer build elasticsearch.json  -var "region=$region" -var "source_ami=$source_ami" && \
  packer build kafka.json          -var "region=$region" -var "source_ami=$source_ami" && \
  packer build kibana.json         -var "region=$region" -var "source_ami=$source_ami" && \
  packer build opennms.json        -var "region=$region" -var "source_ami=$source_ami" && \
  packer build postgresql.json     -var "region=$region" -var "source_ami=$source_ami" && \
  packer build zookeeper.json      -var "region=$region" -var "source_ami=$source_ami" 
else
  echo "ERROR: Packer is not installed."
  echo "       Please go to https://packer.io/ and follow the instructions."
fi
