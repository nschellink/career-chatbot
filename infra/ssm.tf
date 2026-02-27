# SSM parameters for secrets. App reads these at runtime via boto3.
resource "aws_ssm_parameter" "openai_key" {
  name        = local.ssm_openai_param
  description = "OpenAI API key for career chatbot"
  type        = "SecureString"
  value       = var.openai_api_key
  tags        = { App = var.app_name }
}

resource "aws_ssm_parameter" "pushover_token" {
  count       = var.pushover_token != "" ? 1 : 0
  name        = local.ssm_pushover_token
  description = "Pushover API token"
  type        = "SecureString"
  value       = var.pushover_token
  tags        = { App = var.app_name }
}

resource "aws_ssm_parameter" "pushover_user" {
  count       = var.pushover_user != "" ? 1 : 0
  name        = local.ssm_pushover_user
  description = "Pushover user key"
  type        = "SecureString"
  value       = var.pushover_user
  tags        = { App = var.app_name }
}
