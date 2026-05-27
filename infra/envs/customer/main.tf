############################################
# DBAOps-Agent — customer 환경
############################################
# 고객이 자기 PG/MySQL/Prometheus/MSK/S3 를 보유한 상태에서
# agent + UI + MCP Lambda + AgentCore 만 배포한다.
#
# 2-pass apply 흐름:
#   1) terraform apply -var=mcp_images_pushed=false -var=streamlit_image_pushed=false
#      → ECR repo / VPC(옵션) / IAM / ALB / CloudFront 만 생성
#   2) build_*.sh 로 이미지 push
#   3) terraform apply -var=mcp_images_pushed=true -var=streamlit_image_pushed=false
#      → 10 MCP Lambda 생성
#   4) python scripts/register_gateway_targets.py
#      → AgentCore Gateway / Runtime 등록 (terraform 외부)
#   5) terraform apply -var=mcp_images_pushed=true -var=streamlit_image_pushed=true \
#                       -var=agentcore_runtime_arn=<arn>
#      → Streamlit ECS service 생성

############################################
# VPC — 신규 또는 고객 VPC
############################################

module "network" {
  count  = var.create_vpc ? 1 : 0
  source = "../../modules/network"

  environment         = var.environment
  vpc_cidr            = var.new_vpc_cidr
  azs                 = var.new_vpc_azs
  enable_nat_instance = true
  enable_s3_endpoint  = true
}

locals {
  vpc_id             = var.create_vpc ? module.network[0].vpc_id             : var.customer_vpc_id
  private_subnet_ids = var.create_vpc ? module.network[0].private_subnet_ids : var.customer_private_subnet_ids
  public_subnet_ids  = var.create_vpc ? module.network[0].public_subnet_ids  : var.customer_public_subnet_ids
}

############################################
# IAM (MCP Lambda base role)
############################################

module "iam" {
  source      = "../../modules/iam"
  environment = var.environment
}

############################################
# AgentCore (ECR + Cognito + IAM roles)
############################################

module "agentcore" {
  source           = "../../modules/agentcore"
  environment      = var.environment
  region           = var.region
  bedrock_model_id = var.bedrock_model_id
}

############################################
# ECS cluster (Streamlit 용)
############################################

resource "aws_ecs_cluster" "this" {
  name = "dbaops-${var.environment}"
  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
    base              = 0
  }
}

############################################
# 10 MCP Lambda — env_vars 가 customer 변수로 주입
############################################

# 우리 PoC 4개 — 변환 로직이 handler 안에 있음

module "lambda_rds_pi" {
  source       = "../../modules/lambda_mcp_image"
  environment  = var.environment
  tool_name    = "rds-pi"
  image_pushed = var.mcp_images_pushed
  timeout      = 30
  memory_size  = 512
  vpc_id       = local.vpc_id
  subnet_ids   = local.private_subnet_ids
  role_arn     = module.iam.mcp_lambda_base_role_arn
  env_vars     = {}
}

module "lambda_msk_metrics" {
  source       = "../../modules/lambda_mcp_image"
  environment  = var.environment
  tool_name    = "msk-metrics"
  image_pushed = var.mcp_images_pushed
  timeout      = 30
  memory_size  = 512
  vpc_id       = local.vpc_id
  subnet_ids   = local.private_subnet_ids
  role_arn     = module.iam.mcp_lambda_base_role_arn

  env_vars = {
    KAFKA_CLUSTER_NAME  = var.customer_msk_cluster_name
    KAFKA_DEFAULT_TOPIC = var.customer_kafka_default_topic
    KAFKA_DEFAULT_CG    = var.customer_kafka_default_cg
  }
}

module "lambda_s3_log_fetch" {
  source       = "../../modules/lambda_mcp_image"
  environment  = var.environment
  tool_name    = "s3-log-fetch"
  image_pushed = var.mcp_images_pushed
  timeout      = 60
  memory_size  = 512
  vpc_id       = local.vpc_id
  subnet_ids   = local.private_subnet_ids
  role_arn     = module.iam.mcp_lambda_base_role_arn
  env_vars     = {}
}

module "lambda_aws_api" {
  source       = "../../modules/lambda_mcp_image"
  environment  = var.environment
  tool_name    = "aws-api"
  image_pushed = var.mcp_images_pushed
  timeout      = 60
  memory_size  = 512
  vpc_id       = local.vpc_id
  subnet_ids   = local.private_subnet_ids
  role_arn     = module.iam.mcp_lambda_base_role_arn
  env_vars     = {}
}

# awslabs MCP wrap 3개

module "lambda_awslabs_cloudwatch" {
  source       = "../../modules/lambda_mcp_image"
  environment  = var.environment
  tool_name    = "awslabs-cloudwatch"
  image_pushed = var.mcp_images_pushed
  timeout      = 60
  memory_size  = 1024
  vpc_id       = local.vpc_id
  subnet_ids   = local.private_subnet_ids
  role_arn     = module.iam.mcp_lambda_base_role_arn
  env_vars     = {}
}

module "lambda_awslabs_aws_doc" {
  source       = "../../modules/lambda_mcp_image"
  environment  = var.environment
  tool_name    = "awslabs-aws-doc"
  image_pushed = var.mcp_images_pushed
  timeout      = 30
  memory_size  = 512
  vpc_id       = local.vpc_id
  subnet_ids   = local.private_subnet_ids
  role_arn     = module.iam.mcp_lambda_base_role_arn
  env_vars     = {}
}

module "lambda_awslabs_aws_api" {
  source       = "../../modules/lambda_mcp_image"
  environment  = var.environment
  tool_name    = "awslabs-aws-api"
  image_pushed = var.mcp_images_pushed
  timeout      = 60
  memory_size  = 1024
  vpc_id       = local.vpc_id
  subnet_ids   = local.private_subnet_ids
  role_arn     = module.iam.mcp_lambda_base_role_arn
  env_vars     = {}
}

# community MCP wrap 3개

module "lambda_community_prometheus" {
  source       = "../../modules/lambda_mcp_image"
  environment  = var.environment
  tool_name    = "community-prometheus"
  image_pushed = var.mcp_images_pushed
  timeout      = 30
  memory_size  = 512
  vpc_id       = local.vpc_id
  subnet_ids   = local.private_subnet_ids
  role_arn     = module.iam.mcp_lambda_base_role_arn

  env_vars = {
    PROMETHEUS_URL = var.customer_prometheus_url
  }
}

module "lambda_community_postgres" {
  source       = "../../modules/lambda_mcp_image"
  environment  = var.environment
  tool_name    = "community-postgres"
  image_pushed = var.mcp_images_pushed
  timeout      = 60
  memory_size  = 1024
  vpc_id       = local.vpc_id
  subnet_ids   = local.private_subnet_ids
  role_arn     = module.iam.mcp_lambda_base_role_arn

  env_vars = {
    PG_HOST       = var.customer_pg_host
    PG_DBNAME     = var.customer_pg_dbname
    PG_SECRET_ARN = var.customer_pg_secret_arn
    PG_PORT       = "5432"
  }
}

module "lambda_community_mysql" {
  source       = "../../modules/lambda_mcp_image"
  environment  = var.environment
  tool_name    = "community-mysql"
  image_pushed = var.mcp_images_pushed
  timeout      = 60
  memory_size  = 1024
  vpc_id       = local.vpc_id
  subnet_ids   = local.private_subnet_ids
  role_arn     = module.iam.mcp_lambda_base_role_arn

  env_vars = {
    MYSQL_HOST       = var.customer_mysql_host
    MYSQL_DB         = var.customer_mysql_dbname
    MYSQL_SECRET_ARN = var.customer_mysql_secret_arn
    MYSQL_PORT       = "3306"
  }
}

############################################
# Streamlit UI (CloudFront → ALB → Fargate Spot)
############################################

module "streamlit" {
  source = "../../modules/ecs_streamlit"

  environment           = var.environment
  region                = var.region
  vpc_id                = local.vpc_id
  public_subnet_ids     = local.public_subnet_ids
  private_subnet_ids    = local.private_subnet_ids
  ecs_cluster_arn       = aws_ecs_cluster.this.arn
  ecs_cluster_name      = aws_ecs_cluster.this.name
  agentcore_runtime_arn = var.agentcore_runtime_arn
  image_pushed          = var.streamlit_image_pushed
  # gen_security_group_id 미지정 — generator 없음, 빈값 default
}
