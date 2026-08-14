variable "region" {
  description = "AliCloud region. cn-hongkong, not cn-shanghai: a mainland China region would require ICP filing (MIIT-registered domain + 3-month-minimum subscription + 1-3 week approval) before Alibaba Cloud will even resolve traffic to the domain, which doesn't fit a few-day hackathon. Hong Kong needs no ICP filing and is still low-latency from Shanghai (~30-50ms)."
  type        = string
  default     = "cn-hongkong"
}

variable "zone_id" {
  description = "Specific zone, e.g. cn-hongkong-b. Leave blank to auto-pick one with capacity."
  type        = string
  default     = ""
}

variable "name_prefix" {
  description = "Prefix for all resource names, so this is easy to find and to tear down."
  type        = string
  default     = "hackathon"
}

variable "admin_cidr" {
  description = "Your current public IP in CIDR form, e.g. 203.0.113.10/32. SSH is restricted to this."
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to the local SSH public key that will be allowed to log in as root."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "instance_type" {
  description = "ECS instance type. g9i.xlarge (4 vCPU / 16GB) is plenty for one LiteLLM + one bolt.diy instance behind Caddy — no model weights run on this box, every call is an API call out."
  type        = string
  default     = "ecs.g9i.xlarge"
}

variable "eip_bandwidth" {
  description = "EIP peak bandwidth in Mbps."
  type        = number
  default     = 20
}
