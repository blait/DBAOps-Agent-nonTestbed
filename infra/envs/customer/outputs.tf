############################################
# Network
############################################

output "vpc_id"             { value = local.vpc_id }
output "private_subnet_ids" { value = local.private_subnet_ids }
output "public_subnet_ids"  { value = local.public_subnet_ids }

############################################
# AgentCore
############################################

output "ecr_repository_url"        { value = module.agentcore.ecr_repository_url }
output "cognito_user_pool_id"      { value = module.agentcore.cognito_user_pool_id }
output "cognito_app_client_id"     { value = module.agentcore.cognito_app_client_id }
output "agentcore_runtime_role_arn" { value = module.agentcore.runtime_role_arn }
output "agentcore_gateway_role_arn" { value = module.agentcore.gateway_role_arn }

############################################
# MCP Lambda ECR repos
############################################

output "mcp_repo_rds_pi"               { value = module.lambda_rds_pi.ecr_repository_url }
output "mcp_repo_msk_metrics"          { value = module.lambda_msk_metrics.ecr_repository_url }
output "mcp_repo_s3_log_fetch"         { value = module.lambda_s3_log_fetch.ecr_repository_url }
output "mcp_repo_aws_api"              { value = module.lambda_aws_api.ecr_repository_url }
output "mcp_repo_awslabs_cloudwatch"   { value = module.lambda_awslabs_cloudwatch.ecr_repository_url }
output "mcp_repo_awslabs_aws_doc"      { value = module.lambda_awslabs_aws_doc.ecr_repository_url }
output "mcp_repo_awslabs_aws_api"      { value = module.lambda_awslabs_aws_api.ecr_repository_url }
output "mcp_repo_community_prometheus" { value = module.lambda_community_prometheus.ecr_repository_url }
output "mcp_repo_community_postgres"   { value = module.lambda_community_postgres.ecr_repository_url }
output "mcp_repo_community_mysql"      { value = module.lambda_community_mysql.ecr_repository_url }

output "mcp_lambda_arns" {
  value = {
    "rds-pi"               = module.lambda_rds_pi.function_arn
    "msk-metrics"          = module.lambda_msk_metrics.function_arn
    "s3-log-fetch"         = module.lambda_s3_log_fetch.function_arn
    "aws-api"              = module.lambda_aws_api.function_arn
    "awslabs-cloudwatch"   = module.lambda_awslabs_cloudwatch.function_arn
    "awslabs-aws-doc"      = module.lambda_awslabs_aws_doc.function_arn
    "awslabs-aws-api"      = module.lambda_awslabs_aws_api.function_arn
    "community-prometheus" = module.lambda_community_prometheus.function_arn
    "community-postgres"   = module.lambda_community_postgres.function_arn
    "community-mysql"      = module.lambda_community_mysql.function_arn
  }
}

############################################
# Streamlit
############################################

output "streamlit_url"      { value = module.streamlit.cloudfront_url }
output "streamlit_alb_dns"  { value = module.streamlit.alb_dns_name }
output "streamlit_repo_url" { value = module.streamlit.streamlit_repo_url }

output "ecs_cluster_name" { value = aws_ecs_cluster.this.name }
