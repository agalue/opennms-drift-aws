# OpenNMS Drift deployment in AWS for testing purposes

![diagram](resources/diagram.png)

> IMPORTANT: This deployment uses Kafka SASL authentication by default. For this reason Horizon 23.0.1 is required. In order to use an older version, SASL authentication for Kafka has to be disabled.

## Installation and usage

* Make sure you have your AWS credentials on `~/.aws/credentials`, for example:

```INI
[default]
aws_access_key_id = XXXXXXXXXXXXXXXXX
aws_secret_access_key = XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

* Install the Terraform binary from [terraform.io](https://www.terraform.io)

* Install the Packer binary from [packer.io](https://www.packer.io)

* Install VirtualBox from [virtualbox.org](https://www.virtualbox.org)

* Install Vagrant from [vagrantup.com](https://www.vagrantup.com)

* Make sure the AMIs used for the Packer JSON files match your chosen region in AWS (Amazon Linux 2 for `us-east-2` is the default).

* Tweak the versions on the packer initialization scripts located at `packer/scripts`.

* Tweak the common settings on `vars.tf`, in particular:

  * `aws_key_name` and `aws_private_key`, to match the chosen region.
  * `parent_dns_zone` and `dns_zone`, to match an existing Route 53 Hosted Zone.

  All the customizable settings are defined on `vars.tf`. Please do not change the other `.tf` files.

  An internal DNS is also maintained to improve the speed of the service discovery (application dependencies).

* Build the custom AMIs using Packer:

```SHELL
cd packer
. build.sh
```

Of, in order to build a specific image:

```SHELL
cd packer
packer build opennms.json
```

Packer will use the default VPC and the default subnet for the chosen region. If you want to use a specific VPC/Subnet, please update the Packer JSON files.

* Execute the following commands from the repository's root directory (at the same level as the .tf files):

```SHELL
terraform init
terraform plan
terraform apply
```

* Initialize the Minion VMs using Vagrant:

```SHELL
cd resources/minion
vagrant up
```

* Enjoy!

## Requirements

* OpenNMS Horizon version 23.0.1 or newer is required. Currently, the RPMs from the `release-23.0.1` branch are being used in order to test Sentinels and Minions, all with SASL Auth for Kafka.

* Time synchronization is mandatory on every single device (including monitored devices). AWS guarrantees that, meaning the Minion and the Flow Exporters should also be synchronized prior start using this lab (either by using NTP or manual sync).

* In case of using GNS3 to test a Cisco Lab, make the Minion machine an NTP server, and then configure the Cisco routers/switches to use it.

## Design

The purpose here is understand the Drift Architecture for OpenNMS, not using AWS resources like RDS, SQS, etc. to deploy OpenNMS on the cloud.

For this reason, everything will live on the same subnet (a.k.a. one availability zone) with direct Internet access through an Internet Gateway. All the EC2 instances are going to have a specific private IP address, registered on a public DNS domain through Route 53, which is how the operator can connect to each instance, and the way Minion will reach the solution.

Thanks to packer, all the required software will be part of the respective custom AMIs. Those AMIs should be re-created only when the installed software should be changed. Otherwise, they can be re-used, drastically reducing the time to have the EC2 instances ready, as they will just make configuration changes.

The architecture involves the following components:

* A cluster of 3 EC2 instances for Cassandra/Newts.

* A cluster of 3 EC2 instances for Zookeeper (required by Kafka). 

* A cluster of 3 EC2 instances for Kafka.

* A cluster of 6 EC2 instances for Elasticsearch (3 dedicated master nodes, and 3 dedicated data/ingest nodes).

* A cluster of 2 EC2 instances for OpenNMS UI and Grafana.

* A cluster of 2 EC2 instances for OpenNMS Sentinel (work in progress).

* A pair of EC2 instances for PostgreSQL, configured as master/slave with streaming replication, using repmgr to simplify the operation.

* An EC2 instance for the central OpenNMS.

* An EC2 instance for Kibana.

* Private DNS through Route 53 for all the instances.

* Public DNS through Route 53 for all the instances, based on an existing Hosted Zone associated with a Public Domain.

* Outside AWS, there is a Vagrant script to setup 2 Minions, pointing to the AWS environment through the external DNS.

For scalability, the clusters for Kafka, ES Data, Cassandra and ONMS UI can be increased without issues. That being said, the clusters for Zookeeper, and ES Master should remain at 3.

**The way on which all the components should be configured relfect the best practices for production (except for the sizes of the EC2 instances).**

## Retention Periods in Kafka

All the Kafka Topics are created automatically by Kafka when OpenNMS or Minion use the topic for the first time. The topics will be created using the default settings, which means, the default retention will be 7 days for all the topics.

There are special cases like RPC Topics where it doesn't make sense to have a long retention, as the messages won't be re-used after the TTL. For this reason, keeping those messages for a couple of hours is more than enough.

The following script updates the retention (should be executed from one of the Kafka servers):

```shell
config="retention.ms=7200000"
zookeeper="zookeeper1:2181/kafka"
for topic in $(/opt/kafka/bin/kafka-topics.sh --list --zookeeper $zookeeper | grep rpc); do
  /opt/kafka/bin/kafka-configs.sh --zookeeper $zookeeper --alter --entity-type topics --entity-name $topic --add-config $config
done
```

If the performance metrics are also being forwarded to Kafka, it is also recommended to set a more conservative numbers for the retention, as the intention for this is being able to process the metrics through the Streaming API, or forward the metrics to another application through the Kafka Sink API (or a standalone application). Once the data is processed, it can be discarded.

## Limitations

* Be aware of EC2 instance limits on your AWS account for the chosen region, as it might be possible that you won't be able to use this POC unless you increase the limits. The default limit is 20, and this POC will be creating more than that.

* The OpenNMS UI servers have been configured to be read-only in terms of admintration tasks. So, even admin users won't be able to perform administration tasks, but user actions like acknowledging alarms are still available. All administrative tasks should be done through the Core OpenNMS server.

* Grafana doesn't support multi-host database connections. That means, the solution points to the master PG server. If the master server dies, the `grafana.ini` should be manually updated, and Grafana should be restarted on each UI server, unless a VIP and/or a solution like PGBounder or PGPool is used. For more information: https://github.com/grafana/grafana/issues/3676

* This is just a proof of concept for all the components required to deploy Drift. Besides EC2 instance type changes, configuration changes might be required to make this solution production ready.

* The bootstrap scripts are very simple and are not designed to be re-executed, as they do not perform validations. Also, in order to get the runtime version of the scripts, the following command should be executed from the desired instance:

```SHELL
curl http://169.254.169.254/latest/user-data > /tmp/bootstrap-script.sh
```

## Future enhancements

* Enable authentication for all services.

* Add an instance for Kafka Manager to avoid exposing JMX to the public.

* Tune the security groups to only expose what Minions need.

* Add cron jobs to OpenNMS to apply the constraints for the RPC Topics on Kafka, as default retention/storage is not required in this particular case, but unfortunately this cannot be configured within OpenNMS.

* Improve the Elasticsearch cluster architecture to have a dedicated monitoring cluster (assuming X-Pack will be used).

* Create a simple NGinx LoadBalancer for the OpenNMS WebUI (on a tiny EC2 instance to avoid an ELB).

* Make the bootstrap scripts reusable (i.e. to be able to execute them multiple times without side effects, in case the bootstrap process was wrong).

* Enable security every where with passwords, SSL/TLS, or other mechanisms.
  * SSL Certificates might be required, so [Let's Encrypt](https://letsencrypt.org/) can help.
  * Proper configuration of X-Pack is required for Elasticsearch (at least the trial license).
  * Use MD5 password authentication for PostgreSQL.
  * For Kafka, SASL/Kerberos is recommended, so we might need a Kerberos Server (at least from Interface facing perspective, as OpenNMS Core and Sentinels can use PLAINTEXT without issues).
  * Enable SSL/TLS for Kafka (Internet facing, i.e. for Minions).
  * Only expose through Security Groups what's required to be accessed and nothing else.
