terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.32.1"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "count_instances" {
  default     = 3
  description = "Count of instances"
}

data "aws_vpc" "vpc_default" {
  default = true
}

data "aws_subnets" "subnets_default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc_default.id]
  }
}

# data "aws_security_groups" "sg_default" {
#   filter {
#     name   = "vpc-id"
#     values = [data.aws_vpc.vpc_default.id]
#   }
# }

data "aws_key_pair" "aws_ec2" {
  key_name           = "aws-ec2"
  include_public_key = true
}

resource "aws_security_group" "allow_ssh_http_https" {
  name        = "allow_ssh_http_https"
  description = "Allow SSH, HTTP and HTTPS inbound traffic and all outbound traffic"
  vpc_id      = data.aws_vpc.vpc_default.id
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.allow_ssh_http_https.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4" {
  security_group_id = aws_security_group.allow_ssh_http_https.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "allow_https_ipv4" {
  security_group_id = aws_security_group.allow_ssh_http_https.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_ssh_http_https.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_lb" "alb" {
  name               = "alb-web-server"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_ssh_http_https.id]
  subnets            = data.aws_subnets.subnets_default.ids

  # enable_deletion_protection = true
  enable_deletion_protection = false

  tags = {
    Env = "Production"
  }
}

resource "aws_lb_target_group" "tg_web_server" {
  #  for_each           = var.alb_names
  name        = "tg-web-server"
  target_type = "instance"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.vpc_default.id

  health_check {
    healthy_threshold   = 3
    interval            = 20
    unhealthy_threshold = 2
    timeout             = 10
    path                = "/"
    port                = 80
  }
}

resource "aws_lb_target_group_attachment" "tg_attachment_web_server" {
  depends_on = [aws_instance.web]
  count      = var.count_instances

  target_group_arn = aws_lb_target_group.tg_web_server.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

resource "aws_lb_listener" "lb_listener_http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_web_server.arn
  }
}

data "aws_ami" "this" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
  filter {
    name   = "name"
    values = ["al2023-ami-2023*"]
  }
}


resource "aws_instance" "web" {
  ami           = data.aws_ami.this.id
  instance_type = "t4g.nano"

  tags = {
    Name = "Web Server ${count.index + 1}"
  }

  vpc_security_group_ids = [aws_security_group.allow_ssh_http_https.id]

  lifecycle {
    replace_triggered_by = [aws_security_group.allow_ssh_http_https]
  }

  depends_on = [aws_security_group.allow_ssh_http_https]

  key_name = data.aws_key_pair.aws_ec2.key_name

  count = var.count_instances
}

output "vpc_default_name" {
  value = data.aws_vpc.vpc_default.id
}

output "aws_instance_ips" {
  value = aws_instance.web.*.public_ip
}

output "aws_instance_dns" {
  value = aws_instance.web.*.public_dns
}

output "aws_subnets" {
  value = data.aws_subnets.subnets_default.ids
}

output "aws_security_group" {
  value = aws_security_group.allow_ssh_http_https.id
}

output "aws_lb_dns" {
  value = aws_lb.alb.dns_name
}
