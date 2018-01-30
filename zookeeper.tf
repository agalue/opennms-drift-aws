# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "zookeeper" {
    count    = "${length(var.zookeeper_ip_addresses)}"
    template = "${file("${path.module}/templates/zookeeper.tpl")}"

    vars {
        node_id           = "${count.index + 1}"
        vpc_cidr          = "${var.vpc_cidr}"
        hostname          = "${element(keys(var.zookeeper_ip_addresses), count.index)}"
        domainname        = "${var.dns_zone}"
        total_servers     = "${length(var.zookeeper_ip_addresses)}"
        zookeeper_version = "${lookup(var.versions, "zookeeper")}"
    }
}

resource "aws_instance" "zookeeper" {
    count         = "${length(var.zookeeper_ip_addresses)}"
    ami           = "${lookup(var.aws_amis, var.aws_region)}"
    instance_type = "${lookup(var.instance_types, "zookeeper")}"
    subnet_id     = "${aws_subnet.public.id}"
    key_name      = "${var.aws_key_name}"
    private_ip    = "${element(values(var.zookeeper_ip_addresses), count.index)}"
    user_data     = "${element(data.template_file.zookeeper.*.rendered, count.index)}"

    associate_public_ip_address = true

    vpc_security_group_ids = [
        "${aws_security_group.common.id}",
        "${aws_security_group.zookeeper.id}"
    ]

    connection {
        user        = "ec2-user"
        private_key = "${file("${var.aws_private_key}")}"
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
    ttl     = "300"
    records = ["${element(values(var.zookeeper_ip_addresses), count.index)}"]
}

output "zookeeper" {
    value = "${join(",",aws_instance.zookeeper.*.public_ip)}"
}
