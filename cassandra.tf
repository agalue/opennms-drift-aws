# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "cassandra" {
  count    = "${length(var.cassandra_ip_addresses)}"
  template = "${file("${path.module}/templates/cassandra.tpl")}"

  vars {
    node_id      = "${count.index + 1}"
    hostname     = "${element(keys(var.cassandra_ip_addresses), count.index)}"
    domainname   = "${aws_route53_zone.private.name}"
    cluster_name = "${lookup(var.settings, "cluster_name")}"
    seed_name    = "${element(aws_route53_record.cassandra_private.*.name, 0)}"
    datacenter   = "${lookup(var.settings, "cassandra_datacenter")}"
    rack         = "Rack${count.index + 1}"
  }
}

resource "aws_instance" "cassandra" {
  count         = "${length(var.cassandra_ip_addresses)}"
  ami           = "${data.aws_ami.cassandra.image_id}"
  instance_type = "${lookup(var.instance_types, "cassandra")}"
  subnet_id     = "${aws_subnet.public.id}"
  key_name      = "${var.aws_key_name}"
  private_ip    = "${element(values(var.cassandra_ip_addresses), count.index)}"
  user_data     = "${element(data.template_file.cassandra.*.rendered, count.index)}"

  associate_public_ip_address = true

  vpc_security_group_ids = [
    "${aws_security_group.common.id}",
    "${aws_security_group.cassandra.id}",
  ]

  depends_on = [
    "aws_route53_record.cassandra_private",
  ]

  connection {
    user        = "ubuntu"
    private_key = "${file("${var.aws_private_key}")}"
  }

  timeouts {
    create = "30m"
    delete = "15m"
  }

  tags {
    Name = "Terraform ScyllaDB Server ${count.index + 1}"
  }
}

resource "aws_ebs_volume" "cassandra" {
  count             = "${length(var.cassandra_ip_addresses)}"
  availability_zone = "${data.aws_availability_zones.available.names[0]}"
  size              = "${lookup(var.disk_space, "cassandra")}"
  type              = "gp2"

  tags {
    Name = "Terraform ScyllaDB Volume ${count.index + 1}"
  }
}

resource "aws_volume_attachment" "cassandra" {
  count       = "${length(var.cassandra_ip_addresses)}"
  device_name = "/dev/xvdb"
  volume_id   = "${element(aws_ebs_volume.cassandra.*.id, count.index)}"
  instance_id = "${element(aws_instance.cassandra.*.id, count.index)}"
}

resource "aws_route53_record" "cassandra" {
  count   = "${length(var.cassandra_ip_addresses)}"
  zone_id = "${aws_route53_zone.main.zone_id}"
  name    = "${element(keys(var.cassandra_ip_addresses), count.index)}.${aws_route53_zone.main.name}"
  type    = "A"
  ttl     = "${var.dns_ttl}"
  records = [
    "${element(aws_instance.cassandra.*.public_ip, count.index)}",
  ]
}

resource "aws_route53_record" "cassandra_private" {
  count   = "${length(var.cassandra_ip_addresses)}"
  zone_id = "${aws_route53_zone.private.zone_id}"
  name    = "${element(keys(var.cassandra_ip_addresses), count.index)}.${aws_route53_zone.private.name}"
  type    = "A"
  ttl     = "${var.dns_ttl}"
  records = [
    "${element(values(var.cassandra_ip_addresses), count.index)}",
  ]
}

output "cassandra" {
  value = "${join(",",aws_instance.cassandra.*.public_ip)}"
}
