output "ecr_repo_urls" {
  value = {
    dify_api           = aws_ecr_repository.dify_api.repository_url
    dify_web           = aws_ecr_repository.dify_web.repository_url
    dify_sandbox       = aws_ecr_repository.dify_sandbox.repository_url
    dify_plugin_daemon = aws_ecr_repository.dify_plugin_daemon.repository_url
  }
}

# output efs id
output "efs_id" {
  value = aws_efs_file_system.this.id
}

# ElastiCache outputs
output "elasticache_endpoints" {
  value = {
    main_cache   = aws_elasticache_replication_group.this.primary_endpoint_address
    celery_cache = aws_elasticache_replication_group.this.primary_endpoint_address
  }
}

output "elasticache_secrets" {
  value = {
    celery_broker_url_secret_arn = aws_secretsmanager_secret.celery_broker_url_secret.arn
    valkey_default_password_secret_arn = aws_secretsmanager_secret.valkey_default_password_secret.arn
  }
}

# Note: VPC Endpoints outputs have been moved to example/outputs.tf
# since all VPC endpoints are now managed in the example directory
