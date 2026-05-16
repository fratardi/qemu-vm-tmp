#!/usr/bin/env bash
#
# build-seed.sh
# Thin wrapper kept for backward compatibility.
# The real work now lives in scripts/build-seed.sh.

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
exec bash "${SCRIPT_DIR}/scripts/build-seed.sh" "$@"
