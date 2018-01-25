# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "kafka" {
    count    = "${length(var.kafka_ip_addresses)}"
    template = "${file("${path.module}/templates/kafka.tpl")}"

    vars {
        node_id             = "${count.index + 1}"
        vpc_cidr            = "${var.vpc_cidr}"
        hostname            = "${element(keys(var.kafka_ip_addresses), count.index)}"
        domainname          = "${var.dns_zone}"
        kafka_version       = "${lookup(var.versions, "kafka")}"
        scala_version       = "${lookup(var.versions, "scala")}"
        zookeeper_connect   = "${join(",",formatlist("%v:2181", keys(var.zookeeper_ip_addresses)))}/kafka"
        num_partitions      = 8
        replication_factor  = 2
        min_insync_replicas = 2
    }
}

resource "aws_instance" "kafka" {
    count         = "${length(var.kafka_ip_addresses)}"
    ami           = "${lookup(var.aws_amis, var.aws_region)}"
    instance_type = "${lookup(var.instance_types, "kafka")}"
    subnet_id     = "${aws_subnet.public.id}"
    key_name      = "${var.aws_key_name}"
    private_ip    = "${element(values(var.kafka_ip_addresses), count.index)}"
    user_data     = "${element(data.template_file.kafka.*.rendered, count.index)}"

    associate_public_ip_address = true

    vpc_security_group_ids = [
        "${aws_security_group.common.id}",
        "${aws_security_group.kafka.id}"
    ]

    depends_on = [
        "aws_instance.zookeeper"
    ]

    connection {
        user        = "ec2-user"
        private_key = "${file("${var.aws_private_key}")}"
    }

    tags {
        Name = "Terraform Kafka Server ${count.index + 1}"
    }
}

resource "aws_route53_record" "kafka" {
    count   = "${length(var.kafka_ip_addresses)}"
    zone_id = "${aws_route53_zone.main.zone_id}"
    name    = "${element(keys(var.kafka_ip_addresses), count.index)}.${var.dns_zone}"
    type    = "A"
    ttl     = "300"
    records = ["${element(values(var.kafka_ip_addresses), count.index)}"]
}

output "kafka" {
    value = "${join(",",aws_instance.kafka.*.public_ip)}"
}
