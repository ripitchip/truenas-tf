output "vm_name" {
  description = "Name of the virtual machine on TrueNAS"
  value       = var.vm_name
}

output "vm_ip" {
  description = "Configured IP address for the Ubuntu VM"
  value       = var.vm_ip
}

output "vm_mac" {
  description = "MAC address explicitly assigned to the VM's NIC (required - TrueNAS's own auto-generated MAC produced a non-functional NIC on this system)"
  value       = local.vm_mac
}

output "ssh_command" {
  description = "Command to connect to the VM over SSH"
  value       = "ssh ${var.ubuntu_username}@${var.vm_ip}"
}
