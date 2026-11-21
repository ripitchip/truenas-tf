# OpenTofu stack: standard Ubuntu VM on TrueNAS SCALE

Deploys a standard **Ubuntu Cloud Image** VM (22.04/24.04...) on **TrueNAS SCALE**, via the TrueNAS `/api/v2.0` REST API and a Cloud-Init (NoCloud) seed, with a sudo user + SSH key already configured.

Reuses the mechanics of the `02_truenas` stack from the `Terraform_IAC` repo (Xen Orchestra deployment on TrueNAS), simplified for a generic Ubuntu VM: no manual image patching, no application install — just standard cloud-init.

---

## Architecture

1. **OpenTofu** generates the Cloud-Init seed locally (`user-data` + `network-config`) from the variables.
2. A `null_resource` calls `scripts/deploy_vm.sh` via `local-exec`, which:
   - Enables SSH on TrueNAS and authorizes the provided key (needed to write the image to disk),
   - Creates the VM via the REST API (`POST /vm`),
   - Creates a ZFS volume (zvol) as the disk (`POST /pool/dataset`),
   - Downloads the Ubuntu cloud image onto TrueNAS and writes it raw to the zvol (`qemu-img convert`),
   - Builds a `CIDATA` ISO (user-data/meta-data/network-config) and uploads it to TrueNAS,
   - Attaches NIC/DISK/CDROM to the VM (`POST /vm/device`),
   - Starts the VM.
3. On first boot, **cloud-init** (already present in the Ubuntu image) reads the seed ISO and configures: hostname, static IP, user + SSH key, `qemu-guest-agent`.
4. `tofu destroy` removes the VM, the zvol, and the ISO (`scripts/destroy_vm.sh`).

> No TrueNAS provider is used: TrueNAS SCALE doesn't (yet) expose a mature OpenTofu/Terraform resource for VMs, so everything goes through the REST API directly.

---

## Requirements

1. **TrueNAS SCALE** still on the legacy VM manager (KVM/libvirt — not yet switched to the Incus-based "Instances" introduced in 25.04+).
2. **TrueNAS API key**: `System` → `API Keys`.
3. **ZFS pool** available (e.g. `data`).
4. **Network bridge** configured on TrueNAS (e.g. `vlan60`).
5. Locally: `opentofu` (or `tofu`), `jq`, `ssh`/`scp`, and an ISO tool (`xorriso`, `genisoimage`, or `mkisofs`). The provided devcontainer installs all of this.

---

## Deployment

```bash
cd truenas-ubuntu
cp secret.auto.tfvars.example secret.auto.tfvars
# edit secret.auto.tfvars: truenas_api_key, ssh_public_key

tofu init
tofu plan
tofu apply
```

Variables worth adjusting (see `variables.tf`): `vm_name`, `vm_ip`, `vm_gateway`, `network_bridge`, `zfs_pool`, `ubuntu_release` (`noble` = 24.04, `jammy` = 22.04), `ubuntu_username`, CPU/RAM/disk specs.

⚠️ Pick a `vm_name` / `vm_ip` distinct from the Xen Orchestra instance already deployed on this same TrueNAS (`10.0.60.50`).

### IP convention on `10.0.10.0/24` (vlan10)

- `.1` gateway, `.5` TrueNAS, `.10`/`.11` existing admin nodes (`node00`/`node01`)
- `.20`-`.29`: OpenStack controllers (this stack's `ctrl00` = `.20`)
- `.30`+: compute/worker nodes
- `.100`-`.254`: DHCP pool — do not use statically

## Connecting

```bash
ssh <ubuntu_username>@<vm_ip>
```

## Teardown

```bash
tofu destroy
```
