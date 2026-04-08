locals {
  name_prefix = "${var.project}-${var.env}"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ─────────────────────────────────────────
# 起動テンプレート
# ─────────────────────────────────────────
resource "aws_launch_template" "analysis" {
  name          = "${local.name_prefix}-analysis"
  image_id      = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = var.instance_profile_name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.security_group_id]
    subnet_id                   = var.subnet_id
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.root_volume_size_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2 強制
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh.tpl", {
    workspace_bucket = var.workspace_bucket_name
    region           = var.region
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${local.name_prefix}-analysis-node"
      Project     = var.project
      Environment = var.env
      AutoStop    = "true"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name    = "${local.name_prefix}-analysis-root"
      Project = var.project
    }
  }
}
