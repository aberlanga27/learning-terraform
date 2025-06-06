data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["bitnami-tomcat-*-x86_64-hvm-ebs-nami"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["979382823631"] # Bitnami
}

module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "blog-vpc-dev"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  # private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  # enable_nat_gateway = true
  # enable_vpn_gateway = true

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}

# resource "aws_instance" "blog" {
#   ami           = data.aws_ami.app_ami.id
#   instance_type = var.instance_type
#   vpc_security_group_ids = [module.blog_security_group.security_group_id]

#   subnet_id = module.blog_vpc.public_subnets[0]

#   tags = {
#     Name = "HelloWorld"
#   }
# }

module "blog_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.0"

  vpc_id      = module.blog_vpc.vpc_id
  name        = "blog_sg"
  description = "Security group for the blog application"

  ingress_rules = ["http-80-tcp", "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules  = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}

module "blog_autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "8.3.0"

  name = "blog-asg"
  min_size = 1
  max_size = 2

  vpc_zone_identifier = module.blog_vpc.public_subnets
  security_groups = [module.blog_security_group.security_group_id]
  
  image_id = data.aws_ami.app_ami.id
  instance_type = var.instance_type
}

resource "aws_autoscaling_attachment" "blog_asg_alb" {
  autoscaling_group_name = module.blog_autoscaling.autoscaling_group_name
  lb_target_group_arn    = module.blog_load_balancer.target_groups["ex-instance"].arn
}

module "blog_load_balancer" {
  source = "terraform-aws-modules/alb/aws"

  name    = "blog-alb"
  vpc_id  = module.blog_vpc.vpc_id
  subnets = module.blog_vpc.public_subnets

  # Security Group
  security_groups = [module.blog_security_group.security_group_id]

  target_groups = {
    ex-instance = {
      name_prefix      = "blog-"
      protocol         = "HTTP"
      port             = 80
      target_type      = "instance"
      target_ids       = module.blog_autoscaling.autoscaling_group_name
    }
  }

  listeners = {
    ex-http = {
      port     = 80
      protocol = "HTTP"

      forward = {
        target_group_key = "ex-instance"
      }
    }
  }

  tags = {
    Environment = "dev"
  }
}