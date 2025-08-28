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

# Service discovery service for plugin-daemon
resource "aws_service_discovery_service" "plugin_daemon" {
  name = "plugin-daemon"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.dify.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_grace_period_seconds = 30

  tags = merge(
    var.default_tags,
    {
      Name = "service-discovery-service-${local.base_name}-plugin-daemon"
    }
  )
}

# Service discovery service for sandbox
resource "aws_service_discovery_service" "sandbox" {
  name = "sandbox"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.dify.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_grace_period_seconds = 30

  tags = merge(
    var.default_tags,
    {
      Name = "service-discovery-service-${local.base_name}-sandbox"
    }
  )
}

