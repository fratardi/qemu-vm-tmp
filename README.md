# Qemu-init — Boot a cloud image under QEMU with cloud-init


1. Write a **cloud-init** configuration (`user-data`, `meta-data`, `network-config`).
2. Package it as a **NoCloud seed ISO** (`seed.iso`).
3. Boot an **Ubuntu cloud image** under **QEMU/KVM** with that seed attached,
   so cloud-init configures the VM on first boot (user, SSH, packages, etc.).

The pipeline is split into small, independent scripts under `scripts/` —
you can run them one at a time or all at once with `./run-qemu.sh`.

## Layout

```
Qemu-init/
├── cloud-init/
│   ├── user-data            # main cloud-config (users, packages, runcmd, ...)
│   ├── meta-data            # instance-id / hostname
│   └── network-config       # netplan-style network config (DHCP)
├── scripts/
│   ├── config.sh         # shared config (sourced by the others)
│   ├── check-deps.sh     # checks qemu / iso-tools / curl + KVM
│   ├── fetch-image.sh    # downloads the base cloud image
│   ├── build-seed.sh     # builds seed.iso from cloud-init/
│   ├── create-disk.sh    # creates the qcow2 overlay disk
│   ├── run-vm.sh         # boots QEMU
│   ├── clean.sh          # removes generated artifacts
│   └── README.md            # details for each step
├── build-seed.sh            # back-compat wrapper -> build-seed.sh
├── run-qemu.sh              # orchestrator: runs 01 -> 05 in order
├── Makefile                 # `make run`, `make ssh`, `make stop`, ...
└── README.md
```

## Requirements

On Debian/Ubuntu:

```bash
sudo apt update
sudo apt install -y qemu-system-x86 qemu-utils cloud-image-utils curl
# Optional, for KVM acceleration:
sudo apt install -y qemu-kvm
sudo usermod -aG kvm "$USER"   # then log out / back in
```

If `cloud-image-utils` (which provides `cloud-localds`) is unavailable,
`build-seed.sh` falls back to `genisoimage`, `mkisofs`, or `xorriso`.

## Quick start

With `make` (recommended):

```bash
make            # full pipeline: deps -> fetch -> seed -> disk -> run (background, GUI)
make status     # see whether the VM is running and where its files live
make ssh        # ssh ubuntu@localhost (port 2222)
make serial     # tail -f the serial console log
make stop       # stop the VM
make clean      # remove seed + overlay (keep the base image)
make help       # full list of targets
```

Or directly via the scripts:

```bash
chmod +x run-qemu.sh build-seed.sh scripts/*.sh
./run-qemu.sh
```

### Where things are stored

All generated artifacts (downloaded base image, qcow2 overlay, `seed.iso`,
`vm.pid`, `vm-serial.log`) live in a **per-user working directory**:

```
/var/tmp/$USER/working/   (mode 0700, files mode 0600)
├── images/
│   ├── ubuntu-22.base.qcow2
│   └── ubuntu-22.vm.qcow2
├── seed.iso
├── vm.pid
└── vm-serial.log
```

`/var/tmp` is used instead of `/tmp` so the cached image and the VM disk
survive a host reboot. Override the location with `WORKDIR=/some/path`:

```bash
WORKDIR=$HOME/.cache/qemu-init make run
```

On the first run this will:

1. Check dependencies (`check-deps.sh`)
2. Download `jammy-server-cloudimg-amd64.img` into `./images/` (`fetch-image.sh`)
3. Build `seed.iso` from `cloud-init/` (`build-seed.sh`)
4. Create a qcow2 overlay so the base image stays clean (`create-disk.sh`)
5. Boot QEMU (`run-vm.sh`): a QEMU **GUI window pops up**, but the VM is
   **detached from your terminal** — no boot logs are printed to stdout and
   the launcher returns immediately (QEMU is daemonized).

When the VM is up:

```bash
ssh -Ap 2222 dev@localhost
# password: ubuntu  (defined in cloud-init/user-data) the A is for sharing the priv keys with ssh agent for git clone
```

Useful while it boots:

```bash
tail -f vm-serial.log          # watch the serial console (boot messages)
kill "$(cat vm.pid)"           # stop the VM (or just close the QEMU window)
```

If you'd rather attach the serial console to your terminal (old behaviour),
run with `VM_FOREGROUND=1`:

```bash
VM_FOREGROUND=1 ./run-qemu.sh
# exit the serial console with Ctrl-a then x
```

For a true headless run (no GUI window at all), set `VM_HEADLESS=1`. You can
combine the two:

```bash
VM_HEADLESS=1 ./run-qemu.sh                  # background, no window, ssh only
VM_HEADLESS=1 VM_FOREGROUND=1 ./run-qemu.sh  # serial console in this terminal
```

## Run a single step

Every step under `scripts/` is independent:

```bash
bash scripts/check-deps.sh
bash scripts/fetch-image.sh
bash scripts/build-seed.sh
bash scripts/create-disk.sh
bash scripts/run-vm.sh
```

`./run-qemu.sh --no-run` does everything except the final QEMU boot.

## Reset

```bash
bash scripts/clean.sh           # remove seed.iso + overlay disk
bash scripts/clean.sh --seed    # only seed.iso
bash scripts/clean.sh --vm      # only the overlay disk
bash scripts/clean.sh --all     # also the downloaded base image
```

Cloud-init only runs on the **first** boot of a given instance-id, so to
re-apply changes to `cloud-init/user-data` you typically need to rebuild the
seed and recreate the overlay:

```bash
bash scripts/clean.sh   # then:
./run-qemu.sh
```

## Customizing

- Change the user / password / SSH key in `cloud-init/user-data`.
  To generate a password hash:
  ```bash
  mkpasswd --method=SHA-512 --rounds=4096   # from the `whois` package
  ```
- Change the distro/image and resources via environment variables:
  ```bash
  DISTRO_NAME=debian-12 \
  IMG_URL=https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2 \
  VM_MEM=4096 VM_CPUS=4 VM_DISK_SIZE=20G SSH_PORT=2223 \
  ./run-qemu.sh
  ```

All tunables live in `scripts/config.sh`.
