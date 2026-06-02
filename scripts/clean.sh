#!/usr/bin/env bash
#
# clean.sh
# Remove generated artifacts so the next run starts fresh.
#
#   --all    also delete the downloaded base image
#   --seed   only delete seed.iso
#   --vm     only delete the overlay disk
# (default: delete seed.iso and the overlay disk, keep the base image)

KNOWN_HOSTS="/home/fratardi/.ssh/known_hosts"

set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/config.sh"

mode="default"
case "${1:-}" in
    --all)    mode="all"    ;;
    --seed)   mode="seed"   ;;
    --vm)     mode="vm"     ;;
    --purge)  mode="purge"  ;;
    "")       mode="default" ;;
    *)        die "unknown option: $1 (use --all | --seed | --vm | --purge)" ;;
esac

remove() {
    if [[ -e "$1" ]]; then
        log "Removing $1"
        rm -f "$1"
    fi
}

# Refuse to remove anything while the VM is still running.
if [[ -f "${VM_PID_FILE}" ]] && kill -0 "$(cat "${VM_PID_FILE}")" 2>/dev/null; then
    die "VM is still running (PID $(cat "${VM_PID_FILE}")). Stop it first: kill \$(cat ${VM_PID_FILE})"
fi

case "${mode}" in
    seed)    remove "${SEED_ISO}"; remove "${WORKDIR_USER_DATA}" ;;
    vm)      remove "${VM_IMG}"   ;;
    default) remove "${SEED_ISO}"; remove "${WORKDIR_USER_DATA}"; remove "${VM_IMG}"
             remove "${VM_SERIAL_LOG}"; remove "${VM_PID_FILE}" ;;
    all)     remove "${SEED_ISO}"; remove "${WORKDIR_USER_DATA}"; remove "${VM_IMG}"; remove "${BASE_IMG}"
             remove "${VM_SERIAL_LOG}"; remove "${VM_PID_FILE}" ;;
    purge)   # Wipe the whole per-user working directory.
             if [[ -d "${WORKDIR}" ]]; then
                 log "Removing working directory: ${WORKDIR}"
                 rm -rf -- "${WORKDIR}"
                 log "Removing old ssh known hosts @: ${KNOWN_HOSTS}"
                 rm -rf -- "${KNOWN_HOSTS}"
             fi ;;

esac

log "Clean done (mode=${mode})."
