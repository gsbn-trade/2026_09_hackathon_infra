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
