#!/usr/bin/env bash
#
# run-qemu.sh
# Orchestrator: runs each step in ./scripts/ in order.
# Each step is also runnable on its own — see ./scripts/README or the
# headers inside the individual files.
#
#   ./run-qemu.sh           # full pipeline: deps -> fetch -> seed -> disk -> run
#   ./run-qemu.sh --no-run  # everything except the actual QEMU boot
#
# Tunables (export before running):
#   DISTRO_NAME  IMG_URL  VM_DISK_SIZE  VM_MEM  VM_CPUS  SSH_PORT

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
STEPS_DIR="${SCRIPT_DIR}/scripts"

run_step=true
if [[ "${1:-}" == "--no-run" ]]; then
    run_step=false
fi

bash "${STEPS_DIR}/check-deps.sh"
bash "${STEPS_DIR}/fetch-image.sh"
bash "${STEPS_DIR}/inject-key.sh"
bash "${STEPS_DIR}/build-seed.sh"
bash "${STEPS_DIR}/create-disk.sh"

if $run_step; then
    exec bash "${STEPS_DIR}/run-vm.sh"
else
    echo ">> --no-run requested, skipping VM boot."
fi
