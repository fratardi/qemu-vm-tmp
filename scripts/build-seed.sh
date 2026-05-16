#!/usr/bin/env bash
#
# build-seed.sh
# Build the cloud-init NoCloud seed ISO from ./cloud-init/ (+ optional
# pre-staged user-data in the working directory).
#
# Prefers `cloud-localds`; falls back to genisoimage / mkisofs / xorriso.
#
# This script does NOT perform any SSH key injection. If you want to add an
# extra public key, run `scripts/inject-key.sh` FIRST — it will produce
# ${WORKDIR_USER_DATA} which this script will then pick up automatically.
#
# Resolution order for the user-data fed into the seed:
#   1. ${WORKDIR_USER_DATA}        (if it exists — produced by inject-key.sh)
#   2. ${CI_DIR}/user-data         (the source file in the repo)

set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/config.sh"

SRC_USER_DATA="${CI_DIR}/user-data"
META_DATA="${CI_DIR}/meta-data"
NET_CONFIG="${CI_DIR}/network-config"

[[ -f "${SRC_USER_DATA}" ]] || die "missing ${SRC_USER_DATA}"
[[ -f "${META_DATA}"     ]] || die "missing ${META_DATA}"

# Pick the effective user-data: prefer the pre-staged one from
# inject-key.sh if present, otherwise fall back to the source.
if [[ -f "${WORKDIR_USER_DATA}" ]]; then
    EFFECTIVE_USER_DATA="${WORKDIR_USER_DATA}"
    log "Using pre-staged user-data: ${EFFECTIVE_USER_DATA}"
else
    EFFECTIVE_USER_DATA="${SRC_USER_DATA}"
    log "Using source user-data: ${EFFECTIVE_USER_DATA}"
fi

log "Building cloud-init seed ISO: ${SEED_ISO}"

if command -v cloud-localds >/dev/null 2>&1; then
    log "Using cloud-localds"
    if [[ -f "${NET_CONFIG}" ]]; then
        cloud-localds -v --network-config="${NET_CONFIG}" "${SEED_ISO}" "${EFFECTIVE_USER_DATA}" "${META_DATA}"
    else
        cloud-localds -v "${SEED_ISO}" "${EFFECTIVE_USER_DATA}" "${META_DATA}"
    fi
else
    log "cloud-localds not found, falling back to genisoimage/mkisofs/xorriso"
    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp}"' EXIT
    cp "${EFFECTIVE_USER_DATA}" "${tmp}/user-data"
    cp "${META_DATA}"           "${tmp}/meta-data"
    files=( "${tmp}/user-data" "${tmp}/meta-data" )
    if [[ -f "${NET_CONFIG}" ]]; then
        cp "${NET_CONFIG}" "${tmp}/network-config"
        files+=( "${tmp}/network-config" )
    fi

    if command -v genisoimage >/dev/null 2>&1; then
        genisoimage -output "${SEED_ISO}" -volid cidata -joliet -rock "${files[@]}"
    elif command -v mkisofs >/dev/null 2>&1; then
        mkisofs -output "${SEED_ISO}" -volid cidata -joliet -rock "${files[@]}"
    elif command -v xorriso >/dev/null 2>&1; then
        xorriso -as mkisofs -output "${SEED_ISO}" -volid cidata -joliet -rock "${files[@]}"
    else
        die "no ISO builder available (need cloud-localds, genisoimage, mkisofs, or xorriso)"
    fi
fi

chmod 0600 "${SEED_ISO}" 2>/dev/null || true
log "Seed ISO ready: ${SEED_ISO}"
