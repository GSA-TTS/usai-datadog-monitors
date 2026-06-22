# Per-tenant provider wiring + module instantiation.
#
# WHY THIS IS REPETITIVE: Terraform providers (and provider-bound data sources)
# cannot use for_each/count — each Datadog org needs its own statically-declared
# provider alias. So each tenant gets a fixed block: an aws provider alias (to
# reach that tenant's AWS account via its SSO profile), two Secrets Manager data
# sources (the DD api/app keys), a datadog provider alias authed with those
# keys, and one module call. Add/remove a tenant by adding/removing its block.
#
# ENABLED TENANTS = the 7 whose usai-<t>-shared-dd-* secrets are readable today
# (Environment=production tag applied 2026-06-10). The remaining ~16 tenants are
# blocked on the same tagging fix and are listed in tenants.pending.md.
#
# Keys are read from AWS Secrets Manager at plan time — no TF_VAR_* needed.
# Requires the matching AWS SSO profiles to be logged in (aws sso login).

# ---- dnfsb ------------------------------------------------------------------
provider "aws" {
  alias   = "dnfsb"
  region  = "us-east-1"
  profile = "dnfsb"
}

data "aws_secretsmanager_secret_version" "dnfsb_api" {
  provider  = aws.dnfsb
  secret_id = "usai-dnfsb-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "dnfsb_app" {
  provider  = aws.dnfsb
  secret_id = "usai-dnfsb-shared-dd-app-key"
}

provider "datadog" {
  alias    = "dnfsb"
  api_key  = data.aws_secretsmanager_secret_version.dnfsb_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.dnfsb_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

module "dnfsb" {
  source    = "./modules/model_backend_monitors"
  providers = { datadog = datadog.dnfsb }

  tenant               = "dnfsb"
  notification_channel = var.notification_channel
}

# ---- doj ------------------------------------------------------------------
provider "aws" {
  alias   = "doj"
  region  = "us-east-1"
  profile = "doj"
}

data "aws_secretsmanager_secret_version" "doj_api" {
  provider  = aws.doj
  secret_id = "usai-doj-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "doj_app" {
  provider  = aws.doj
  secret_id = "usai-doj-shared-dd-app-key"
}

provider "datadog" {
  alias    = "doj"
  api_key  = data.aws_secretsmanager_secret_version.doj_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.doj_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

module "doj" {
  source    = "./modules/model_backend_monitors"
  providers = { datadog = datadog.doj }

  tenant               = "doj"
  notification_channel = var.notification_channel
}

# ---- faa ------------------------------------------------------------------
provider "aws" {
  alias   = "faa"
  region  = "us-east-1"
  profile = "faa"
}

data "aws_secretsmanager_secret_version" "faa_api" {
  provider  = aws.faa
  secret_id = "usai-faa-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "faa_app" {
  provider  = aws.faa
  secret_id = "usai-faa-shared-dd-app-key"
}

provider "datadog" {
  alias    = "faa"
  api_key  = data.aws_secretsmanager_secret_version.faa_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.faa_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

module "faa" {
  source    = "./modules/model_backend_monitors"
  providers = { datadog = datadog.faa }

  tenant               = "faa"
  notification_channel = var.notification_channel
}

# ---- ftc ------------------------------------------------------------------
provider "aws" {
  alias   = "ftc"
  region  = "us-east-1"
  profile = "ftc"
}

data "aws_secretsmanager_secret_version" "ftc_api" {
  provider  = aws.ftc
  secret_id = "usai-ftc-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "ftc_app" {
  provider  = aws.ftc
  secret_id = "usai-ftc-shared-dd-app-key"
}

provider "datadog" {
  alias    = "ftc"
  api_key  = data.aws_secretsmanager_secret_version.ftc_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.ftc_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

module "ftc" {
  source    = "./modules/model_backend_monitors"
  providers = { datadog = datadog.ftc }

  tenant               = "ftc"
  notification_channel = var.notification_channel
}

# ---- nrc ------------------------------------------------------------------
provider "aws" {
  alias   = "nrc"
  region  = "us-east-1"
  profile = "nrc"
}

data "aws_secretsmanager_secret_version" "nrc_api" {
  provider  = aws.nrc
  secret_id = "usai-nrc-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "nrc_app" {
  provider  = aws.nrc
  secret_id = "usai-nrc-shared-dd-app-key"
}

provider "datadog" {
  alias    = "nrc"
  api_key  = data.aws_secretsmanager_secret_version.nrc_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.nrc_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

module "nrc" {
  source    = "./modules/model_backend_monitors"
  providers = { datadog = datadog.nrc }

  tenant               = "nrc"
  notification_channel = var.notification_channel
}

# ---- ntsb ------------------------------------------------------------------
provider "aws" {
  alias   = "ntsb"
  region  = "us-east-1"
  profile = "ntsb"
}

data "aws_secretsmanager_secret_version" "ntsb_api" {
  provider  = aws.ntsb
  secret_id = "usai-ntsb-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "ntsb_app" {
  provider  = aws.ntsb
  secret_id = "usai-ntsb-shared-dd-app-key"
}

provider "datadog" {
  alias    = "ntsb"
  api_key  = data.aws_secretsmanager_secret_version.ntsb_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.ntsb_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

module "ntsb" {
  source    = "./modules/model_backend_monitors"
  providers = { datadog = datadog.ntsb }

  tenant               = "ntsb"
  notification_channel = var.notification_channel
}

# ---- oge ------------------------------------------------------------------
provider "aws" {
  alias   = "oge"
  region  = "us-east-1"
  profile = "oge"
}

data "aws_secretsmanager_secret_version" "oge_api" {
  provider  = aws.oge
  secret_id = "usai-oge-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "oge_app" {
  provider  = aws.oge
  secret_id = "usai-oge-shared-dd-app-key"
}

provider "datadog" {
  alias    = "oge"
  api_key  = data.aws_secretsmanager_secret_version.oge_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.oge_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

module "oge" {
  source    = "./modules/model_backend_monitors"
  providers = { datadog = datadog.oge }

  tenant               = "oge"
  notification_channel = var.notification_channel
}

