# Configure aws provider

provider "aws" {
  region = var.region
  assume_role {
    role_arn = var.assume_role
  }
}

# VPC and subnet configuration

data "aws_availability_zones" "available_az" {}

resource "aws_vpc" "ecs_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "ecs_vpc"
  }
}

resource "aws_subnet" "ecs_subnets" {
  count             = length(data.aws_availability_zones.available_az.names)
  cidr_block        = cidrsubnet(aws_vpc.ecs_vpc.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available_az.names[count.index]
  vpc_id            = aws_vpc.ecs_vpc.id
  tags = {
    Name = "ecs_subnet"
  }
}

resource "aws_internet_gateway" "ecs_gw" {
  vpc_id = aws_vpc.ecs_vpc.id
}

resource "aws_route_table" "ecs_rt" {
  vpc_id = aws_vpc.ecs_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ecs_gw.id
  }

  tags = {
    Name = "ecs_rt"
  }
}

resource "aws_route_table_association" "ecs_rt_association" {
  count          = length(data.aws_availability_zones.available_az.names)
  subnet_id      = element(aws_subnet.ecs_subnets.*.id, count.index)
  route_table_id = aws_route_table.ecs_rt.id
}

# Security group configuration

resource "aws_security_group" "ecs_sg" {
  name        = "ecs_sg"
  vpc_id      = aws_vpc.ecs_vpc.id

  dynamic "ingress" {
    for_each = var.security_group_ingress
    content {
      from_port   = lookup(ingress.value, "from_port", null)
      protocol    = lookup(ingress.value, "protocol", null)
      to_port     = lookup(ingress.value, "to_port", null)
      cidr_blocks = lookup(ingress.value, "cidr_blocks", null)
    }
  }

  dynamic "egress" {
    for_each = var.security_group_egress
    content {
      from_port   = lookup(egress.value, "from_port", null)
      protocol    = lookup(egress.value, "protocol", null)
      to_port     = lookup(egress.value, "to_port", null)
      cidr_blocks = lookup(egress.value, "cidr_blocks", null)
    }
  }
  tags = {
    Name = "ecs_sg"
  }
}

#  Load Balancer Ressources

resource "aws_alb" "ecs_load_balancer" {
  name            = "ECSloadbalancer"
  security_groups = [aws_security_group.ecs_sg.id]
  subnets         = aws_subnet.ecs_subnets.*.id
  tags            = {
    Name = "ecs_lb"
  }
}

resource "aws_alb_target_group" "ecs_target_group" {
  name                  = "ECSTargetGroup"
  port                  = var.ecs_target_group_port
  protocol              = "HTTP"
  vpc_id                = aws_vpc.ecs_vpc.id

  health_check {
    healthy_threshold   = "5"
    unhealthy_threshold = "2"
    interval            = "30"
    matcher             = "200"
    path                = var.lb_hc_path
    port                = var.lb_port
    protocol            = "HTTP"
    timeout             = "5"
  }
  tags                  = {
    Name = "ecs_target_group"
  }
  depends_on            = [aws_alb.ecs_load_balancer]
}

resource "aws_alb_listener" "alb_listener" {
  load_balancer_arn  = aws_alb.ecs_load_balancer.arn
  port               = 80
  protocol           = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.ecs_target_group.arn
    type             = "forward"
  }
  depends_on         = [aws_alb.ecs_load_balancer]
}

# Autoscaling Group Resources

resource "aws_autoscaling_group" "ecs_autoscaling-group" {
  name_prefix          = "ecs_autoscaling"
  max_size             = "2"
  min_size             = "1"
  desired_capacity     = "1"
  vpc_zone_identifier  = aws_subnet.ecs_subnets.*.id
  launch_configuration = aws_launch_configuration.ecs_launch_configuration.name
  health_check_type    = "ELB"
}

# EC2 AMI id for ECS cluster

data "aws_ami" "ecs_optimized_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  owners = ["amazon"]
}


# Launch Configuration Resources

data "template_file" "ecs_cloud_config" {
  template            = file("ecs-config/cloud-config.sh.tpl")
  vars = {
    ecs_cluster       = var.ecs_cluster_name
  }
}

resource "aws_launch_configuration" "ecs_launch_configuration" {
  name                 = "ecs_launch_configuration"
  image_id             = data.aws_ami.ecs_optimized_ami.id
  instance_type        = "t2.xlarge"
  iam_instance_profile = aws_iam_instance_profile.instance_profile.id

  lifecycle {
    create_before_destroy = true
  }

  security_groups             = [aws_security_group.ecs_sg.id]
  associate_public_ip_address = "true"
  key_name                    = var.ecs_key_pair_name
  user_data                   = data.template_file.ecs_cloud_config.rendered
}

# Instance Role Resource

data "aws_iam_policy_document" "instance_policy" {
  statement {
    actions       = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance_role" {
  name               = "ecs_instance_role"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.instance_policy.json
}

resource "aws_iam_role_policy_attachment" "instance_role_attachment" {
  role       = aws_iam_role.instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "instance_profile" {
  name  = "ecs_instance_profile"
  path  = "/"
  role  = aws_iam_role.instance_role.id
}

# Service Role Resources

data "aws_iam_policy_document" "service_policy" {
  statement {
    actions       = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "service_role" {
  name               = "ecs_service_role"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.service_policy.json
}

resource "aws_iam_role_policy_attachment" "service-role-attachment" {
  role       = aws_iam_role.service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}

# Task Execution Role Resource

data "aws_iam_policy_document" "task_execution_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution_role" {
  name               = "ecs_task_execution_role"
  assume_role_policy = data.aws_iam_policy_document.task_execution_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Cluster Resource

resource "aws_ecs_cluster" "ecs_cluster" {
  name = var.ecs_cluster_name
  tags = {
    Name = "ecs_cluster"
  }
}

# ECS service creation

resource "aws_ecs_service" "ecs_service" {
  name            = "ecs_service"
  iam_role        = aws_iam_role.service_role.name
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.ecs_task_definition.family
  desired_count   = 1

  load_balancer {
    target_group_arn = aws_alb_target_group.ecs_target_group.arn
    container_port   = 80
    container_name   = "nginx"
  }
}

# ECS Task definition creation

data "template_file" "task_definition" {
  template = file("task-definition-template/task_definition.json.tpl")
  vars = {
    container_name       = "nginx"
    container_image      = "nginx"
    container_port       = "80"
    container_memory     = "1024"
    container_cpu        = "512"
    task_execution_role  = aws_iam_role.task_execution_role.arn
  }
}

resource "aws_ecs_task_definition" "ecs_task_definition" {
  family                = "ecs_task_definition"
  execution_role_arn    = aws_iam_role.task_execution_role.arn
  container_definitions = data.template_file.task_definition.rendered
  tags = {
      Name = "ecs_task_definition"
    }
}
