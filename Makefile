
SHELL          := /bin/bash
.SHELLFLAGS    := -eu -o pipefail -c
.DEFAULT_GOAL  := all
.ONESHELL:

SCRIPTS_DIR := scripts

# ---------------------------------------------------------------------------
# Optional SSH public key injection
# ---------------------------------------------------------------------------
# PUBKEY defaults to the first existing key file among the common candidates
# in $HOME/.ssh. To disable auto-injection: `make run PUBKEY=`.
# To inject an inline key string: `make run SSH_PUBKEY="ssh-ed25519 AAAA..."`.
PUBKEY ?= $(firstword $(wildcard \
    $(HOME)/.ssh/id_ed25519.pub \
    $(HOME)/.ssh/id_rsa.pub \
    $(HOME)/.ssh/id_ecdsa.pub))

# Build the env var prefix passed to the key-injection step. If the user
# provided SSH_PUBKEY=... on the command line, that wins. Otherwise we point
# SSH_PUBKEY_FILE at PUBKEY (if any). This only affects the staged init file
# produced by inject-key.sh — the seed build (build-seed.sh) is never
# given the key directly.
ifneq ($(strip $(SSH_PUBKEY)),)
    INJECT_ENV := SSH_PUBKEY="$(SSH_PUBKEY)"
else ifneq ($(strip $(PUBKEY)),)
    INJECT_ENV := SSH_PUBKEY_FILE="$(PUBKEY)"
else
    INJECT_ENV :=
endif


define _conf
$$(bash -c 'source $(SCRIPTS_DIR)/config.sh >/dev/null && echo $$$(1)')
endef

WORKDIR_VAL      := $(shell bash -c 'source $(SCRIPTS_DIR)/config.sh >/dev/null && echo $$WORKDIR')
VM_PID_FILE_VAL  := $(shell bash -c 'source $(SCRIPTS_DIR)/config.sh >/dev/null && echo $$VM_PID_FILE')
VM_SERIAL_LOG_VAL := $(shell bash -c 'source $(SCRIPTS_DIR)/config.sh >/dev/null && echo $$VM_SERIAL_LOG')
SSH_PORT_VAL     := $(shell bash -c 'source $(SCRIPTS_DIR)/config.sh >/dev/null && echo $$SSH_PORT')

.PHONY: all help prepare deps fetch inject-key seed disk run run-fg run-headless \
        ssh serial stop status \
        clean clean-seed clean-vm clean-all purge

all: run

help:
	@sed -n '1,/^# All tunables/p' Makefile | sed 's/^# \{0,1\}//'

prepare:
	@bash run-qemu.sh --no-run

deps:
	@bash $(SCRIPTS_DIR)/check-deps.sh

fetch: deps
	@bash $(SCRIPTS_DIR)/fetch-image.sh

# Stage cloud-init/user-data into the working directory, optionally
# injecting an extra SSH public key. This step ONLY affects the init file;
# it never modifies cloud-init/user-data on disk and never touches seed.iso.
inject-key:
	@$(INJECT_ENV) bash $(SCRIPTS_DIR)/inject-key.sh

seed: inject-key
	@bash $(SCRIPTS_DIR)/build-seed.sh

disk: fetch
	@bash $(SCRIPTS_DIR)/create-disk.sh

run: deps fetch inject-key seed disk
	@bash $(SCRIPTS_DIR)/run-vm.sh

run-fg: deps fetch inject-key seed disk
	@VM_FOREGROUND=1 bash $(SCRIPTS_DIR)/run-vm.sh

run-headless: deps fetch inject-key seed disk
	@VM_HEADLESS=1 bash $(SCRIPTS_DIR)/run-vm.sh

ssh:
	@ssh -p $(SSH_PORT_VAL) \
	     -o StrictHostKeyChecking=no \
	     -o UserKnownHostsFile=/dev/null \
	     ubuntu@localhost

serial:
	@if [[ ! -f "$(VM_SERIAL_LOG_VAL)" ]]; then \
	    echo "no serial log yet at $(VM_SERIAL_LOG_VAL)"; exit 1; \
	fi; \
	tail -F "$(VM_SERIAL_LOG_VAL)"

stop:
	@if [[ -f "$(VM_PID_FILE_VAL)" ]] && kill -0 "$$(cat $(VM_PID_FILE_VAL))" 2>/dev/null; then \
	    pid="$$(cat $(VM_PID_FILE_VAL))"; \
	    echo "stopping VM (PID $$pid)"; \
	    kill "$$pid"; \
	    rm -f "$(VM_PID_FILE_VAL)"; \
	else \
	    echo "no VM running"; \
	fi

status:
	@echo "workdir : $(WORKDIR_VAL)"; \
	echo "pidfile : $(VM_PID_FILE_VAL)"; \
	echo "serial  : $(VM_SERIAL_LOG_VAL)"; \
	echo "ssh     : ssh -Ap $(SSH_PORT_VAL) ubuntu@localhost"; \
	if [[ -f "$(VM_PID_FILE_VAL)" ]] && kill -0 "$$(cat $(VM_PID_FILE_VAL))" 2>/dev/null; then \
	    echo "status  : running (PID $$(cat $(VM_PID_FILE_VAL)))"; \
	else \
	    echo "status  : not running"; \
	fi

clean:
	@bash $(SCRIPTS_DIR)/clean.sh

clean-seed:
	@bash $(SCRIPTS_DIR)/clean.sh --seed

clean-vm:
	@bash $(SCRIPTS_DIR)/clean.sh --vm

clean-all:
	@bash $(SCRIPTS_DIR)/clean.sh --all

purge:
	@bash $(SCRIPTS_DIR)/clean.sh --purge
