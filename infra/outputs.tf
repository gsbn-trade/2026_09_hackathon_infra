output "public_ip" {
  value       = alicloud_eip_address.main.ip_address
  description = "Point your DNS A records (gateway.<domain>, build.<domain>) at this."
}

output "ssh_command" {
  value       = "ssh root@${alicloud_eip_address.main.ip_address}"
  description = "AliCloud's Ubuntu images default to root login via the key pair."
}

output "instance_id" {
  value = alicloud_instance.app.id
}
