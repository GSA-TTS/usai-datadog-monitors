# Per-tenant provider wiring + module instantiation.
#
# WHY THIS IS REPETITIVE: Terraform providers (and provider-bound data sources)
# cannot use for_each/count — each Datadog org needs its own statically-declared
# provider alias. So each tenant gets a fixed block: an aws provider alias (to
# reach that tenant's AWS account via its SSO profile), two Secrets Manager data
# sources (the DD api/app keys), a datadog provider alias authed with those
# keys, and one module call. Add/remove a tenant by adding/removing its block.
#
# ENABLED TENANTS = 25 (original 7 + 16 unblocked 2026-07-09 + nsf, eeoc 2026-07-22).
# aigov is the shared account: it does NOT get the per-tenant model_backend
# monitors module, but its Keycloak monitors + dashboard ARE managed here (see
# the aigov provider block below + monitors.tf / dashboard.tf). gsai blocked
# (KMS decrypt denied); disa has no SSO access.
#
# Keys are read from AWS Secrets Manager at plan time — no TF_VAR_* needed.
# Requires the matching AWS SSO profiles to be logged in (aws sso login).

# ---- aigov (shared account) ------------------------------------------------
# aigov hosts the shared Keycloak. Unlike the other tenants it gets NO
# model_backend_monitors module — only the Keycloak log alerts (monitors.tf)
# and the Keycloak dashboard (dashboard.tf), which reference datadog.aigov.
provider "aws" {
  alias   = "aigov"
  region  = "us-east-1"
  profile = "aigov"
}

data "aws_secretsmanager_secret_version" "aigov_api" {
  provider  = aws.aigov
  secret_id = "aigov-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "aigov_app" {
  provider  = aws.aigov
  secret_id = "aigov-shared-dd-app-key"
}

provider "datadog" {
  alias    = "aigov"
  api_key  = data.aws_secretsmanager_secret_version.aigov_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.aigov_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

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
  # Edge synthetics ON: ftc is verified reachable from the Datadog
  # `aws:us-gov-west-1` location (2026-08-18). See the per-tenant reachability
  # table in cert_monitors.tf — 8 sibling tenants time out from that location and
  # are deliberately left off.
  enable_edge_synthetics = true
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



# ---- doc -------------------------------------------------------------------
provider "aws" {
  alias   = "doc"
  region  = "us-east-1"
  profile = "doc"
}

data "aws_secretsmanager_secret_version" "doc_api" {
  provider  = aws.doc
  secret_id = "usai-doc-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "doc_app" {
  provider  = aws.doc
  secret_id = "usai-doc-shared-dd-app-key"
}

provider "datadog" {
  alias    = "doc"
  api_key  = data.aws_secretsmanager_secret_version.doc_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.doc_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

module "doc" {
  source    = "./modules/model_backend_monitors"
  providers = { datadog = datadog.doc }

  tenant               = "doc"
  notification_channel = var.notification_channel
  # Edge synthetics ON: doc is verified reachable from the Datadog
  # `aws:us-gov-west-1` location (2026-08-18). See the per-tenant reachability
  # table in cert_monitors.tf — 8 sibling tenants time out from that location and
  # are deliberately left off.
  enable_edge_synthetics = true
}

# ---- doi -------------------------------------------------------------------
provider "aws" {
  alias   = "doi"
  region  = "us-east-1"
  profile = "doi"
}

data "aws_secretsmanager_secret_version" "doi_api" {
  provider  = aws.doi
  secret_id = "usai-doi-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "doi_app" {
  provider  = aws.doi
  secret_id = "usai-doi-shared-dd-app-key"
}

provider "datadog" {
  alias    = "doi"
  api_key  = data.aws_secretsmanager_secret_version.doi_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.doi_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

module "doi" {
  source    = "./modules/model_backend_monitors"
  providers = { datadog = datadog.doi }

  tenant               = "doi"
  notification_channel = var.notification_channel
  # Edge synthetics ON: doi is verified reachable from the Datadog
  # `aws:us-gov-west-1` location (2026-08-18). See the per-tenant reachability
  # table in cert_monitors.tf — 8 sibling tenants time out from that location and
  # are deliberately left off.
  enable_edge_synthetics = true
}

# ---- dot -------------------------------------------------------------------
provider "aws" {
  alias   = "dot"
  region  = "us-east-1"
  profile = "dot"
}

data "aws_secretsmanager_secret_version" "dot_api" {
  provider  = aws.dot
  secret_id = "usai-dot-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "dot_app" {
  provider  = aws.dot
  secret_id = "usai-dot-shared-dd-app-key"
}

provider "datadog" {
  alias    = "dot"
  api_key  = data.aws_secretsmanager_secret_version.dot_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.dot_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

module "dot" {
  source    = "./modules/model_backend_monitors"
  providers = { datadog = datadog.dot }

  tenant               = "dot"
  notification_channel = var.notification_channel
  # Edge synthetics ON: dot is verified reachable from the Datadog
  # `aws:us-gov-west-1` location (2026-08-18). See the per-tenant reachability
  # table in cert_monitors.tf — 8 sibling tenants time out from that location and
  # are deliberately left off.
  enable_edge_synthetics = true
}

# ---- ed --------------------------------------------------------------------
provider "aws" {
  alias   = "ed"
  region  = "us-east-1"
  profile = "ed"
}

data "aws_secretsmanager_secret_version" "ed_api" {
  provider  = aws.ed
  secret_id = "usai-ed-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "ed_app" {
  provider  = aws.ed
  secret_id = "usai-ed-shared-dd-app-key"
}

provider "datadog" {
  alias    = "ed"
  api_key  = data.aws_secretsmanager_secret_version.ed_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.ed_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

module "ed" {
  source    = "./modules/model_backend_monitors"
  providers = { datadog = datadog.ed }

  tenant               = "ed"
  notification_channel = var.notification_channel
  # Edge synthetics ON: ed is verified reachable from the Datadog
  # `aws:us-gov-west-1` location (2026-08-18). See the per-tenant reachability
  # table in cert_monitors.tf — 8 sibling tenants time out from that location and
  # are deliberately left off.
  enable_edge_synthetics = true
}

# ---- fhfa ------------------------------------------------------------------
provider "aws" {
  alias   = "fhfa"
  region  = "us-east-1"
  profile = "fhfa"
}

data "aws_secretsmanager_secret_version" "fhfa_api" {
  provider  = aws.fhfa
  secret_id = "usai-fhfa-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "fhfa_app" {
  provider  = aws.fhfa
  secret_id = "usai-fhfa-shared-dd-app-key"
}

provider "datadog" {
  alias    = "fhfa"
  api_key  = data.aws_secretsmanager_secret_version.fhfa_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.fhfa_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

module "fhfa" {
  source    = "./modules/model_backend_monitors"
  providers = { datadog = datadog.fhfa }

  tenant               = "fhfa"
  notification_channel = var.notification_channel
  # Edge synthetics ON: fhfa is verified reachable from the Datadog
  # `aws:us-gov-west-1` location (2026-08-18). See the per-tenant reachability
  # table in cert_monitors.tf — 8 sibling tenants time out from that location and
  # are deliberately left off.
  enable_edge_synthetics = true
}

# ---- gsa -------------------------------------------------------------------
provider "aws" {
  alias   = "gsa"
  region  = "us-east-1"
  profile = "gsa"
}

data "aws_secretsmanager_secret_version" "gsa_api" {
  provider  = aws.gsa
  secret_id = "usai-gsa-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "gsa_app" {
  provider  = aws.gsa
  secret_id = "usai-gsa-shared-dd-app-key"
}

provider "datadog" {
  alias    = "gsa"
  api_key  = data.aws_secretsmanager_secret_version.gsa_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.gsa_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

module "gsa" {
  source    = "./modules/model_backend_monitors"
  providers = { datadog = datadog.gsa }

  tenant               = "gsa"
  notification_channel = var.notification_channel
  # Edge synthetics ON: gsa is verified reachable from the Datadog
  # `aws:us-gov-west-1` location (2026-08-18). See the per-tenant reachability
  # table in cert_monitors.tf — 8 sibling tenants time out from that location and
  # are deliberately left off.
  enable_edge_synthetics = true
}



# ---- hud -------------------------------------------------------------------
provider "aws" {
  alias   = "hud"
  region  = "us-east-1"
  profile = "hud"
}

data "aws_secretsmanager_secret_version" "hud_api" {
  provider  = aws.hud
  secret_id = "usai-hud-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "hud_app" {
  provider  = aws.hud
  secret_id = "usai-hud-shared-dd-app-key"
}

provider "datadog" {
  alias    = "hud"
  api_key  = data.aws_secretsmanager_secret_version.hud_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.hud_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

module "hud" {
  source    = "./modules/model_backend_monitors"
  providers = { datadog = datadog.hud }

  tenant               = "hud"
  notification_channel = var.notification_channel
  # Edge synthetics ON: hud is verified reachable from the Datadog
  # `aws:us-gov-west-1` location (2026-08-18). See the per-tenant reachability
  # table in cert_monitors.tf — 8 sibling tenants time out from that location and
  # are deliberately left off.
  enable_edge_synthetics = true
}

# ---- ncua ------------------------------------------------------------------
provider "aws" {
  alias   = "ncua"
  region  = "us-east-1"
  profile = "ncua"
}

data "aws_secretsmanager_secret_version" "ncua_api" {
  provider  = aws.ncua
  secret_id = "usai-ncua-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "ncua_app" {
  provider  = aws.ncua
  secret_id = "usai-ncua-shared-dd-app-key"
}

provider "datadog" {
  alias    = "ncua"
  api_key  = data.aws_secretsmanager_secret_version.ncua_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.ncua_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

module "ncua" {
  source    = "./modules/model_backend_monitors"
  providers = { datadog = datadog.ncua }

  tenant               = "ncua"
  notification_channel = var.notification_channel
  # Edge synthetics ON: ncua is verified reachable from the Datadog
  # `aws:us-gov-west-1` location (2026-08-18). See the per-tenant reachability
  # table in cert_monitors.tf — 8 sibling tenants time out from that location and
  # are deliberately left off.
  enable_edge_synthetics = true
}

# ---- nlrb ------------------------------------------------------------------
# Restored from the existing shared Terraform state, which already tracks the
# NLRB module resources under this provider alias. Keep the conventional tenant
# wiring so Terraform can refresh and manage those objects rather than treating
# them as provider-orphaned resources.
provider "aws" {
  alias   = "nlrb"
  region  = "us-east-1"
  profile = "nlrb"
}

data "aws_secretsmanager_secret_version" "nlrb_api" {
  provider  = aws.nlrb
  secret_id = "usai-nlrb-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "nlrb_app" {
  provider  = aws.nlrb
  secret_id = "usai-nlrb-shared-dd-app-key"
}

provider "datadog" {
  alias    = "nlrb"
  api_key  = data.aws_secretsmanager_secret_version.nlrb_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.nlrb_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

module "nlrb" {
  source    = "./modules/model_backend_monitors"
  providers = { datadog = datadog.nlrb }

  tenant               = "nlrb"
  notification_channel = var.notification_channel
  # Edge synthetics ON: testing reachability from aws:us-gov-west-1
  # for issue 1530 (API health check deployment). If blocked by WAF,
  # will be moved to WAF-unreachable list and this flag will be removed.
  enable_edge_synthetics = true
}

# ---- pc --------------------------------------------------------------------
provider "aws" {
  alias   = "pc"
  region  = "us-east-1"
  profile = "pc"
}

data "aws_secretsmanager_secret_version" "pc_api" {
  provider  = aws.pc
  secret_id = "usai-pc-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "pc_app" {
  provider  = aws.pc
  secret_id = "usai-pc-shared-dd-app-key"
}

provider "datadog" {
  alias    = "pc"
  api_key  = data.aws_secretsmanager_secret_version.pc_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.pc_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

module "pc" {
  source    = "./modules/model_backend_monitors"
  providers = { datadog = datadog.pc }

  tenant               = "pc"
  notification_channel = var.notification_channel
  # Edge synthetics ON: pc is verified reachable from the Datadog
  # `aws:us-gov-west-1` location (2026-08-18). See the per-tenant reachability
  # table in cert_monitors.tf — 8 sibling tenants time out from that location and
  # are deliberately left off.
  enable_edge_synthetics = true
}

# ---- sss -------------------------------------------------------------------
provider "aws" {
  alias   = "sss"
  region  = "us-east-1"
  profile = "sss"
}

data "aws_secretsmanager_secret_version" "sss_api" {
  provider  = aws.sss
  secret_id = "usai-sss-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "sss_app" {
  provider  = aws.sss
  secret_id = "usai-sss-shared-dd-app-key"
}

provider "datadog" {
  alias    = "sss"
  api_key  = data.aws_secretsmanager_secret_version.sss_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.sss_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

module "sss" {
  source    = "./modules/model_backend_monitors"
  providers = { datadog = datadog.sss }

  tenant               = "sss"
  notification_channel = var.notification_channel
  # Edge synthetics ON: sss is verified reachable from the Datadog
  # `aws:us-gov-west-1` location (2026-08-18). See the per-tenant reachability
  # table in cert_monitors.tf — 8 sibling tenants time out from that location and
  # are deliberately left off.
  enable_edge_synthetics = true
}

# ---- stateoig --------------------------------------------------------------
provider "aws" {
  alias   = "stateoig"
  region  = "us-east-1"
  profile = "stateoig"
}

data "aws_secretsmanager_secret_version" "stateoig_api" {
  provider  = aws.stateoig
  secret_id = "usai-stateoig-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "stateoig_app" {
  provider  = aws.stateoig
  secret_id = "usai-stateoig-shared-dd-app-key"
}

provider "datadog" {
  alias    = "stateoig"
  api_key  = data.aws_secretsmanager_secret_version.stateoig_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.stateoig_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

module "stateoig" {
  source    = "./modules/model_backend_monitors"
  providers = { datadog = datadog.stateoig }

  tenant               = "stateoig"
  notification_channel = var.notification_channel
  # Edge synthetics ON: stateoig is verified reachable from the Datadog
  # `aws:us-gov-west-1` location (2026-08-18). See the per-tenant reachability
  # table in cert_monitors.tf — 8 sibling tenants time out from that location and
  # are deliberately left off.
  enable_edge_synthetics = true
}

# ---- usda ------------------------------------------------------------------
provider "aws" {
  alias   = "usda"
  region  = "us-east-1"
  profile = "usda"
}

data "aws_secretsmanager_secret_version" "usda_api" {
  provider  = aws.usda
  secret_id = "usai-usda-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "usda_app" {
  provider  = aws.usda
  secret_id = "usai-usda-shared-dd-app-key"
}

provider "datadog" {
  alias    = "usda"
  api_key  = data.aws_secretsmanager_secret_version.usda_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.usda_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

module "usda" {
  source    = "./modules/model_backend_monitors"
  providers = { datadog = datadog.usda }

  tenant               = "usda"
  notification_channel = var.notification_channel
  # Edge synthetics ON: usda is verified reachable from the Datadog
  # `aws:us-gov-west-1` location (2026-08-18). See the per-tenant reachability
  # table in cert_monitors.tf — 8 sibling tenants time out from that location and
  # are deliberately left off.
  enable_edge_synthetics = true
}

# ---- nsf --------------------------------------------------------------------
# Sub-account under aigov (like doli): SSO profile is aigov-nsf, but the DD
# secrets keep the standard usai- prefix (unlike doli's bare names).
provider "aws" {
  alias   = "nsf"
  region  = "us-east-1"
  profile = "nsf"
}

data "aws_secretsmanager_secret_version" "nsf_api" {
  provider  = aws.nsf
  secret_id = "usai-nsf-shared-dd-api-key"
}

data "aws_secretsmanager_secret_version" "nsf_app" {
  provider  = aws.nsf
  secret_id = "usai-nsf-shared-dd-app-key"
}

provider "datadog" {
  alias    = "nsf"
  api_key  = data.aws_secretsmanager_secret_version.nsf_api.secret_string
  app_key  = data.aws_secretsmanager_secret_version.nsf_app.secret_string
  api_url  = "https://api.ddog-gov.com/"
  validate = true
}

module "nsf" {
  source    = "./modules/model_backend_monitors"
  providers = { datadog = datadog.nsf }

  tenant               = "nsf"
  notification_channel = var.notification_channel
}


