# scripts/

Each step of the pipeline is a small, independent script. They all share the
same configuration (`config.sh`) so you can run any of them in any order
(as long as the previous artifacts exist).

| Script | Purpose |
| --- | --- |
| `config.sh`     | **Sourced**, not executed. Defines paths, defaults, and `log`/`warn`/`die` helpers. Every value can be overridden by exporting it before running. |
| `check-deps.sh` | Verifies QEMU, an ISO builder, and a downloader are installed. Reports KVM availability. |
| `fetch-image.sh`| Downloads the base cloud image into `../images/` (idempotent). |
| `inject-key.sh`| Stages `../cloud-init/user-data` into the working directory, optionally injecting an extra SSH public key (via `SSH_PUBKEY` / `SSH_PUBKEY_FILE`). **Only touches the init file**, never the seed ISO, and never edits the source `cloud-init/user-data`. |
| `build-seed.sh` | Builds `../seed.iso` from the staged user-data (or from `../cloud-init/user-data` if no key was injected). Contains no key-injection logic of its own. |
| `create-disk.sh`| Creates the qcow2 overlay disk in `../images/` (backed by the base image). |
| `run-vm.sh`     | Boots QEMU with the overlay disk + seed ISO. Detached by default (no terminal output); set `VM_FOREGROUND=1` to attach the serial console. |
| `clean.sh`      | Removes generated artifacts. `--seed`, `--vm`, or `--all`. |

## Run them individually

```bash
bash scripts/check-deps.sh
bash scripts/fetch-image.sh
SSH_PUBKEY_FILE=$HOME/.ssh/id_ed25519.pub bash scripts/inject-key.sh
bash scripts/build-seed.sh
bash scripts/create-disk.sh
bash scripts/run-vm.sh
```

> `inject-key.sh` is optional. If you skip it, `build-seed.sh` will
> just use `cloud-init/user-data` as-is. If you run it, it produces
> `$WORKDIR/user-data` (the "effective" init file), which the seed builder
> then picks up automatically. Either way, neither script ever modifies
> `cloud-init/user-data` on disk.

## Or run the whole pipeline

```bash
./run-qemu.sh            # everything, including the actual VM boot
./run-qemu.sh --no-run   # prepare everything but don't boot
```

## Reset

```bash
bash scripts/clean.sh          # remove seed.iso + overlay disk
bash scripts/clean.sh --seed   # only seed.iso
bash scripts/clean.sh --vm     # only the overlay disk
bash scripts/clean.sh --all    # also the downloaded base image
```

## Override configuration

Any variable defined in `config.sh` can be overridden via the environment:

```bash
DISTRO_NAME=debian-12 \
IMG_URL=https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2 \
VM_MEM=4096 VM_CPUS=4 VM_DISK_SIZE=20G SSH_PORT=2223 \
./run-qemu.sh
```
