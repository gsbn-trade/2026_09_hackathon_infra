# Written for OpenTofu (the `tofu` CLI) — a drop-in, MPL-licensed fork of
# Terraform, same HCL and provider ecosystem. `terraform` itself would also
# read this unmodified if you ever switch back.
terraform {
  required_version = ">= 1.6"
  required_providers {
    alicloud = {
      # Pinned to the full registry host: OpenTofu checks registry.opentofu.org
      # first and doesn't always fall back automatically, and aliyun/alicloud
      # is confirmed published on the Terraform registry, so this is the
      # unambiguous choice rather than hoping the short form resolves.
      source  = "registry.terraform.io/aliyun/alicloud"
      version = "~> 1.240"
    }
  }
}

# Credentials are NOT set here directly. Recommended: run `aliyun configure`
# once (see README) — it writes ~/.aliyun/config.json. The provider does NOT
# read that file automatically just because it exists; it needs to be told
# which profile to use, hence `profile = "default"` below (matches the
# profile name `aliyun configure` writes unless you pass --profile).
# If you used a different profile name, override with:
#   export ALIBABA_CLOUD_PROFILE="<your-profile-name>"
# (this env var takes precedence over the `profile` argument here.)
#
# The alternative, raw env vars, works too but puts the secret directly in
# your shell history:
#   export ALIBABA_CLOUD_ACCESS_KEY_ID="..."
#   export ALIBABA_CLOUD_ACCESS_KEY_SECRET="..."
#   export ALIBABA_CLOUD_REGION="cn-hongkong"
provider "alicloud" {
  region  = var.region
  profile = "default"
}
