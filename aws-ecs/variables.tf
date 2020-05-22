variable "region" {
  description = "Amazon region"
  type        = string
  default     = "eu-central-1"
}

variable "assume_role" {
  description = "Amazon profile to assume"
  type        = string
  default     = ""
}

variable "security_group_ingress" {
  description = "Ingress security group rules"
  type = list(object({
    from_port   = number
    protocol    = string
    to_port     = number
    self        = bool
    cidr_blocks = list(string)
  }))
  default = [{
      from_port   = 80 # Listner port number
      protocol    = "tcp"
      to_port     = 80
      self        = true
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      from_port   = 22 # SSH port number
      protocol    = "tcp"
      to_port     = 22
      self        = true
      cidr_blocks = ["0.0.0.0/0"]
  }]
}

variable "security_group_egress" {
  description = "Egress security group rules"
  type = list(object({
    from_port   = number
    protocol    = string
    to_port     = number
    self        = bool
    cidr_blocks = list(string)
  }))
  default = [{
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    self        = false
    cidr_blocks = ["0.0.0.0/0"]
  }]
}

variable "ecs_target_group_port" {
  description = "ECS target group port"
  type        = string
  default     = "80"
}

variable "lb_hc_path" {
  description = "Load balancer health check path"
  type        = string
  default     = "/"
}

variable "lb_port" {
  description = "Load balancer port"
  type        = string
  default     = "80"
}

variable "ecs_cluster_name" {
  description = "Name of ECS cluster"
  type        = string
  default     = "ecs-nginx"
}

variable "ecs_key_pair_name" {
  description = "EC2 key pair name"
  type        = string
  default     = ""
}
