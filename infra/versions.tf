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

# Credentials are NOT set here. Recommended: run `aliyun configure` once
# (see README) — it writes ~/.aliyun/config.json, which this provider reads
# automatically. The alternative, raw env vars, works too but puts the
# secret directly in your shell history:
#   export ALICLOUD_ACCESS_KEY="..."
#   export ALICLOUD_SECRET_KEY="..."
#   export ALICLOUD_REGION="cn-shanghai"
provider "alicloud" {
  region = var.region
}
