#!/usr/bin/env bash
#
# config.sh
# Shared configuration sourced by the other scripts in ./scripts/.
# All values can be overridden by exporting the variable before running.
#
# This file is meant to be SOURCED, not executed directly.

# Resolve the project root (the parent of the scripts/ directory) regardless
# of where the caller invoked the script from.
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
export PROJECT_DIR

# ---- Distro / image ---------------------------------------------------------
export DISTRO_NAME="${DISTRO_NAME:-ubuntu-22.04}"
export IMG_URL="${IMG_URL:-https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img}"

# ---- Working directory ------------------------------------------------------
# All generated artifacts (downloaded base image, overlay qcow2, seed.iso,
# pidfile, serial log) live under a per-user working directory so they don't
# pollute the source tree and so other users on the host can't read them.
#
# Default: /var/tmp/$USER/working   (override with WORKDIR=...)
#
# /var/tmp is preferred over /tmp because most distros do NOT wipe it on
# reboot, so the downloaded image and the overlay survive a host restart.
export WORKDIR="${WORKDIR:-/var/tmp/${USER:-$(id -un)}/working}"

# Create with mode 0700 so only the owning user can read/list/traverse it.
# umask 077 ensures any files we create afterwards inherit the same intent.
umask 077
mkdir -p "${WORKDIR}"
chmod 0700 "${WORKDIR}" 2>/dev/null || true

# ---- Paths ------------------------------------------------------------------
export IMAGES_DIR="${WORKDIR}/images"
export BASE_IMG="${IMAGES_DIR}/${DISTRO_NAME}-base.qcow2"
export VM_IMG="${IMAGES_DIR}/${DISTRO_NAME}-vm.qcow2"
export SEED_ISO="${WORKDIR}/seed.iso"
export VM_SERIAL_LOG="${VM_SERIAL_LOG:-${WORKDIR}/vm-serial.log}"
export VM_PID_FILE="${VM_PID_FILE:-${WORKDIR}/vm.pid}"
export CI_DIR="${PROJECT_DIR}/cloud-init"

# Effective (possibly key-injected) user-data produced by inject-key.sh.
# build-seed.sh prefers this file over ${CI_DIR}/user-data when it exists.
export WORKDIR_USER_DATA="${WORKDIR_USER_DATA:-${WORKDIR}/user-data}"

mkdir -p "${IMAGES_DIR}"
chmod 0700 "${IMAGES_DIR}" 2>/dev/null || true

# ---- VM resources -----------------------------------------------------------
export VM_DISK_SIZE="${VM_DISK_SIZE:-10G}"   # virtual size of the overlay disk
export VM_MEM="${VM_MEM:-2048}"              # MiB
export VM_CPUS="${VM_CPUS:-4}"
export SSH_PORT="${SSH_PORT:-2222}"          # host port forwarded to guest:22

# ---- Pretty logging ---------------------------------------------------------
log()  { printf '\033[1;34m>>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mXX\033[0m %s\n' "$*" >&2; exit 1; }
