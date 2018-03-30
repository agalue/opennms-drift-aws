# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "postgresql" {
  count    = "${length(var.pg_ip_addresses)}"
  template = "${file("${path.module}/templates/postgresql.tpl")}"

  vars {
    node_id            = "${count.index + 1}"
    vpc_cidr           = "${var.vpc_cidr}"
    hostname           = "${element(keys(var.pg_ip_addresses), count.index)}"
    domainname         = "${var.dns_zone}"
    pg_max_connections = "${lookup(var.settings, "postgresql_max_connections")}"
    pg_version_family  = "${lookup(var.settings, "postgresql_version_family")}"
    pg_role            = "${element(var.pg_roles, count.index)}"
    pg_rep_slots       = "${length(var.pg_ip_addresses)+1}"
    pg_master_server   = "${element(keys(var.pg_ip_addresses), 0)}"
  }
}

resource "aws_instance" "postgresql" {
  count         = "${length(var.pg_ip_addresses)}"
  ami           = "${data.aws_ami.postgresql.image_id}"
  instance_type = "${lookup(var.instance_types, "postgresql")}"
  subnet_id     = "${aws_subnet.public.id}"
  key_name      = "${var.aws_key_name}"
  private_ip    = "${element(values(var.pg_ip_addresses), count.index)}"
  user_data     = "${element(data.template_file.postgresql.*.rendered, count.index)}"

  associate_public_ip_address = true

  vpc_security_group_ids = [
    "${aws_security_group.common.id}",
    "${aws_security_group.postgresql.id}",
  ]

  root_block_device {
    volume_type = "gp2"
    volume_size = "${lookup(var.disk_space, "postgresql")}"
  }

  depends_on = [
    "aws_route53_record.postgresql",
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
    Name = "Terraform PostgreSQL Server ${count.index + 1}"
  }
}

resource "aws_route53_record" "postgresql" {
  count   = "${length(var.pg_ip_addresses)}"
  zone_id = "${aws_route53_zone.main.zone_id}"
  name    = "${element(keys(var.pg_ip_addresses),count.index)}.${var.dns_zone}"
  type    = "A"
  ttl     = "300"
  records = ["${element(values(var.pg_ip_addresses),count.index)}"]
}

output "postgresql" {
  value = "${join(",",aws_instance.postgresql.*.public_ip)}"
}
