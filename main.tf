# 1. Local Cloud-Init seed files (NoCloud: user-data + network-config)
resource "local_file" "cloud_init_user_data" {
  content  = local.cloud_init_user_data
  filename = "${path.module}/user_data_${var.vm_name}.yaml"
}

resource "local_file" "cloud_init_network_config" {
  content  = local.cloud_init_network_config
  filename = "${path.module}/network_config_${var.vm_name}.yaml"
}

# 2. Deploy the Ubuntu VM on TrueNAS SCALE via the REST API (/api/v2.0/vm)
resource "null_resource" "truenas_vm_deploy" {
  depends_on = [
    local_file.cloud_init_user_data,
    local_file.cloud_init_network_config,
  ]

  triggers = {
    vm_name             = var.vm_name
    vm_ram              = var.vm_memory
    vm_vcpus            = var.vm_vcpus
    vm_disk_size        = var.vm_disk_size
    zfs_pool            = var.zfs_pool
    network_bridge      = var.network_bridge
    vm_mac              = local.vm_mac
    host                = var.truenas_host
    api_key             = var.truenas_api_key
    ubuntu_image_url    = local.ubuntu_image_url
    user_data_hash      = md5(local.cloud_init_user_data)
    network_config_hash = md5(local.cloud_init_network_config)
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/deploy_vm.sh"

    environment = {
      TRUENAS_HOST     = var.truenas_host
      TRUENAS_SCHEME   = var.truenas_scheme
      TRUENAS_API_KEY  = var.truenas_api_key
      VM_NAME          = var.vm_name
      VM_VCPUS         = var.vm_vcpus
      VM_CORES         = var.vm_cores
      VM_THREADS       = var.vm_threads
      VM_MEMORY        = var.vm_memory
      VM_DISK_SIZE     = var.vm_disk_size
      ZFS_POOL         = var.zfs_pool
      NETWORK_BRIDGE   = var.network_bridge
      VM_MAC           = local.vm_mac
      UBUNTU_IMAGE_URL = local.ubuntu_image_url
      SSH_PUBLIC_KEY   = local.ssh_key
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/scripts/destroy_vm.sh"

    environment = {
      TRUENAS_HOST    = self.triggers.host
      TRUENAS_SCHEME  = "http"
      TRUENAS_API_KEY = self.triggers.api_key
      VM_NAME         = self.triggers.vm_name
      ZFS_POOL        = self.triggers.zfs_pool
    }
  }
}
