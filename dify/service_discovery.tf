# ----------------------------------------------------------- #
# Service Discovery Configuration for Dify Services          #
# ----------------------------------------------------------- #

# Create a private DNS namespace for service discovery
resource "aws_service_discovery_private_dns_namespace" "dify" {
  name        = "dify.local"
  description = "Private DNS namespace for Dify service discovery"
  vpc         = var.vpc_id

  tags = merge(
    var.default_tags,
    {
      Name = "service-discovery-namespace-${local.base_name}"
    }
  )
}

# Service discovery services are no longer needed as we use Service Connect

