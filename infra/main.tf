data "alicloud_zones" "available" {
  available_resource_creation = "Instance"
}

locals {
  zone_id = var.zone_id != "" ? var.zone_id : data.alicloud_zones.available.zones[0].id
}

resource "alicloud_vpc" "main" {
  vpc_name   = "${var.name_prefix}-vpc"
  cidr_block = "172.16.0.0/16"
}

resource "alicloud_vswitch" "main" {
  vswitch_name = "${var.name_prefix}-vsw"
  vpc_id       = alicloud_vpc.main.id
  cidr_block   = "172.16.0.0/24"
  zone_id      = local.zone_id
}

resource "alicloud_security_group" "main" {
  security_group_name = "${var.name_prefix}-sg"
  vpc_id               = alicloud_vpc.main.id
}

# SSH: only from the admin's own IP.
resource "alicloud_security_group_rule" "ssh" {
  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "22/22"
  priority          = 1
  security_group_id = alicloud_security_group.main.id
  cidr_ip           = var.admin_cidr
}

# SSH: also from a VPN's static egress IP, when set — a second fixed
# source alongside admin_cidr above, for when the admin's own ISP IP isn't
# the one actually reaching the instance (e.g. connecting over a VPN).
# Skipped entirely (count = 0) when vpn_cidr is left blank.
resource "alicloud_security_group_rule" "ssh_vpn" {
  count             = var.vpn_cidr != "" ? 1 : 0
  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "22/22"
  priority          = 1
  security_group_id = alicloud_security_group.main.id
  cidr_ip           = var.vpn_cidr
}

# Alternate SSH port (2222), same two sources as port 22 above. Added
# 2026-09-02 after real SSH connections to :22 consistently died right
# after the plaintext SSH banner exchange (TCP handshake fine, both sides
# exchange "SSH-2.0-..." banners, then an immediate RST) — the signature
# of on-path protocol-based blocking keyed on port 22 rather than payload,
# not a security-group or instance problem (sshd itself was confirmed
# healthy throughout via Cloud Assistant/RunCommand, which doesn't go
# through this same network path). `cloud-init.sh` adds `Port 2222`
# alongside `Port 22` in sshd_config for exactly this — see its own
# comment for the live-instance verification this was based on (RunCommand
# against the already-running VM, before this got written back into
# cloud-init.sh so a fresh `tofu apply` reproduces it too).
resource "alicloud_security_group_rule" "ssh_alt_port" {
  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "2222/2222"
  priority          = 1
  security_group_id = alicloud_security_group.main.id
  cidr_ip           = var.admin_cidr
}

resource "alicloud_security_group_rule" "ssh_alt_port_vpn" {
  count             = var.vpn_cidr != "" ? 1 : 0
  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "2222/2222"
  priority          = 1
  security_group_id = alicloud_security_group.main.id
  cidr_ip           = var.vpn_cidr
}

# HTTP: open, but only used to redirect to HTTPS (Caddy does this automatically).
resource "alicloud_security_group_rule" "http" {
  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "80/80"
  priority          = 1
  security_group_id = alicloud_security_group.main.id
  cidr_ip           = "0.0.0.0/0"
}

# HTTPS: open to participants.
resource "alicloud_security_group_rule" "https" {
  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "443/443"
  priority          = 1
  security_group_id = alicloud_security_group.main.id
  cidr_ip           = "0.0.0.0/0"
}

data "alicloud_images" "ubuntu" {
  name_regex  = "^ubuntu_22_04_x64"
  owners      = "system"
  most_recent = true
}

resource "alicloud_key_pair" "deploy" {
  key_pair_name = "${var.name_prefix}-key"
  public_key    = file(pathexpand(var.ssh_public_key_path))
}

resource "alicloud_instance" "app" {
  instance_name        = "${var.name_prefix}-app"
  instance_type        = var.instance_type
  image_id              = data.alicloud_images.ubuntu.images[0].id
  security_groups        = [alicloud_security_group.main.id]
  vswitch_id              = alicloud_vswitch.main.id
  key_name                = alicloud_key_pair.deploy.key_pair_name
  system_disk_category      = "cloud_essd"
  system_disk_size            = 100
  # No public bandwidth on the instance itself — the EIP below is the only public entry point.
  internet_max_bandwidth_out = 0
  user_data = base64encode(file("${path.module}/cloud-init.sh"))
}

resource "alicloud_eip_address" "main" {
  bandwidth             = var.eip_bandwidth
  internet_charge_type  = "PayByTraffic"
  isp                   = "BGP"
}

resource "alicloud_eip_association" "main" {
  allocation_id = alicloud_eip_address.main.id
  instance_id   = alicloud_instance.app.id
}
