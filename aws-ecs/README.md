# AWS-ECS

This project aims to create an ECS cluster with container instances with Terraform.

In this cluster we need :
- Network : VPC, subnet, ig, routing table
- Security group
- Load Balancer
- Autoscaling Group
- Launch Configuration
- IAM roles : Instance, Service, Task Execution
- ECS Cluster
- ECS service
- ECS Task definition



**REQUIRED**
You need to configure the assume role if you use it, if not you must comment it from the aws provider section.
```
export TF_VAR_assume_role=''
export TF_VAR_ecs_key_pair=''
```

**Basic Usage**
```
terraform init
terraform plan
terraform apply
```
