#!/usr/bin/env bash
set -e

HOST="${TRUENAS_HOST:-10.0.60.10}"
SCHEME="${TRUENAS_SCHEME:-http}"
API_KEY="${TRUENAS_API_KEY}"
VM_NAME="${VM_NAME:-ubuntulab}"
VM_VCPUS="${VM_VCPUS:-2}"
VM_CORES="${VM_CORES:-2}"
VM_THREADS="${VM_THREADS:-1}"
VM_MEMORY="${VM_MEMORY:-4096}"
VM_DISK_SIZE_GB="${VM_DISK_SIZE:-20}"
ZFS_POOL="${ZFS_POOL:-data}"
BRIDGE="${NETWORK_BRIDGE:-vlan60}"
VM_MAC="${VM_MAC:?VM_MAC is required}"
IMAGE_URL="${UBUNTU_IMAGE_URL:?UBUNTU_IMAGE_URL is required}"
SSH_KEY="${SSH_PUBLIC_KEY:-}"

API_URL="${SCHEME}://${HOST}/api/v2.0"
AUTH_HEADER="Authorization: Bearer ${API_KEY}"
IMAGE_FILENAME="$(basename "$IMAGE_URL")"

echo "=== TrueNAS VM Deployment (${VM_NAME}) ==="
echo "TrueNAS host: ${API_URL}"

# 1. Enable SSH & authorize root on TrueNAS (needed to write the image to the zvol)
echo "Checking SSH access on TrueNAS..."
ROOT_USER=$(curl -s -k -H "${AUTH_HEADER}" "${API_URL}/user?username=root")
ROOT_ID=$(echo "$ROOT_USER" | jq -r '.[0].id // 1' 2>/dev/null || echo "1")

if [ -n "$SSH_KEY" ]; then
  curl -s -k -X PUT -H "${AUTH_HEADER}" -H "Content-Type: application/json" \
    -d "{\"sshpubkey\": \"${SSH_KEY}\"}" "${API_URL}/user/id/${ROOT_ID}" > /dev/null || true
fi

curl -s -k -X PUT -H "${AUTH_HEADER}" -H "Content-Type: application/json" -d '{"enable": true}' "${API_URL}/service/id/11" > /dev/null || true
curl -s -k -X POST -H "${AUTH_HEADER}" -H "Content-Type: application/json" -d '{"service": "ssh"}' "${API_URL}/service/start" > /dev/null || true

# 2. Check / create the VM
EXISTING_VM=$(curl -s -k -H "${AUTH_HEADER}" "${API_URL}/vm?name=${VM_NAME}")
VM_ID=$(echo "$EXISTING_VM" | jq -r '.[0].id // empty' 2>/dev/null || echo "")

if [ -n "$VM_ID" ] && [ "$VM_ID" != "null" ]; then
  echo "VM '${VM_NAME}' already exists (ID: ${VM_ID})."
else
  echo "Creating VM '${VM_NAME}'..."
  CREATE_RESP=$(curl -s -k -X POST "${API_URL}/vm" \
    -H "${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${VM_NAME}\",
      \"description\": \"Ubuntu ${VM_NAME} VM\",
      \"vcpus\": ${VM_VCPUS},
      \"cores\": ${VM_CORES},
      \"threads\": ${VM_THREADS},
      \"memory\": ${VM_MEMORY},
      \"autostart\": true,
      \"bootloader\": \"UEFI\"
    }")

  VM_ID=$(echo "$CREATE_RESP" | jq -r '.id // empty')

  if [ -z "$VM_ID" ] || [ "$VM_ID" == "null" ]; then
    echo "Error creating the VM: $CREATE_RESP"
    exit 1
  fi
  echo "VM created successfully (ID: ${VM_ID})."
fi

# 3. Check / create the ZFS volume for the disk
ZVOL_NAME="${ZFS_POOL}/${VM_NAME}disk"
VOL_BYTES=$(( VM_DISK_SIZE_GB * 1024 * 1024 * 1024 ))

echo "Checking ZFS volume '${ZVOL_NAME}'..."
ZVOL_CHECK=$(curl -s -k -H "${AUTH_HEADER}" "${API_URL}/pool/dataset/id/${ZVOL_NAME//\//%2F}")
ZVOL_EXISTS=$(echo "$ZVOL_CHECK" | jq -r '.id // empty')

if [ -z "$ZVOL_EXISTS" ] || [ "$ZVOL_EXISTS" == "null" ]; then
  echo "Creating ZFS volume '${ZVOL_NAME}' (${VM_DISK_SIZE_GB} GB)..."
  curl -s -k -X POST "${API_URL}/pool/dataset" \
    -H "${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${ZVOL_NAME}\",
      \"type\": \"VOLUME\",
      \"volsize\": ${VOL_BYTES}
    }" > /dev/null
  echo "ZFS volume created."
fi

# 4. Write the Ubuntu cloud image to the zvol over SSH (once only)
echo "Checking ZFS volume contents..."
HAS_GPT=$(ssh -o StrictHostKeyChecking=no root@${HOST} "parted -s /dev/zvol/${ZVOL_NAME} print 2>/dev/null | grep -i 'partition table: gpt'" 2>/dev/null || echo "")

if [ -z "$HAS_GPT" ]; then
  echo "ZFS volume has no partition table (or is empty). Injecting the Ubuntu cloud image..."
  ssh -o StrictHostKeyChecking=no root@${HOST} "ZFS_POOL='${ZFS_POOL}' ZVOL_NAME='${ZVOL_NAME}' IMAGE_URL='${IMAGE_URL}' IMAGE_FILENAME='${IMAGE_FILENAME}' bash -s" << 'REMOTE_SCRIPT'
    set -e
    IMAGE_PATH="/mnt/${ZFS_POOL}/${IMAGE_FILENAME}"

    # A cached file is only trusted if it actually starts with the qcow2
    # magic number (51 46 49 fb / "QFI\xfb"); a failed download (e.g. an
    # HTML error page saved by a past bad URL) would otherwise be reused
    # forever since it still passes a plain "file exists" check.
    if [ -f "$IMAGE_PATH" ]; then
      MAGIC=$(od -An -tx1 -N4 "$IMAGE_PATH" | tr -d ' \n')
      if [ "$MAGIC" != "514649fb" ]; then
        echo "Cached image at ${IMAGE_PATH} is not a valid qcow2 file, removing it..."
        rm -f "$IMAGE_PATH"
      fi
    fi

    if [ ! -f "$IMAGE_PATH" ]; then
      echo "Downloading Ubuntu cloud image (${IMAGE_FILENAME})..."
      curl -fsSL -o "$IMAGE_PATH" "${IMAGE_URL}"
    fi
    echo "Converting to ZVOL /dev/zvol/${ZVOL_NAME}..."
    qemu-img convert -f qcow2 -O raw "$IMAGE_PATH" "/dev/zvol/${ZVOL_NAME}"

    # UEFI safety net: some cloud images don't ship /EFI/BOOT/BOOTX64.EFI (the
    # default path OVMF looks for when there's no NVRAM boot entry). If missing,
    # build it from whichever grubx64.efi is present in the image.
    LOOP=$(losetup -fP --show "/dev/zvol/${ZVOL_NAME}")
    partprobe "${LOOP}" 2>/dev/null || true
    sleep 1

    EFI_DEV=""
    if [ -b "${LOOP}p15" ]; then EFI_DEV="${LOOP}p15"; elif [ -b "${LOOP}p1" ]; then EFI_DEV="${LOOP}p1"; fi
    if [ -n "$EFI_DEV" ]; then
      mkdir -p /tmp/vm-efi
      mount "$EFI_DEV" /tmp/vm-efi 2>/dev/null || true
      if [ ! -f /tmp/vm-efi/EFI/BOOT/BOOTX64.EFI ]; then
        GRUB_EFI=$(find /tmp/vm-efi/EFI -mindepth 2 -iname 'grubx64.efi' | head -n1)
        if [ -n "$GRUB_EFI" ]; then
          mkdir -p /tmp/vm-efi/EFI/BOOT
          cp "$GRUB_EFI" /tmp/vm-efi/EFI/BOOT/BOOTX64.EFI
        fi
      fi
      umount /tmp/vm-efi 2>/dev/null || true
    fi
    losetup -d "${LOOP}" 2>/dev/null || true
REMOTE_SCRIPT
  echo "Ubuntu image injected onto the disk."
fi

# 5. Build & upload the Cloud-Init seed ISO (CIDATA)
echo "Preparing Cloud-Init seed ISO..."
USER_DATA_FILE="user_data_${VM_NAME}.yaml"
NETWORK_CONFIG_FILE="network_config_${VM_NAME}.yaml"
ISO_NAME="cloud-init-${VM_NAME}.iso"
LOCAL_TMP_ISO="/tmp/${ISO_NAME}"

# TrueNAS's VM device validation rejects a CDROM path that isn't itself a ZFS
# dataset mountpoint or inside one ("The path must be a dataset or a directory
# within a dataset.") - neither the pool root nor a plain mkdir'd subdirectory
# satisfy it, so the ISO needs a real child dataset to live in.
ISO_DATASET="${ZFS_POOL}/cloud-init"
ISO_DATASET_CHECK=$(curl -s -k -H "${AUTH_HEADER}" "${API_URL}/pool/dataset/id/${ISO_DATASET//\//%2F}")
ISO_DATASET_EXISTS=$(echo "$ISO_DATASET_CHECK" | jq -r '.id // empty')
if [ -z "$ISO_DATASET_EXISTS" ] || [ "$ISO_DATASET_EXISTS" == "null" ]; then
  echo "Creating ZFS dataset '${ISO_DATASET}' for the Cloud-Init ISO..."
  curl -s -k -X POST "${API_URL}/pool/dataset" \
    -H "${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${ISO_DATASET}\",
      \"type\": \"FILESYSTEM\"
    }" > /dev/null
fi

REMOTE_ISO_PATH="/mnt/${ISO_DATASET}/${ISO_NAME}"

if [ -f "${USER_DATA_FILE}" ]; then
  TMP_DIR=$(mktemp -d /tmp/cidata-XXXXXX)
  cp "${USER_DATA_FILE}" "${TMP_DIR}/user-data"
  [ -f "${NETWORK_CONFIG_FILE}" ] && cp "${NETWORK_CONFIG_FILE}" "${TMP_DIR}/network-config"
  echo "instance-id: ${VM_NAME}-01" > "${TMP_DIR}/meta-data"
  echo "local-hostname: ${VM_NAME}" >> "${TMP_DIR}/meta-data"

  if command -v xorriso >/dev/null 2>&1; then
    xorriso -as mkisofs -V CIDATA -o "${LOCAL_TMP_ISO}" -J -r "${TMP_DIR}" > /dev/null 2>&1
  elif command -v genisoimage >/dev/null 2>&1; then
    genisoimage -output "${LOCAL_TMP_ISO}" -volid CIDATA -joliet -rock "${TMP_DIR}" > /dev/null 2>&1
  elif command -v mkisofs >/dev/null 2>&1; then
    mkisofs -output "${LOCAL_TMP_ISO}" -volid CIDATA -joliet -rock "${TMP_DIR}" > /dev/null 2>&1
  else
    echo "No mkisofs/genisoimage/xorriso tool found locally." >&2
    exit 1
  fi
  rm -rf "${TMP_DIR}"

  if [ -f "${LOCAL_TMP_ISO}" ]; then
    scp -o StrictHostKeyChecking=no "${LOCAL_TMP_ISO}" root@${HOST}:"${REMOTE_ISO_PATH}" > /dev/null
    echo "Cloud-Init ISO uploaded to TrueNAS (${REMOTE_ISO_PATH})."
  fi
fi

# 6. Attach devices (NIC, DISK, CDROM)
VM_DEVICES=$(curl -s -k -H "${AUTH_HEADER}" "${API_URL}/vm/device?vm=${VM_ID}")

# POST a new device and fail loudly if the API rejects it, instead of
# silently ignoring the error (which is how a bad CDROM path once went
# unnoticed and left the VM without its Cloud-Init seed attached).
create_device() {
  local payload="$1" resp new_id
  resp=$(curl -s -k -X POST "${API_URL}/vm/device" \
    -H "${AUTH_HEADER}" -H "Content-Type: application/json" -d "${payload}")
  new_id=$(echo "$resp" | jq -r '.id // empty' 2>/dev/null || echo "")
  if [ -z "$new_id" ] || [ "$new_id" == "null" ]; then
    echo "Error attaching device: $resp" >&2
    exit 1
  fi
}

# A. Network interface (NIC)
HAS_NIC=$(echo "$VM_DEVICES" | jq -r '.[] | select(.attributes.dtype=="NIC") | .id' 2>/dev/null || echo "")

if [ -n "$HAS_NIC" ] && [ "$HAS_NIC" != "null" ]; then
  echo "Updating NIC to attach on ${BRIDGE} (MAC ${VM_MAC})..."
  curl -s -k -X PUT "${API_URL}/vm/device/id/${HAS_NIC}" \
    -H "${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -d "{
      \"attributes\": {
        \"dtype\": \"NIC\",
        \"type\": \"VIRTIO\",
        \"nic_attach\": \"${BRIDGE}\",
        \"mac\": \"${VM_MAC}\"
      }
    }" > /dev/null || true
else
  echo "Attaching NIC on ${BRIDGE} (MAC ${VM_MAC})..."
  create_device "{
      \"vm\": ${VM_ID},
      \"attributes\": {
        \"dtype\": \"NIC\",
        \"type\": \"VIRTIO\",
        \"nic_attach\": \"${BRIDGE}\",
        \"mac\": \"${VM_MAC}\"
      },
      \"order\": 1000
    }"
fi

# B. ZFS disk
HAS_DISK=$(echo "$VM_DEVICES" | jq -r '.[] | select(.attributes.dtype=="DISK") | .id' 2>/dev/null || echo "")
if [ -z "$HAS_DISK" ]; then
  echo "Attaching ZFS disk..."
  create_device "{
      \"vm\": ${VM_ID},
      \"attributes\": {
        \"dtype\": \"DISK\",
        \"path\": \"/dev/zvol/${ZVOL_NAME}\",
        \"type\": \"VIRTIO\"
      },
      \"order\": 1001
    }"
fi

# C. CD-ROM for the Cloud-Init seed
HAS_CDROM=$(echo "$VM_DEVICES" | jq -r '.[] | select(.attributes.dtype=="CDROM") | .id' 2>/dev/null || echo "")
if [ -n "$HAS_CDROM" ] && [ "$HAS_CDROM" != "null" ]; then
  curl -s -k -X PUT "${API_URL}/vm/device/id/${HAS_CDROM}" \
    -H "${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -d "{
      \"attributes\": {
        \"dtype\": \"CDROM\",
        \"path\": \"${REMOTE_ISO_PATH}\"
      }
    }" > /dev/null || true
else
  echo "Attaching Cloud-Init CD-ROM (${REMOTE_ISO_PATH})..."
  create_device "{
      \"vm\": ${VM_ID},
      \"attributes\": {
        \"dtype\": \"CDROM\",
        \"path\": \"${REMOTE_ISO_PATH}\"
      },
      \"order\": 1002
    }"
fi

# 7. Start the VM
VM_STATUS=$(curl -s -k -H "${AUTH_HEADER}" "${API_URL}/vm/id/${VM_ID}")
IS_RUNNING=$(echo "$VM_STATUS" | jq -r '.status.state // empty')

if [ "$IS_RUNNING" != "RUNNING" ]; then
  echo "Starting VM ${VM_ID}..."
  curl -s -k -X POST "${API_URL}/vm/id/${VM_ID}/start" -H "${AUTH_HEADER}" > /dev/null
  echo "VM ${VM_ID} started successfully."
fi

echo "=== TrueNAS VM deployment (Ubuntu + Cloud-Init) completed successfully ==="
