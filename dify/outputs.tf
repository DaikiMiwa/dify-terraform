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
