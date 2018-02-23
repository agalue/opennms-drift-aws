# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "kafka" {
    count    = "${length(var.kafka_ip_addresses)}"
    template = "${file("${path.module}/templates/kafka.tpl")}"

    vars {
        node_id             = "${count.index + 1}"
        hostname            = "${element(keys(var.kafka_ip_addresses), count.index)}"
        domainname          = "${var.dns_zone}"
        zookeeper_connect   = "${join(",",formatlist("%v:2181", keys(var.zookeeper_ip_addresses)))}/kafka"
        num_partitions      = "${lookup(var.settings, "kafka_num_partitions")}"
        replication_factor  = "${lookup(var.settings, "kafka_replication_factor")}"
        min_insync_replicas = "${lookup(var.settings, "kafka_min_insync_replicas")}"
    }
}

resource "aws_instance" "kafka" {
    count         = "${length(var.kafka_ip_addresses)}"
    ami           = "${data.aws_ami.kafka.image_id}"
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

    root_block_device {
        volume_type = "gp2"
        volume_size = "${lookup(var.disk_space, "kafka")}"
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
