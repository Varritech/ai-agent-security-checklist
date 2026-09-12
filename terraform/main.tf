# AI Agent Isolation Infrastructure
# Creates a secure, isolated environment for running AI agents
# 
# Usage:
#   terraform init
#   terraform plan -var="agent_name=my-agent"
#   terraform apply

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "agent_name" {
  description = "Name identifier for this agent deployment"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the isolated VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# Isolated VPC - no route to production resources
resource "aws_vpc" "agent_isolated" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.agent_name}-isolated-vpc"
    Environment = var.environment
    Purpose     = "ai-agent-isolation"
  }
}

# Private subnets only - no public internet access by default
resource "aws_subnet" "agent_private" {
  vpc_id            = aws_vpc.agent_isolated.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "${var.agent_name}-private-subnet"
    Environment = var.environment
    Access      = "private-only"
  }
}

# Internet gateway (optional - disable for fully isolated agents)
resource "aws_internet_gateway" "agent_igw" {
  vpc_id = aws_vpc.agent_isolated.id

  tags = {
    Name        = "${var.agent_name}-igw"
    Environment = var.environment
    # Set to "disabled" to completely isolate
    Status      = "enabled"
  }
}

# Security group with restrictive defaults
resource "aws_security_group" "agent_sg" {
  name        = "${var.agent_name}-security-group"
  description = "Restrictive security group for AI agent execution"
  vpc_id      = aws_vpc.agent_isolated.id

  # No inbound access by default
  # Outbound limited to specific services

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS outbound only (for API calls)"
  }

  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "DNS resolution"
  }

  tags = {
    Name        = "${var.agent_name}-sg"
    Environment = var.environment
  }
}

# IAM role with minimal permissions
resource "aws_iam_role" "agent_role" {
  name = "${var.agent_name}-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.agent_name}-role"
    Environment = var.environment
  }
}

# Policy: Read-only S3 access to designated bucket only
resource "aws_iam_role_policy" "agent_s3_readonly" {
  name = "${var.agent_name}-s3-readonly"
  role = aws_iam_role.agent_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.agent_name}-input-data",
          "arn:aws:s3:::${var.agent_name}-input-data/*"
        ]
      }
    ]
  })
}

# Policy: CloudWatch Logs (required for monitoring)
resource "aws_iam_role_policy" "agent_logging" {
  name = "${var.agent_name}-logging"
  role = aws_iam_role.agent_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/aws/ecs/${var.agent_name}:*"
      }
    ]
  })
}

# ECS Cluster for agent container execution
resource "aws_ecs_cluster" "agent_cluster" {
  name = "${var.agent_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "${var.agent_name}-ecs-cluster"
    Environment = var.environment
  }
}

# CloudWatch Log Group for immutable logging
resource "aws_cloudwatch_log_group" "agent_logs" {
  name              = "/aws/ecs/${var.agent_name}"
  retention_in_days = 90  # Adjust based on compliance requirements
  
  tags = {
    Name        = "${var.agent_name}-logs"
    Environment = var.environment
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Outputs
output "vpc_id" {
  description = "ID of the isolated VPC"
  value       = aws_vpc.agent_isolated.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.agent_private.id
}

output "security_group_id" {
  description = "ID of the agent security group"
  value       = aws_security_group.agent_sg.id
}

output "iam_role_arn" {
  description = "ARN of the agent IAM role"
  value       = aws_iam_role.agent_role.arn
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.agent_cluster.name
}
