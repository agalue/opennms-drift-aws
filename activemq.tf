# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "activemq" {
  count    = "${length(var.amq_ip_addresses)}"
  template = "${file("${path.module}/templates/activemq.tpl")}"

  vars {
    node_id     = "${count.index + 1}"
    hostname    = "${element(keys(var.amq_ip_addresses), count.index)}"
    domainname  = "${var.dns_zone}"
    amq_sibling = "${element(var.amq_siblings, count.index)}"
  }
}

resource "aws_instance" "activemq" {
  count         = "${length(var.amq_ip_addresses)}"
  ami           = "${data.aws_ami.activemq.image_id}"
  instance_type = "${lookup(var.instance_types, "activemq")}"
  subnet_id     = "${aws_subnet.public.id}"
  key_name      = "${var.aws_key_name}"
  private_ip    = "${element(values(var.amq_ip_addresses), count.index)}"
  user_data     = "${element(data.template_file.activemq.*.rendered, count.index)}"

  associate_public_ip_address = true

  vpc_security_group_ids = [
    "${aws_security_group.common.id}",
    "${aws_security_group.activemq.id}",
  ]

  root_block_device {
    volume_type = "gp2"
    volume_size = "${lookup(var.disk_space, "activemq")}"
  }

  depends_on = [
    "aws_route53_record.activemq",
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
    Name = "Terraform ActiveMQ Server ${count.index + 1}"
  }
}

resource "aws_route53_record" "activemq" {
  count   = "${length(var.amq_ip_addresses)}"
  zone_id = "${aws_route53_zone.main.zone_id}"
  name    = "${element(keys(var.amq_ip_addresses), count.index)}.${var.dns_zone}"
  type    = "A"
  ttl     = "300"
  records = ["${element(values(var.amq_ip_addresses), count.index)}"]
}

output "activemq" {
  value = "${join(",",aws_instance.activemq.*.public_ip)}"
}
