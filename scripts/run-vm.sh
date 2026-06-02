#!/usr/bin/env bash
#
# run-vm.sh
# Boot the VM with QEMU. Assumes the previous steps have already produced:
#   - the base image      (fetch-image.sh)
#   - the seed.iso        (build-seed.sh)
#   - the overlay disk    (create-disk.sh)
#
# By default the VM is started in the BACKGROUND:
#   - QEMU opens its own graphical window  (default SDL/GTK display)
#   - nothing is printed on this terminal  (stdout/serial -> ${VM_SERIAL_LOG})
#   - the launcher returns immediately     (PID -> ${VM_PID_FILE})
#
# Reach the guest over SSH:
#   ssh -p ${SSH_PORT} ubuntu@localhost     (password: ubuntu)
#
# Watch the serial output (optional):
#   tail -f ${VM_SERIAL_LOG}
#
# Stop the VM:
#   close the QEMU window, or:  kill "$(cat ${VM_PID_FILE})"
#
# Options (env vars):
#   VM_FOREGROUND=1   attach serial console to this terminal (Ctrl-a x to quit)
#   VM_HEADLESS=1     don't open a graphical window (true headless)

set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/config.sh"

[[ -f "${VM_IMG}"   ]] || die "overlay disk missing: ${VM_IMG} (run create-disk.sh)"
[[ -f "${SEED_ISO}" ]] || die "seed ISO missing: ${SEED_ISO} (run build-seed.sh)"

QEMU_BIN="$(command -v qemu-system-x86_64 || true)"
[[ -n "${QEMU_BIN}" ]] || die "qemu-system-x86_64 not found (apt install qemu-system-x86)"

: "${VM_FOREGROUND:=0}"
: "${VM_HEADLESS:=0}"
# VM_SERIAL_LOG and VM_PID_FILE are defaulted by config.sh inside ${WORKDIR}.

# Refuse to start if another instance is already running (otherwise QEMU dies
# with "Failed to get write lock" on the qcow2).
if [[ -f "${VM_PID_FILE}" ]] && kill -0 "$(cat "${VM_PID_FILE}")" 2>/dev/null; then
    die "VM already running (PID $(cat "${VM_PID_FILE}")). Stop it with: kill \$(cat ${VM_PID_FILE})"
fi
rm -f "${VM_PID_FILE}"

ACCEL_ARGS=()
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    ACCEL_ARGS+=( -accel kvm -cpu host )
    log "Using KVM acceleration."
else
    ACCEL_ARGS+=( -accel tcg -cpu max )
    warn "KVM unavailable, using TCG (slow)."
fi

# Display: by default open a GUI window so the user can see/use the VM.
# VM_HEADLESS=1 disables the window entirely (useful over SSH).
# VM_DISPLAY can override the QEMU -display backend (gtk, sdl, ...).
IO_ARGS=()
if [[ "${VM_HEADLESS}" == "1" ]]; then
    IO_ARGS+=( -display none )
    DISPLAY_MODE="headless (no GUI window)"
else
    # Pick a graphical backend explicitly so we don't rely on QEMU's defaults
    # (which can end up as "none" in background/detached invocations).
    if [[ -n "${VM_DISPLAY:-}" ]]; then
        chosen_display="${VM_DISPLAY}"
    else
        available="$("${QEMU_BIN}" -display help 2>/dev/null || true)"
        chosen_display=""
        for d in gtk sdl; do
            if grep -qx "${d}" <<<"${available}"; then
                chosen_display="${d}"
                break
            fi
        done
        [[ -n "${chosen_display}" ]] || die "no GUI display backend (gtk/sdl) available in this QEMU build; install qemu-system-gui or run with VM_HEADLESS=1"
    fi
    IO_ARGS+=( -display "${chosen_display}" )
    DISPLAY_MODE="GUI window (-display ${chosen_display})"
fi


# Serial:
#   - foreground: serial attached to this terminal (Ctrl-a x to quit)
#   - default   : serial sent to a log file
if [[ "${VM_FOREGROUND}" == "1" ]]; then
    IO_ARGS+=( -serial mon:stdio )
else
    IO_ARGS+=( -serial "file:${VM_SERIAL_LOG}" )
    : > "${VM_SERIAL_LOG}"
    chmod 0600 "${VM_SERIAL_LOG}" 2>/dev/null || true
fi

cat <<EOF

============================================================
 Booting ${DISTRO_NAME}
   disk    : ${VM_IMG}
   seed    : ${SEED_ISO}
   mem     : ${VM_MEM} MiB
   cpus    : ${VM_CPUS}
   ssh     : ssh -p ${SSH_PORT} dev@localhost   (password: ubuntu)
   display : ${DISPLAY_MODE}
EOF
if [[ "${VM_FOREGROUND}" == "1" ]]; then
    cat <<EOF
   mode    : foreground (serial on this terminal)
   exit    : Ctrl-a then x
============================================================

EOF
else
    cat <<EOF
   mode    : background (terminal stays clean)
   serial  : tail -f ${VM_SERIAL_LOG}
   stop    : kill \$(cat ${VM_PID_FILE})
============================================================

EOF
fi

QEMU_CMD=( "${QEMU_BIN}"
    -name "${DISTRO_NAME}"
    -machine q35
    "${ACCEL_ARGS[@]}"
    -smp "${VM_CPUS}"
    -m "${VM_MEM}"
    "${IO_ARGS[@]}"
    -drive "if=virtio,format=qcow2,file=${VM_IMG}"
    -drive "if=virtio,format=raw,readonly=on,file=${SEED_ISO}"
    -device virtio-net-pci,netdev=net0
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22"
    -device virtio-rng-pci
    -pidfile "${VM_PID_FILE}"
)

if [[ "${VM_FOREGROUND}" == "1" ]]; then
    exec "${QEMU_CMD[@]}"
else
    # Run in the background, fully detached from the terminal, but keep the
    # GUI window open (no -daemonize, which can interfere with the SDL/GTK UI
    # on some setups).
    #
    # - setsid              : new session, fully detached from the controlling tty
    # - </dev/null          : no stdin
    # - >>${VM_SERIAL_LOG}  : capture any QEMU diagnostics
    # - 2>&1                : merge stderr into the same log
    # - &                   : background
    # - disown              : forget about it so closing the shell doesn't kill it
    setsid "${QEMU_CMD[@]}" </dev/null >>"${VM_SERIAL_LOG}" 2>&1 &
    QEMU_PID=$!
    disown "${QEMU_PID}" 2>/dev/null || true

    # Give QEMU a moment to start (and to write its own pidfile).
    sleep 1

    if ! kill -0 "${QEMU_PID}" 2>/dev/null; then
        die "QEMU exited immediately. See ${VM_SERIAL_LOG} for details."
    fi

    if [[ ! -f "${VM_PID_FILE}" ]]; then
        # Fallback: QEMU didn't write the pidfile yet, store the child PID.
        echo "${QEMU_PID}" > "${VM_PID_FILE}"
    fi
    log "VM started in background (PID $(cat "${VM_PID_FILE}"))."
fi
