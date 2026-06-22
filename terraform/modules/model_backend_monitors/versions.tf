# The module does not configure the datadog provider itself — it inherits the
# aliased provider passed by the caller via `providers = { datadog = ... }`.
# `configuration_aliases` declares that requirement.
terraform {
  required_version = ">= 1.5"

  required_providers {
    datadog = {
      source                = "DataDog/datadog"
      version               = "~> 3.46"
      configuration_aliases = [datadog]
    }
  }
}
