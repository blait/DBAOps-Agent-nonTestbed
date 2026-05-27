############################################
# 환경 / 리전
############################################

variable "environment" {
  type    = string
  default = "customer"
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

############################################
# Bedrock
############################################

variable "bedrock_model_id" {
  description = "AgentCore Runtime 이 호출하는 모델 ID. cross-region inference profile 권장."
  type        = string
  default     = "global.anthropic.claude-opus-4-7"
}

############################################
# 이미지 push 토글 — 2-pass apply 흐름
############################################

variable "mcp_images_pushed" {
  description = "MCP Lambda 이미지 push 후 true. 첫 apply 는 false (ECR repo 만)."
  type        = bool
  default     = false
}

variable "streamlit_image_pushed" {
  description = "Streamlit 이미지 push 후 true. 첫 apply 는 false (ALB/CF 만)."
  type        = bool
  default     = false
}

############################################
# VPC — 신규 vs 고객 VPC
############################################

variable "create_vpc" {
  description = "true 면 새 VPC 를 만듦. false 면 customer_* 변수의 기존 VPC 를 사용."
  type        = bool
  default     = false
}

# 신규 VPC 옵션 (create_vpc = true)
variable "new_vpc_cidr" {
  type    = string
  default = "10.50.0.0/16"
}

variable "new_vpc_azs" {
  type    = list(string)
  default = ["ap-northeast-2a", "ap-northeast-2c"]
}

# 기존 VPC 옵션 (create_vpc = false)
variable "customer_vpc_id" {
  type    = string
  default = ""
}

variable "customer_private_subnet_ids" {
  type    = list(string)
  default = []
}

variable "customer_public_subnet_ids" {
  type    = list(string)
  default = []
}

############################################
# 고객 PostgreSQL (Aurora 또는 일반 PG) — 필수
############################################

variable "customer_pg_host" {
  description = "PG endpoint hostname (포트 제외)"
  type        = string
}

variable "customer_pg_dbname" {
  type    = string
  default = "postgres"
}

variable "customer_pg_secret_arn" {
  description = "{username, password} JSON 을 담은 Secrets Manager ARN. RDS 가 master_user_secret 으로 자동 발급한 것을 사용 가능."
  type        = string
}

############################################
# 고객 MySQL — 옵션 (없으면 빈 값)
############################################

variable "customer_mysql_host" {
  type    = string
  default = ""
}

variable "customer_mysql_dbname" {
  type    = string
  default = "mysql"
}

variable "customer_mysql_secret_arn" {
  type    = string
  default = ""
}

############################################
# 고객 Prometheus URL (in-VPC HTTP) — 옵션
############################################

variable "customer_prometheus_url" {
  description = "예: http://10.40.1.10:9090. private subnet 안에서 접근 가능해야 함."
  type        = string
  default     = ""
}

############################################
# 고객 MSK / Kafka — 옵션
############################################

variable "customer_msk_cluster_name" {
  type    = string
  default = ""
}

variable "customer_kafka_default_topic" {
  type    = string
  default = ""
}

variable "customer_kafka_default_cg" {
  type    = string
  default = ""
}

############################################
# 고객 S3 log bucket — 옵션
############################################

variable "customer_log_bucket" {
  type    = string
  default = ""
}

variable "customer_log_bucket_arn" {
  type    = string
  default = ""
}

############################################
# Agent prompt 의 인프라 식별자
############################################

variable "customer_prom_instance_id" {
  type    = string
  default = ""
}

variable "customer_aurora_cluster_id" {
  type    = string
  default = ""
}

variable "customer_aurora_writer_id" {
  type    = string
  default = ""
}

variable "customer_aurora_reader_id" {
  type    = string
  default = ""
}

variable "customer_mysql_db_id" {
  type    = string
  default = ""
}

############################################
# AgentCore Runtime ARN — register_gateway_targets.py 가 만든 후 -var 로 주입
############################################

variable "agentcore_runtime_arn" {
  description = "register 스크립트 실행 후 ARN 을 -var 로 주입. 비어있으면 Streamlit task 가 경고만 표시."
  type        = string
  default     = ""
}
