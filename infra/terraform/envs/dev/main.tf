terraform {
  required_version = ">= 1.8"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "etra-tf-state"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "etra-tf-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.env
      ManagedBy   = "Terraform"
    }
  }
}

# CloudFront WAF は us-east-1 固定
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.env
      ManagedBy   = "Terraform"
    }
  }
}

# ─────────────────────────────────────────
# VPC
# ─────────────────────────────────────────
module "vpc" {
  source = "../../modules/vpc"

  project             = var.project
  env                 = var.env
  region              = var.region
  vpc_cidr        = "10.0.0.0/16"
  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
}

# ─────────────────────────────────────────
# S3
# ─────────────────────────────────────────
module "s3" {
  source  = "../../modules/s3"
  project = var.project
  env     = var.env
}

# ─────────────────────────────────────────
# IAM
# ─────────────────────────────────────────
module "iam" {
  source = "../../modules/iam"

  project                = var.project
  env                    = var.env
  workspace_bucket_arn   = module.s3.workspace_bucket_arn
  notification_topic_arn = module.cloudwatch.alerts_topic_arn
}

# ─────────────────────────────────────────
# Cognito
# ─────────────────────────────────────────
module "cognito" {
  source = "../../modules/cognito"

  project               = var.project
  env                   = var.env
  callback_urls         = var.cognito_callback_urls
  logout_urls           = var.cognito_logout_urls
  allowed_email_domains = var.allowed_email_domains
}

# ─────────────────────────────────────────
# AWS HealthImaging
# ─────────────────────────────────────────
module "healthimaging" {
  source  = "../../modules/healthimaging"
  project = var.project
  env     = var.env
}

# ─────────────────────────────────────────
# EC2 起動テンプレート
# ─────────────────────────────────────────
module "ec2" {
  source = "../../modules/ec2"

  project               = var.project
  env                   = var.env
  region                = var.region
  instance_type         = var.ec2_instance_type
  instance_profile_name = module.iam.ec2_analysis_instance_profile
  security_group_id     = module.vpc.ec2_analysis_sg_id
  subnet_id             = module.vpc.private_subnet_ids[0]
  workspace_bucket_name = module.s3.workspace_bucket_name
}

# ─────────────────────────────────────────
# Lambda
# ─────────────────────────────────────────
module "lambda" {
  source = "../../modules/lambda"

  project    = var.project
  env        = var.env
  region     = var.region

  role_arns = {
    start_compute  = module.iam.lambda_start_compute_role_arn
    stop_compute   = module.iam.lambda_stop_compute_role_arn
    status_compute = module.iam.lambda_status_compute_role_arn
    workspace_api  = module.iam.lambda_workspace_api_role_arn
    notify_status  = module.iam.lambda_notify_status_role_arn
  }

  private_subnet_ids     = module.vpc.private_subnet_ids
  lambda_sg_id           = module.vpc.lambda_sg_id
  workspace_bucket_name  = module.s3.workspace_bucket_name
  notification_topic_arn = module.cloudwatch.alerts_topic_arn
}

# ─────────────────────────────────────────
# EventBridge（自動停止スケジュール）
# ─────────────────────────────────────────
module "eventbridge" {
  source = "../../modules/eventbridge"

  project                 = var.project
  env                     = var.env
  stop_compute_lambda_arn = module.lambda.function_arns["stop_compute"]
}

# ─────────────────────────────────────────
# CloudTrail
# ─────────────────────────────────────────
module "cloudtrail" {
  source = "../../modules/cloudtrail"

  project              = var.project
  env                  = var.env
  workspace_bucket_arn = module.s3.workspace_bucket_arn
}

# ─────────────────────────────────────────
# CloudWatch / Budgets
# ─────────────────────────────────────────
module "cloudwatch" {
  source = "../../modules/cloudwatch"

  project               = var.project
  env                   = var.env
  alert_emails          = var.alert_emails
  lambda_function_names = module.lambda.function_names
  monthly_budget_usd    = var.monthly_budget_usd
}

# ─────────────────────────────────────────
# CloudFront + WAF（OHIF Viewer 配信）
# ─────────────────────────────────────────
module "cloudfront" {
  source = "../../modules/cloudfront"

  providers = {
    aws.us_east_1 = aws.us_east_1
  }

  project                         = var.project
  env                             = var.env
  frontend_bucket_name            = module.s3.frontend_bucket_name
  frontend_bucket_arn             = module.s3.frontend_bucket_arn
  frontend_bucket_regional_domain = "${module.s3.frontend_bucket_name}.s3.${var.region}.amazonaws.com"
}
