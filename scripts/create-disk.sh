#!/usr/bin/env bash
#
# create-disk.sh
# Create a qcow2 overlay disk that uses the base cloud image as a backing file.
# The base image stays read-only; all VM writes go into the overlay.
# To "reset" the VM, just delete the overlay and run this script again.

set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/config.sh"

[[ -f "${BASE_IMG}" ]] || die "base image not found: ${BASE_IMG} (run fetch-image.sh first)"

if [[ -f "${VM_IMG}" ]]; then
    log "Overlay disk already exists: ${VM_IMG}"
    exit 0
fi

log "Creating overlay disk:"
log "  Backing : ${BASE_IMG}"
log "  Overlay : ${VM_IMG}"
log "  Size    : ${VM_DISK_SIZE}"

qemu-img create -f qcow2 -F qcow2 -b "${BASE_IMG}" "${VM_IMG}" "${VM_DISK_SIZE}"
chmod 0600 "${VM_IMG}" 2>/dev/null || true

log "Overlay created."
