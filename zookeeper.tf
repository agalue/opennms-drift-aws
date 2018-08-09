# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "zookeeper" {
  count    = "${length(var.zookeeper_ip_addresses)}"
  template = "${file("${path.module}/templates/zookeeper.tpl")}"

  vars {
    node_id       = "${count.index + 1}"
    vpc_cidr      = "${var.vpc_cidr}"
    hostname      = "${element(keys(var.zookeeper_ip_addresses), count.index)}"
    domainname    = "${var.dns_zone}"
    total_servers = "${length(var.zookeeper_ip_addresses)}"
  }
}

resource "aws_instance" "zookeeper" {
  count         = "${length(var.zookeeper_ip_addresses)}"
  ami           = "${data.aws_ami.kafka.image_id}"
  instance_type = "${lookup(var.instance_types, "zookeeper")}"
  subnet_id     = "${aws_subnet.public.id}"
  key_name      = "${var.aws_key_name}"
  private_ip    = "${element(values(var.zookeeper_ip_addresses), count.index)}"
  user_data     = "${element(data.template_file.zookeeper.*.rendered, count.index)}"

  associate_public_ip_address = true

  vpc_security_group_ids = [
    "${aws_security_group.common.id}",
    "${aws_security_group.zookeeper.id}",
  ]

  depends_on = [
    "aws_route53_record.zookeeper_private",
  ]

  root_block_device {
    volume_type = "gp2"
    volume_size = "${lookup(var.disk_space, "zookeeper")}"
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
    Name = "Terraform Zookeeper Server ${count.index + 1}"
  }
}

resource "aws_route53_record" "zookeeper" {
  count   = "${length(var.zookeeper_ip_addresses)}"
  zone_id = "${aws_route53_zone.main.zone_id}"
  name    = "${element(keys(var.zookeeper_ip_addresses), count.index)}.${var.dns_zone}"
  type    = "A"
  ttl     = "${var.dns_ttl}"
  records = [
    "${element(aws_instance.zookeeper.*.public_ip, count.index)}",
  ]
}

resource "aws_route53_record" "zookeeper_private" {
  count   = "${length(var.zookeeper_ip_addresses)}"
  zone_id = "${aws_route53_zone.private.zone_id}"
  name    = "${element(keys(var.zookeeper_ip_addresses), count.index)}.${aws_route53_zone.private.name}"
  type    = "A"
  ttl     = "${var.dns_ttl}"
  records = [
    "${element(values(var.zookeeper_ip_addresses), count.index)}",
  ]
}

output "zookeeper" {
  value = "${join(",",aws_instance.zookeeper.*.public_ip)}"
}
