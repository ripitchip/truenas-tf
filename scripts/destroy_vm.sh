#!/usr/bin/env bash
set -e

HOST="${TRUENAS_HOST:-10.0.60.10}"
SCHEME="${TRUENAS_SCHEME:-http}"
API_KEY="${TRUENAS_API_KEY}"
VM_NAME="${VM_NAME:-ubuntulab}"
ZFS_POOL="${ZFS_POOL:-data}"

API_URL="${SCHEME}://${HOST}/api/v2.0"
AUTH_HEADER="Authorization: Bearer ${API_KEY}"

echo "=== TrueNAS VM Destruction (${VM_NAME}) ==="

# 1. Get the VM ID
EXISTING_VM=$(curl -s -k -H "${AUTH_HEADER}" "${API_URL}/vm?name=${VM_NAME}")
VM_ID=$(echo "$EXISTING_VM" | jq -r '.[0].id // empty' 2>/dev/null || echo "")

if [ -n "$VM_ID" ] && [ "$VM_ID" != "null" ]; then
  echo "Stopping VM '${VM_NAME}' (ID: ${VM_ID})..."
  curl -s -k -X POST "${API_URL}/vm/id/${VM_ID}/stop" -H "${AUTH_HEADER}" > /dev/null || true
  sleep 3

  echo "Deleting VM '${VM_NAME}'..."
  curl -s -k -X DELETE "${API_URL}/vm/id/${VM_ID}" -H "${AUTH_HEADER}" > /dev/null || true
  echo "VM '${VM_NAME}' deleted."
else
  echo "VM '${VM_NAME}' does not exist or was already deleted."
fi

# 2. Delete the ZFS volume (zvol)
ZVOL_NAME="${ZFS_POOL}/${VM_NAME}disk"
echo "Deleting ZFS volume '${ZVOL_NAME}'..."
curl -s -k -X DELETE "${API_URL}/pool/dataset/id/${ZVOL_NAME//\//%2F}?cascade=true" -H "${AUTH_HEADER}" > /dev/null || true

# 3. Clean up the Cloud-Init ISO on TrueNAS
ISO_NAME="cloud-init-${VM_NAME}.iso"
REMOTE_ISO_PATH="/mnt/${ZFS_POOL}/cloud-init/${ISO_NAME}"
echo "Deleting Cloud-Init ISO on TrueNAS (${REMOTE_ISO_PATH})..."
ssh -o StrictHostKeyChecking=no root@${HOST} "rm -f ${REMOTE_ISO_PATH}" 2>/dev/null || true

echo "=== Destruction completed successfully ==="
