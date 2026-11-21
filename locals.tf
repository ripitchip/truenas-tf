locals {
  ssh_key = length(var.ssh_public_key) > 0 ? var.ssh_public_key : (
    fileexists("${path.module}/../../local-secrets/id_rsa_proxmox.pub") ? trimspace(file("${path.module}/../../local-secrets/id_rsa_proxmox.pub")) :
    fileexists(pathexpand("~/.ssh/id_rsa.pub")) ? trimspace(file(pathexpand("~/.ssh/id_rsa.pub"))) : ""
  )

  ubuntu_image_url = "https://cloud-images.ubuntu.com/${var.ubuntu_release}/current/${var.ubuntu_release}-server-cloudimg-amd64.img"

  # TrueNAS's own NIC auto-MAC-generation (vm/device with no "mac" field)
  # appears to produce a non-functional NIC on this system (no link, no ARP
  # replies ever, regardless of guest-side netplan config) - an explicit MAC
  # must always be passed to the API. Derived deterministically from vm_ip so
  # it's stable across redeploys.
  vm_mac = length(var.vm_mac) > 0 ? var.vm_mac : format(
    "52:54:00:10:00:%02x",
    tonumber(element(split(".", var.vm_ip), 3))
  )

  # NoCloud user-data: standard cloud-init, no image patching needed.
  cloud_init_user_data = <<-EOT
    #cloud-config
    hostname: ${var.vm_name}
    manage_etc_hosts: true
    ssh_pwauth: false
    package_update: true
    packages:
      - qemu-guest-agent
    users:
      - name: ${var.ubuntu_username}
        groups: sudo
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL
        ssh_authorized_keys:
          - ${local.ssh_key}
    runcmd:
      - systemctl enable --now qemu-guest-agent
  EOT

  # Matched by MAC: this is the combination that was actually confirmed
  # working (IP .21 + MAC match + explicit API mac). Name-based matching
  # ("e*") was tried in isolation and failed, so keep this until a clean
  # single-variable test says otherwise.
  cloud_init_network_config = <<-EOT
    network:
      version: 2
      ethernets:
        id0:
          match:
            macaddress: "${local.vm_mac}"
          set-name: eth0
          dhcp4: false
          addresses:
            - ${var.vm_ip}/24
          routes:
            - to: default
              via: ${var.vm_gateway}
          nameservers:
            addresses:
              - ${var.vm_dns}
  EOT
}
