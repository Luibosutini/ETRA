locals {
  name_prefix = "${var.project}-${var.env}"
}

# ─────────────────────────────────────────
# VPC
# ─────────────────────────────────────────
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name_prefix}-vpc" }
}

# ─────────────────────────────────────────
# サブネット
# ─────────────────────────────────────────
resource "aws_subnet" "private" {
  for_each          = { for i, az in var.azs : az => var.private_subnets[i] }
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = { Name = "${local.name_prefix}-private-${each.key}" }
}

resource "aws_subnet" "public" {
  for_each                = { for i, az in var.azs : az => var.public_subnets[i] }
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = { Name = "${local.name_prefix}-public-${each.key}" }
}

# ─────────────────────────────────────────
# Internet Gateway（Public サブネット向け）
# ─────────────────────────────────────────
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name_prefix}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name_prefix}-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name_prefix}-private-rt" }
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# ─────────────────────────────────────────
# VPC Endpoints（S3 / HealthImaging / SSM）
# ─────────────────────────────────────────
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${local.name_prefix}-vpce-s3" }
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = { Name = "${local.name_prefix}-vpce-ssm" }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = { Name = "${local.name_prefix}-vpce-ssmmessages" }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = { Name = "${local.name_prefix}-vpce-ec2messages" }
}

resource "aws_vpc_endpoint" "lambda" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.lambda"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = { Name = "${local.name_prefix}-vpce-lambda" }
}

# EC2 API エンドポイント（start/stop/status_compute Lambda が必要）
resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = { Name = "${local.name_prefix}-vpce-ec2" }
}

# CloudWatch Logs エンドポイント（logs_api Lambda が必要）
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = { Name = "${local.name_prefix}-vpce-logs" }
}

# cognito-idp エンドポイントがサポートする AZ を動的に取得
data "aws_vpc_endpoint_service" "cognito_idp" {
  service = "cognito-idp"
}

# Cognito IDP エンドポイント（admin_api Lambda が必要）
# サービスがサポートする AZ のサブネットのみ指定（全 AZ 対応ではない）
resource "aws_vpc_endpoint" "cognito_idp" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.cognito-idp"
  vpc_endpoint_type = "Interface"
  subnet_ids = [
    for s in aws_subnet.private : s.id
    if contains(data.aws_vpc_endpoint_service.cognito_idp.availability_zones, s.availability_zone)
  ]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = { Name = "${local.name_prefix}-vpce-cognito-idp" }
}

# SNS エンドポイント（notify_status Lambda が必要）
resource "aws_vpc_endpoint" "sns" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.sns"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = { Name = "${local.name_prefix}-vpce-sns" }
}

# ─────────────────────────────────────────
# Security Groups
# ─────────────────────────────────────────
resource "aws_security_group" "vpce" {
  name        = "${local.name_prefix}-vpce-sg"
  description = "VPC Endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-vpce-sg" }
}

resource "aws_security_group" "ec2_analysis" {
  name        = "${local.name_prefix}-ec2-analysis-sg"
  description = "EC2 analysis node - SSM access only (no inbound rules required)"
  vpc_id      = aws_vpc.this.id

  # inbound ルールなし:
  #   DCV へのアクセスは SSM ポートフォワーディング経由で行う。
  #   固定 IP が不要になり、SG を開放しなくてよい。
  #
  #   接続コマンド:
  #     aws ssm start-session \
  #       --target <instance-id> \
  #       --document-name AWS-StartPortForwardingSession \
  #       --parameters '{"portNumber":["8443"],"localPortNumber":["8443"]}'
  #   → https://localhost:8443 で DCV に接続

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-ec2-analysis-sg" }
}

resource "aws_security_group" "lambda" {
  name        = "${local.name_prefix}-lambda-sg"
  description = "Lambda functions"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-lambda-sg" }
}
