# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "opennms" {
  template = "${file("${path.module}/templates/opennms.core.tpl")}"

  vars {
    hostname                = "${element(keys(var.onms_ip_addresses),0)}"
    domainname              = "${aws_route53_zone.private.name}"
    dependencies            = "${join(",",formatlist("%v:5432", aws_route53_record.postgresql_private.*.name))},${join(",",formatlist("%v:9042", aws_route53_record.cassandra_private.*.name))},${join(",",formatlist("%v:9092", aws_route53_record.kafka_private.*.name))},${join(",",formatlist("%v:9200", aws_route53_record.elasticsearch_data_private.*.name))}"
    postgres_onms_url       = "jdbc:postgresql://${join(",", formatlist("%v:5432", aws_route53_record.postgresql_private.*.name))}/opennms?targetServerType=master&amp;loadBalanceHosts=false"
    activemq_url            = "" # All communication with Minions will be managed by Kafka
    kafka_servers           = "${join(",",formatlist("%v:9092", aws_route53_record.kafka_private.*.name))}"
    kafka_security_protocol = "${lookup(var.settings, "kafka_security_protocol")}"
    kafka_security_module   = "${lookup(var.settings, "kafka_security_module")}"
    kafka_client_mechanism  = "${lookup(var.settings, "kafka_client_mechanism")}"
    kafka_user_name         = "${lookup(var.settings, "kafka_user_name")}"
    kafka_user_password     = "${lookup(var.settings, "kafka_user_password")}"
    cassandra_datacenter    = "${lookup(var.settings, "cassandra_datacenter")}"
    cassandra_seed          = "${element(aws_route53_record.cassandra_private.*.name, 0)}"
    cassandra_repfactor     = "${lookup(var.settings, "cassandra_replication_factor")}"
    opennms_ui_servers      = "${join(",", values(var.onms_ui_ip_addresses))}"
    elastic_url             = "${join(",",formatlist("http://%v:9200", aws_route53_record.elasticsearch_data_private.*.name))}"
    elastic_user            = "${lookup(var.settings, "elastic_user")}"
    elastic_password        = "${lookup(var.settings, "elastic_password")}"
    use_redis               = "false"
    use_30sec_frequency     = "${lookup(var.settings, "onms_use_30sec_frequency")}"
  }
}

resource "aws_instance" "opennms" {
  ami           = "${data.aws_ami.opennms.image_id}"
  instance_type = "${lookup(var.instance_types, "onms_core")}"
  subnet_id     = "${aws_subnet.public.id}"
  key_name      = "${var.aws_key_name}"
  private_ip    = "${element(values(var.onms_ip_addresses),0)}"
  user_data     = "${data.template_file.opennms.rendered}"

  associate_public_ip_address = true

  vpc_security_group_ids = [
    "${aws_security_group.common.id}",
    "${aws_security_group.opennms.id}",
  ]

  depends_on = [
    "aws_route53_record.opennms_private",
  ]

  provisioner "file" {
    source      = "./resources/provision/"
    destination = "/tmp"
  }

  connection {
    user        = "ec2-user"
    private_key = "${file("${var.aws_private_key}")}"
  }

  timeouts {
    create = "30m"
    delete = "15m"
  }

  tags {
    Name = "Terraform OpenNMS Core Server"
  }
}

resource "aws_route53_record" "opennms" {
  zone_id = "${aws_route53_zone.main.zone_id}"
  name    = "${element(keys(var.onms_ip_addresses),0)}.${aws_route53_zone.main.name}"
  type    = "A"
  ttl     = "${var.dns_ttl}"
  records = [
    "${aws_instance.opennms.public_ip}",
  ]
}

resource "aws_route53_record" "opennms_private" {
  count   = "${length(var.onms_ip_addresses)}"
  zone_id = "${aws_route53_zone.private.zone_id}"
  name    = "${element(keys(var.onms_ip_addresses), count.index)}.${aws_route53_zone.private.name}"
  type    = "A"
  ttl     = "${var.dns_ttl}"
  records = [
    "${element(values(var.onms_ip_addresses), count.index)}",
  ]
}

output "onmscore" {
  value = "${aws_instance.opennms.public_ip}"
}
