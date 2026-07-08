# AGENTS.md

Repository for spinning up a disposable Fedora CoreOS VM in QEMU, configured end-to-end
through KCL (`*.k`) -> butane (`config.bu`) -> ignition (`config.ign`). There is no
application code, no tests, no lint, no build step — only a `task` (go-task) Taskfile and
KCL config files.

## Running tasks

The Taskfile has a non-default name: **`taskfile.qemu.yaml`**. Every `task` invocation must
pass `-t taskfile.qemu.yaml`, e.g. `task -t taskfile.qemu.yaml up`. Tasks internally
re-invoke themselves the same way (see `launch-vm`'s `status:`), so do not rename it.

Public tasks:
- `up` — full lifecycle: download Fedora CoreOS qcow2, verify GPG + sha256, build butane/ignition, `sudo`-launch QEMU, wait for SSH, wait for `install-system-pkgs.service`, wait for `run-topgrade.service`, reboot if staged, attach SSH.
- `down` — stop VM, clean beszel hub entry, delete workspace + generated files.
- `status` / `ssh` / `logs` / `mgmt` (cockpit) / `stop` — operating tasks.
- `check` — verifies host deps are present (qemu, butane, **shasum/sha256sum**, jq, **kcl**, curl, gpgv). Run first when debugging environment issues.

`up` launches QEMU via `sudo` — host must allow passwordless `sudo qemu` (or prompt interactively). The VM is reached over mDNS at `<uuid>.local` (the `.uuid` file in repo root is the identity; do not delete it between runs or `up` will regenerate it and orphan the old workspace).

## Config flow

1. User writes `config.k` at repo root (gitignored; copy `exemple.config.k` — note the French spelling — as a template). It must `import .schema as schema` and bind `config = schema.Qemu { ... }`.
2. `kcl_dataset` Taskfile var runs `kcl config.k --format json` with several `--argument`s derived from the host: `taskfile_dir`, `qemu_butane_user_name`, `qemu_butane_user_id`, `qemu_host_arch`, `qemu_host_os`, `github_token`. `schema.k` reads these via `option(...)`. The result is re-parsed with `fromJson` into many `qemu_*` vars — keep this shape stable when editing the schema. (A historical `cache: true` key was removed: it was a no-op on older go-task and rejected by go-task ≥ 3.34 — do not re-add it.)
3. `build-butane`: `kcl butane-render.k --path_selector butane > config.bu`. `butane-render.k` imports both `schema.k` and `config.k`, so changes to either invalidate this step (declared in `sources:`).
4. `build-ignition`: `butane --strict config.bu --output config.ign`. The `.ign` is passed to QEMU via `-fw_cfg name=opt/com.coreos/config`.

Generated artifacts (all gitignored): `config.k`, `config.bu`, `config.ign`, `.uuid`, `.task/*`. The VM workspace (`~/.qemu/<uuid>/`) holds the qcow2, pid, log, and downloaded Fedora GPG key — not under the repo.

## Editing the schema

- `schema.k` is the single source of truth for VM shape (hardware, OS version/checksums, qemu command line, butane contents). It is host-aware: detects `darwin` vs `linux` to choose `hvf` vs `kvm` and `vmnet-shared` vs `user` networking, and `aarch64` to add the EDK2 pflash drive. Honor these conditionals when adding command-line options.
- EDK2 pflash path (`schema.k` `_edk2_path`) is resolved by scanning a list of candidate paths (`/opt/homebrew/share/qemu/edk2-aarch64-code.fd`, `/usr/share/qemu/edk2-aarch64-code.fd`, `/usr/share/AAVMF/AAVMF_CODE.fd`) and picking the first that exists. Override via `option("qemu_edk2_path")` if needed. Only relevant on `aarch64`.
- SHA-256 verification uses the Taskfile var `shasum_cmd` (`command -v shasum || command -v sha256sum`), so it works on macOS (`shasum`, Perl) and Linux (`sha256sum`, coreutils) without code changes. Do not hardcode `shasum` in new tasks.
- `templates.k` holds lambda strings (repo files, hostname, sudoers, systemd unit bodies) consumed by the schema. New file/unit contents belong here, not inline in `schema.k`.
- `GITHUB_TOKEN` is read from env and threaded through `--argument github_token='{{ env "GITHUB_TOKEN" }}'`; `config.butane.github.token` overrides it. Same pattern (option with env fallback) is used for beszel credentials.
- Fedora CoreOS version + checksums are hard-coded in `schema.k` (`_os_version`, `_checksum_x86_64`, `_checksum_aarch64`). Bumping the OS means updating both the version string and the matching sha256, or `image-validation` will fail.

## Conventions

- KCL files use the `.k` extension. `exemple.config.k` uses French spelling intentionally — do not "fix" it; existing docs/import paths may reference it.
- Logging in tasks goes through `scripts/utils.sh` `_log` / `_error_handler`, invoked via the Taskfile vars `{{ .log }}` and `{{ .error }}`. New tasks should use these instead of bare `echo` to keep the Nord-colored output consistent.
- Most internal tasks are `internal: true` + `silent: true` with a `status:` check so they are idempotent — `up` can be re-run safely and will skip already-done steps.
