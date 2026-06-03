#!/usr/bin/env bash
#
# inject-key.sh
# Produce an "effective" cloud-init user-data file in the working directory,
# optionally with an extra SSH public key injected under `ssh_authorized_keys`.
#
# This script ONLY touches the init file. It does NOT build the seed ISO
# (that is the job of build-seed.sh) and it never modifies the source
# cloud-init/user-data on disk.
#
# Inputs (env):
#   SSH_PUBKEY        inline public key, e.g. "ssh-ed25519 AAAA... user@host"
#   SSH_PUBKEY_FILE   path to a .pub file to read the key from
#
# If neither is set, the source user-data is copied verbatim to
# ${WORKDIR_USER_DATA} (no key injection, just a working-dir copy so the
# pipeline always has a stable input path).
#
# Output:
#   ${WORKDIR_USER_DATA}   (defaults to ${WORKDIR}/user-data)
#
# Examples:
#   SSH_PUBKEY_FILE=$HOME/.ssh/id_ed25519.pub ./inject-key.sh
#   SSH_PUBKEY="ssh-ed25519 AAAA... me@host"  ./inject-key.sh

set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/config.sh"

SRC_USER_DATA="${CI_DIR}/user-data"
[[ -f "${SRC_USER_DATA}" ]] || die "missing ${SRC_USER_DATA}"

# ---------------------------------------------------------------------------
# Resolve the (optional) extra SSH public key.
# ---------------------------------------------------------------------------
EXTRA_KEY=""
if [[ -n "${SSH_PUBKEY:-}" ]]; then
    EXTRA_KEY="${SSH_PUBKEY}"
elif [[ -n "${SSH_PUBKEY_FILE:-}" ]]; then
    [[ -r "${SSH_PUBKEY_FILE}" ]] || die "SSH_PUBKEY_FILE not readable: ${SSH_PUBKEY_FILE}"
    EXTRA_KEY="$(< "${SSH_PUBKEY_FILE}")"
fi
# Strip surrounding whitespace / trailing newlines.
EXTRA_KEY="${EXTRA_KEY%$'\n'}"
EXTRA_KEY="${EXTRA_KEY#"${EXTRA_KEY%%[![:space:]]*}"}"
EXTRA_KEY="${EXTRA_KEY%"${EXTRA_KEY##*[![:space:]]}"}"

mkdir -p "$(dirname -- "${WORKDIR_USER_DATA}")"

if [[ -z "${EXTRA_KEY}" ]]; then
    log "No SSH key supplied; staging user-data without injection -> ${WORKDIR_USER_DATA}"
    install -m 0600 "${SRC_USER_DATA}" "${WORKDIR_USER_DATA}"
    exit 0
fi

log "Injecting extra SSH key into ${WORKDIR_USER_DATA} (source ${SRC_USER_DATA} untouched)"

TMP_OUT="$(mktemp "${WORKDIR}/.user-data.XXXXXX")"
chmod 0600 "${TMP_OUT}"
trap 'rm -f "${TMP_OUT}"' EXIT

# REPLACE the contents of the first `ssh_authorized_keys:` block with our
# single key. Any existing `- ssh-...` entries under that block are dropped.
#
# We MUST use a consistent indentation for the new entry. We reuse the
# indentation of the first existing list item if there is one; otherwise we
# fall back to parent_indent + 2 spaces.
awk -v key="${EXTRA_KEY}" '
    function flush_block(   indent) {
        # Decide the indent for our single new entry.
        indent = (item_indent != "") ? item_indent : (parent_indent "  ")
        printf "%s- %s\n", indent, key
    }
    BEGIN { state = "scan"; parent_indent = ""; item_indent = ""; injected = 0 }
    {
        if (state == "scan") {
            print $0
            if ($0 ~ /^[[:space:]]*ssh_authorized_keys:[[:space:]]*$/) {
                match($0, /^[[:space:]]*/)
                parent_indent = substr($0, RSTART, RLENGTH)
                item_indent = ""
                state = "in_block"
            }
            next
        }

        # state == "in_block": eat existing list items (`<deeper-indent>- ...`)
        # and comment / blank lines that belong to the block, until we hit a
        # line at parent_indent or shallower depth (end of the block).
        if ($0 ~ /^[[:space:]]*-[[:space:]]/) {
            match($0, /^[[:space:]]*/)
            this_indent = substr($0, RSTART, RLENGTH)
            if (length(this_indent) > length(parent_indent)) {
                # Record the first items indent so we can mimic it exactly.
                if (item_indent == "") item_indent = this_indent
                # Drop the existing entry.
                next
            }
        }
        if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*#/) {
            # Blank or comment line: keep it associated with the block but
            # do not end the block on it. Easiest correct thing: drop blanks
            # inside the block and keep comments verbatim AFTER we have
            # flushed our replacement entry.
            if ($0 ~ /^[[:space:]]*$/) next
            # comment line: emit replacement first if not yet done
            if (!injected) { flush_block(); injected = 1 }
            print $0
            next
        }

        # Anything else means we have left the ssh_authorized_keys: block.
        if (!injected) { flush_block(); injected = 1 }
        state = "done"
        print $0
    }
    END {
        if (state == "in_block" && !injected) {
            flush_block()
            injected = 1
        }
        if (!injected) {
            # No ssh_authorized_keys: block found anywhere. Append one.
            print "ssh_authorized_keys:"
            printf "  - %s\n", key
        }
    }
' "${SRC_USER_DATA}" > "${TMP_OUT}"

mv -f "${TMP_OUT}" "${WORKDIR_USER_DATA}"
chmod 0600 "${WORKDIR_USER_DATA}"
trap - EXIT

log "Effective user-data ready: ${WORKDIR_USER_DATA}"
