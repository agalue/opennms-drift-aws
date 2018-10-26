# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "opennms_sentinel" {
  count    = "${length(var.onms_sentinel_ip_addresses)}"
  template = "${file("${path.module}/templates/opennms.sentinel.tpl")}"

  vars {
    hostname                = "${element(keys(var.onms_sentinel_ip_addresses), count.index)}"
    domainname              = "${aws_route53_zone.private.name}"
    dependencies            = "${aws_route53_record.opennms_private.name}:8980" # To make sure that the DB was initialized, and the rest of the dependencies are available
    postgres_onms_url       = "jdbc:postgresql://${join(",", formatlist("%v:5432", aws_route53_record.postgresql_private.*.name))}/opennms?targetServerType=master&amp;loadBalanceHosts=false"
    kafka_servers           = "${join(",",formatlist("%v:9092", aws_route53_record.kafka_private.*.name))}"
    kafka_security_protocol = "${lookup(var.settings, "kafka_security_protocol")}"
    kafka_security_module   = "${lookup(var.settings, "kafka_security_module")}"
    kafka_client_mechanism  = "${lookup(var.settings, "kafka_client_mechanism")}"
    kafka_user_name         = "${lookup(var.settings, "kafka_user_name")}"
    kafka_user_password     = "${lookup(var.settings, "kafka_user_password")}"
    elastic_url             = "${join(",",formatlist("http://%v:9200", aws_route53_record.elasticsearch_data_private.*.name))}"
    elastic_user            = "${lookup(var.settings, "elastic_user")}"
    elastic_password        = "${lookup(var.settings, "elastic_password")}"
    elastic_index_strategy  = "${lookup(var.settings, "elastic_flow_index_strategy")}"
    opennms_url             = "http://${aws_route53_record.opennms_private.name}:8980/opennms"
    sentinel_location       = "AWS"
  }
}

resource "aws_instance" "opennms_sentinel" {
  count         = "${length(var.onms_sentinel_ip_addresses)}"
  ami           = "${data.aws_ami.sentinel.image_id}"
  instance_type = "${lookup(var.instance_types, "onms_sentinel")}"
  subnet_id     = "${aws_subnet.public.id}"
  key_name      = "${var.aws_key_name}"
  private_ip    = "${element(values(var.onms_sentinel_ip_addresses), count.index)}"
  user_data     = "${element(data.template_file.opennms_sentinel.*.rendered, count.index)}"

  associate_public_ip_address = true

  vpc_security_group_ids = [
    "${aws_security_group.common.id}",
    "${aws_security_group.sentinel.id}",
  ]

  depends_on = [
    "aws_route53_record.opennms_sentinel_private",
  ]

  connection {
    user        = "ec2-user"
    private_key = "${file("${var.aws_private_key}")}"
  }

  timeouts {
    create = "30m"
    delete = "15m"
  }

  tags {
    Name = "Terraform OpenNMS Sentinel ${count.index + 1}"
  }
}

resource "aws_route53_record" "opennms_sentinel" {
  count   = "${length(var.onms_sentinel_ip_addresses)}"
  zone_id = "${aws_route53_zone.main.zone_id}"
  name    = "${element(keys(var.onms_sentinel_ip_addresses), count.index)}.${aws_route53_zone.main.name}"
  type    = "A"
  ttl     = "${var.dns_ttl}"
  records = [
    "${element(aws_instance.opennms_sentinel.*.public_ip, count.index)}",
  ]
}

resource "aws_route53_record" "opennms_sentinel_private" {
  count   = "${length(var.onms_sentinel_ip_addresses)}"
  zone_id = "${aws_route53_zone.private.zone_id}"
  name    = "${element(keys(var.onms_sentinel_ip_addresses), count.index)}.${aws_route53_zone.private.name}"
  type    = "A"
  ttl     = "${var.dns_ttl}"
  records = [
    "${element(values(var.onms_sentinel_ip_addresses), count.index)}",
  ]
}

output "sentinel" {
  value = "${join(",",aws_instance.opennms_sentinel.*.public_ip)}"
}
