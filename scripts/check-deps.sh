#!/usr/bin/env bash
#
# check-deps.sh
# Verify that the host has everything needed to build a seed ISO and run QEMU.
# Prints a friendly apt install hint when something is missing.

set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/config.sh"

missing=()

# QEMU itself
command -v qemu-system-x86_64 >/dev/null 2>&1 || missing+=("qemu-system-x86_64 (apt: qemu-system-x86)")
command -v qemu-img           >/dev/null 2>&1 || missing+=("qemu-img (apt: qemu-utils)")

# Something that can build an ISO
if ! command -v cloud-localds >/dev/null 2>&1 \
    && ! command -v genisoimage >/dev/null 2>&1 \
    && ! command -v mkisofs     >/dev/null 2>&1 \
    && ! command -v xorriso     >/dev/null 2>&1; then
    missing+=("cloud-localds (apt: cloud-image-utils) OR genisoimage/xorriso")
fi

# Something that can download
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    missing+=("curl or wget")
fi

if (( ${#missing[@]} > 0 )); then
    warn "Missing dependencies:"
    for m in "${missing[@]}"; do
        printf '   - %s\n' "$m" >&2
    done
    echo >&2
    echo "On Debian/Ubuntu, a one-liner that covers everything is:" >&2
    echo "  sudo apt install -y qemu-system-x86 qemu-utils cloud-image-utils curl" >&2
    exit 1
fi

# KVM is optional but warn if absent.
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    log "KVM available — hardware acceleration will be used."
else
    warn "KVM not available (or no permission on /dev/kvm). Will fall back to TCG (slow)."
    warn "To enable KVM: sudo usermod -aG kvm \"\$USER\"  (then log out / back in)"
fi

log "All required dependencies are present."
