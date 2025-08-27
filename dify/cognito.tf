# ------------------------------------------------
# Cognito User Pool Configuration
# ------------------------------------------------

# Cognito User Pool
resource "aws_cognito_user_pool" "dify" {
  name = coalesce(var.user_pool_name, "${local.base_name}-user-pool")

  # Email configuration
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Sign-up configuration
  admin_create_user_config {
    allow_admin_create_user_only = !var.enable_cognito_signup
  }

  # User pool add-ons
  user_pool_add_ons {
    advanced_security_mode = "ENFORCED"
  }

  # Password policy
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  tags = merge(
    var.default_tags,
    {
      Name = "${local.base_name}-user-pool"
    }
  )
}

# Cognito User Pool Domain (use managed domain for now)
resource "aws_cognito_user_pool_domain" "dify" {
  domain       = "${local.base_name}-auth-${random_id.cognito_domain.hex}"
  user_pool_id = aws_cognito_user_pool.dify.id
}

# Random ID for unique domain name
resource "random_id" "cognito_domain" {
  byte_length = 4
}

# SAML Identity Provider
resource "aws_cognito_identity_provider" "saml" {
  user_pool_id  = aws_cognito_user_pool.dify.id
  provider_name = var.saml_idp_name
  provider_type = "SAML"

  provider_details = {
    MetadataURL = var.saml_metadata_url != null ? var.saml_metadata_url : null
    MetadataFile = var.saml_metadata_file != null ? file(var.saml_metadata_file) : null
  }

  attribute_mapping = {
    email = var.saml_email_attribute
  }

  depends_on = [
    aws_cognito_user_pool.dify
  ]
}

# User Pool Client
resource "aws_cognito_user_pool_client" "dify" {
  name         = "${local.base_name}-client"
  user_pool_id = aws_cognito_user_pool.dify.id

  # OAuth configuration
  callback_urls = [
    "https://${local.dify_fqdn}/oauth2/idpresponse"
  ]
  logout_urls = [
    "https://${local.dify_fqdn}/"
  ]

  allowed_oauth_flows = ["code"]
  allowed_oauth_scopes = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true

  supported_identity_providers = [
    aws_cognito_identity_provider.saml.provider_name
  ]

  # Token configuration
  id_token_validity      = 60   # minutes
  access_token_validity  = 60   # minutes  
  refresh_token_validity = 30   # days

  token_validity_units {
    id_token      = "minutes"
    access_token  = "minutes"
    refresh_token = "days"
  }

  # Generate client secret
  generate_secret = true

  depends_on = [
    aws_cognito_identity_provider.saml
  ]
}