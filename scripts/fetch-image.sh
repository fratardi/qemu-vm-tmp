#!/usr/bin/env bash
#
# fetch-image.sh
# Download the base cloud image (qcow2) into ./images/ if not already present.

set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/config.sh"

mkdir -p "${IMAGES_DIR}"

if [[ -f "${BASE_IMG}" ]]; then
    log "Base image already present: ${BASE_IMG}"
    exit 0
fi


tmp="${BASE_IMG}.part"

curl -L --fail --progress-bar -o "${tmp}" "${IMG_URL}"

mv "${tmp}" "${BASE_IMG}"
chmod 0600 "${BASE_IMG}" 2>/dev/null || true

log "Downloaded: ${BASE_IMG}"
