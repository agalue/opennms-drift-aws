# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "cassandra" {
    count    = "${length(var.cassandra_ip_addresses)}"
    template = "${file("${path.module}/templates/cassandra.tpl")}"

    vars {
        node_id      = "${count.index + 1}"
        hostname     = "${element(keys(var.cassandra_ip_addresses), count.index)}"
        domainname   = "${var.dns_zone}"
        cluster_name = "${lookup(var.settings, "cluster_name")}"
        seed_name    = "${element(keys(var.cassandra_ip_addresses), 0)}"
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
        "${aws_security_group.cassandra.id}"
    ]

    root_block_device {
        volume_type = "gp2"
        volume_size = "${lookup(var.disk_space, "cassandra")}"
    }

    depends_on = [
        "aws_route53_record.cassandra"
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
        Name = "Terraform Cassandra Server ${count.index + 1}"
    }
}

resource "aws_route53_record" "cassandra" {
    count   = "${length(var.cassandra_ip_addresses)}"
    zone_id = "${aws_route53_zone.main.zone_id}"
    name    = "${element(keys(var.cassandra_ip_addresses), count.index)}.${var.dns_zone}"
    type    = "A"
    ttl     = "300"
    records = ["${element(values(var.cassandra_ip_addresses), count.index)}"]
}

output "cassandra" {
    value = "${join(",",aws_instance.cassandra.*.public_ip)}"
}
