variable "truenas_host" {
  description = "IP address or hostname of the TrueNAS SCALE instance"
  type        = string
  default     = "10.0.60.10"
}

variable "truenas_scheme" {
  description = "Protocol scheme for TrueNAS API (http or https)"
  type        = string
  default     = "http"
}

variable "truenas_api_key" {
  description = "API Key generated on TrueNAS (System Settings -> API Keys)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vm_name" {
  description = "Name of the Ubuntu VM (TrueNAS requires alphanumeric only)"
  type        = string
  default     = "ctrl00"
}

variable "vm_vcpus" {
  description = "Number of virtual CPUs allocated to the VM"
  type        = number
  default     = 4
}

variable "vm_cores" {
  description = "Number of cores per vCPU socket"
  type        = number
  default     = 1
}

variable "vm_threads" {
  description = "Number of threads per core"
  type        = number
  default     = 1
}

variable "vm_memory" {
  description = "RAM memory allocated to the VM in MiB"
  type        = number
  default     = 16384
}

variable "vm_disk_size" {
  description = "Disk size allocated to the VM in GiB"
  type        = number
  default     = 20
}

variable "zfs_pool" {
  description = "ZFS Pool name on TrueNAS to store the VM disk volume"
  type        = string
  default     = "data"
}

variable "network_bridge" {
  description = "Network bridge or interface on TrueNAS for VM attachment"
  type        = string
  default     = "vlan10"
}

variable "vm_ip" {
  description = "Static IP address for the Ubuntu VM. Convention on this network: OpenStack controllers in 10.0.10.20-29, compute/worker nodes in 10.0.10.30+ (node00/node01 admin hosts already sit on .10/.11)."
  type        = string
  default     = "10.0.10.20"
}

variable "vm_gateway" {
  description = "Network gateway for the Ubuntu VM"
  type        = string
  default     = "10.0.10.1"
}

variable "vm_mac" {
  description = "Fixed MAC address for the VM's NIC - must be set explicitly (not left to TrueNAS's auto-generation, which produces a non-functional NIC on this system). Leave empty to derive one deterministically from vm_ip's last octet."
  type        = string
  default     = ""
}

variable "vm_dns" {
  description = "DNS server for the Ubuntu VM"
  type        = string
  default     = "10.0.10.1"
}

variable "ssh_public_key" {
  description = "Public SSH key: authorized both on the TrueNAS host (root, to drive image provisioning) and inside the Ubuntu VM"
  type        = string
  default     = ""
}

variable "ubuntu_username" {
  description = "Login created inside the VM, with passwordless sudo"
  type        = string
  default     = "administrator"
}

variable "ubuntu_release" {
  description = "Ubuntu cloud image codename to deploy (e.g. noble = 24.04, jammy = 22.04)"
  type        = string
  default     = "noble"
}
