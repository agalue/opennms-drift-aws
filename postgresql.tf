# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "postgresql" {
    template = "${file("${path.module}/templates/postgresql.tpl")}"

    vars {
        vpc_cidr           = "${var.vpc_cidr}"
        hostname           = "${element(keys(var.pg_ip_addresses),0)}"
        domainname         = "${var.dns_zone}"
        pg_repo_version    = "${lookup(var.versions, "postgresql_repo")}"
        pg_num_connections = "${lookup(var.settings, "postgresql_num_connections")}"
    }
}

resource "aws_instance" "postgresql" {
    ami           = "${lookup(var.aws_amis, var.aws_region)}"
    instance_type = "${lookup(var.instance_types, "postgresql")}"
    subnet_id     = "${aws_subnet.public.id}"
    key_name      = "${var.aws_key_name}"
    private_ip    = "${element(values(var.pg_ip_addresses),0)}"
    user_data     = "${data.template_file.postgresql.rendered}"

    associate_public_ip_address = true

    vpc_security_group_ids = [
        "${aws_security_group.common.id}",
        "${aws_security_group.postgresql.id}"
    ]

    root_block_device {
        volume_type = "gp2"
        volume_size = "${lookup(var.disk_space, "postgresql")}"
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
        Name = "Terraform PostgreSQL Server"
    }
}

resource "aws_route53_record" "postgresql" {
    zone_id = "${aws_route53_zone.main.zone_id}"
    name    = "${element(keys(var.pg_ip_addresses),0)}.${var.dns_zone}"
    type    = "A"
    ttl     = "300"
    records = ["${element(values(var.pg_ip_addresses),0)}"]
}

output "postgresql" {
    value = "${aws_instance.postgresql.public_ip}"
}
