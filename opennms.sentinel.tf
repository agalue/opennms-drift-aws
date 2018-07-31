# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "opennms_sentinel" {
  count    = "${length(var.onms_sentinel_ip_addresses)}"
  template = "${file("${path.module}/templates/opennms.sentinel.tpl")}"

  vars {
    hostname               = "${element(keys(var.onms_sentinel_ip_addresses), count.index)}"
    domainname             = "${var.dns_zone}"
    postgres_onms_url      = "jdbc:postgresql://${join(",", formatlist("%v:5432", keys(var.pg_ip_addresses)))}/opennms?targetServerType=master&amp;loadBalanceHosts=false"
    kafka_servers          = "${join(",",formatlist("%v:9092", keys(var.kafka_ip_addresses)))}"
    cassandra_seed         = "${element(keys(var.cassandra_ip_addresses), 0)}"
    elastic_url            = "${join(",",formatlist("http://%v:9200", keys(var.es_data_ip_addresses)))}"
    elastic_user           = "elastic"
    elastic_password       = "${lookup(var.settings, "elastic_password")}"
    elastic_index_strategy = "${lookup(var.settings, "elastic_flow_index_strategy")}"
    opennms_url            = "http://${element(keys(var.onms_ip_addresses),0)}:8980/opennms"
    sentinel_location      = "AWS"
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
  ]

  depends_on = [
    "aws_instance.opennms",
    "aws_route53_record.opennms_sentinel",
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
  name    = "${element(keys(var.onms_sentinel_ip_addresses), count.index)}.${var.dns_zone}"
  type    = "A"
  ttl     = "300"
  records = ["${element(values(var.onms_sentinel_ip_addresses), count.index)}"]
}

output "sentinel" {
  value = "${join(",",aws_instance.opennms_sentinel.*.public_ip)}"
}
