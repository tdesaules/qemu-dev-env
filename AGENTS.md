# AGENTS.md

Repository for spinning up a disposable Fedora CoreOS VM in QEMU, configured end-to-end
through KCL (`*.k`) -> butane (`config.bu`) -> ignition (`config.ign`). There is no
application code, no tests, no lint, no build step — only a `task` (go-task) Taskfile and
KCL config files.

## Git workflow

- **Always commit changes locally** following conventional commits. Do not leave the working tree dirty after completing a task.
- **Never push.** `git push` (and any remote-syncing operation) is performed manually by the owner.

## Running tasks

The Taskfile has a non-default name: **`taskfile.qemu.yaml`**. Every `task` invocation must
pass `-t taskfile.qemu.yaml`, e.g. `task -t taskfile.qemu.yaml up`. Tasks internally
re-invoke themselves the same way (see `launch-vm`'s `status:`), so do not rename it.

Public tasks:
- `up` — full lifecycle: `check` deps → download Fedora CoreOS qcow2 → verify GPG + sha256 → build butane/ignition → activate bridge (Linux) → `sudo`-launch QEMU → wait for SSH → wait for `install-system-pkgs.service` → wait for `run-topgrade.service` → reboot if staged → attach SSH. Has `deps: [check]` so deps are verified first.
- `down` — stop VM, deactivate bridge (Linux), clean beszel hub entry, delete workspace + generated files.
- `status` / `ssh` / `logs` / `mgmt` (cockpit) / `stop` — operating tasks.
- `check` — verifies host deps are present (qemu, butane, **shasum/sha256sum**, jq, **kcl**, curl, gpgv). Run first when debugging environment issues.

`up` launches QEMU via `sudo` — host must allow passwordless `sudo qemu` (or prompt interactively). The VM is reached over mDNS at `<uuid>.local` (the `.uuid` file in repo root is the identity; do not delete it between runs or `up` will regenerate it and orphan the old workspace).

## Config flow

1. User writes `config.k` at repo root (gitignored; copy `exemple.config.k` — note the French spelling — as a template). It must `import .schema as schema` and bind `config = schema.Qemu { ... }`.
2. `kcl_dataset` Taskfile var runs `kcl config.k --format json` with several `--argument`s derived from the host: `taskfile_dir`, `qemu_butane_user_name`, `qemu_butane_user_id`, `qemu_host_arch`, `qemu_host_os`, `github_token`. `schema.k` reads these via `option(...)`. The result is re-parsed with `fromJson` into many `qemu_*` vars — keep this shape stable when editing the schema. (A historical `cache: true` key was removed: it was a no-op on older go-task and rejected by go-task ≥ 3.34 — do not re-add it.)
3. `build-butane`: `kcl butane-render.k --path_selector butane > config.bu`. `butane-render.k` imports both `schema.k` and `config.k`, so changes to either invalidate this step (declared in `sources:`). Additional `--argument`s passed at this stage: `beszel_token` (auto-fetched from hub API), `beszel_key` (from env/gopass).
4. `build-ignition`: `butane --strict config.bu --output config.ign`. The `.ign` is passed to QEMU via `-fw_cfg name=opt/com.coreos/config`.

Generated artifacts (all gitignored): `config.k`, `config.bu`, `config.ign`, `.uuid`, `.task/*`. The VM workspace (`~/.qemu/<uuid>/`) holds the qcow2, pid, log, and downloaded Fedora GPG key — not under the repo.

## Cross-platform (macOS + Linux)

The schema is host-aware via `_host_os` and `_os_arch` (from `uname`). Key conditionals:

| Aspect | macOS (darwin) | Linux |
|---|---|---|
| Binary | `qemu-system-aarch64` (M-series) | `qemu-system-x86_64` |
| Machine | `virt,highmem=off` (aarch64) | `q35,vmport=off` (x86_64) |
| Accel | `hvf` | `kvm` |
| Network | `vmnet-shared` (mDNS works natively) | `bridge,br=br-qemu` (requires NM bridge + firewalld) |
| I/O | `cache=unsafe` | `cache=unsafe,aio=io_uring` |
| EDK2 pflash | `/opt/homebrew/share/qemu/edk2-aarch64-code.fd` | `/usr/share/AAVMF/AAVMF_CODE.fd` (Fedora) |

- **Linux networking**: uses a NetworkManager bridge `br-qemu` (`ipv4.method shared` — provides DHCP + NAT + mDNS). The bridge profile + `/etc/qemu/bridge.conf` (`allow br-qemu`) + firewalld rules (`mdns` service + `8090/tcp` port in `nm-shared` zone) are managed by chezmoi, not by this repo. Tasks `create-bridge` / `delete-bridge` activate/deactivate the bridge connection (no-op on macOS via `status:` short-circuit `[ "{{ .qemu_host_os }}" != "linux" ]`).
- **EDK2 pflash** (`schema.k` `_edk2_path`): resolved by scanning candidate paths and picking the first that exists. Override via `option("qemu_edk2_path")`. Only relevant on `aarch64`.
- **SHA-256 verification**: uses the Taskfile var `shasum_cmd` (`command -v shasum || command -v sha256sum`). Do not hardcode `shasum` in new tasks.
- **`ConditionVirtualization`**: all systemd units in `templates.k` use `ConditionVirtualization=vm` (not `qemu` — `qemu` only matches TCG emulation, not KVM/hvf).

## Editing the schema

- `schema.k` is the single source of truth for VM shape (hardware, OS version/checksums, qemu command line, butane contents). Honor the host-aware conditionals when adding command-line options.
- `templates.k` holds lambda strings (repo files, hostname, sudoers, systemd unit bodies) consumed by the schema. New file/unit contents belong here, not inline in `schema.k`.
- Fedora CoreOS version + checksums are hard-coded in `schema.k` (`_os_version`, `_checksum_x86_64`, `_checksum_aarch64`). Bumping the OS means updating both the version string and the matching sha256, or `image-validation` will fail.
- `butane-render.k` moves the default `core` user to UID 2000 to avoid conflicts with the host user's UID (1000 on Linux, 501 on macOS). Do not remove this — Ignition will fail with `useradd: UID 1000 is not unique`.

## Copies and custom files

The `Butane` schema provides three mechanisms to add files to the VM at ignition provisioning time:

### `custom_files` — inline content files

Files with inline content defined directly in `config.k`. Follows the same pattern as `custom_pkgs` and `custom_mise_tools`:

```kcl
butane = schema.Butane {
    custom_files = [
        {
            path = "/var/home/${option('qemu_butane_user_name')}/hello-files"
            mode = 420
            contents.inline = "hello files\n"
        }
    ]
}
```

### `copies` / `custom_copies` — host files baked into ignition

Files read from the host filesystem at build time (KCL `file.read()`) and baked into the ignition config as inline butane files. The VM gets its own writable copies on the local filesystem — no 9p mount needed. Changes on the host require a VM rebuild (`down` + `up`) to take effect.

```kcl
butane = schema.Butane {
    custom_copies = [
        {
            source = "${option('HOME')}/.config/some-tool/config.toml"
            path = "/var/home/${option('qemu_butane_user_name')}/.config/some-tool/config.toml"
        }
    ]
}
```

The `ButaneCopy` schema:
- `source` — host path (read via `file.read()` at build time)
- `path` — VM path
- `mode` — file permissions (default: `420` = 0644)
- `user` / `group` — optional, default to the butane user

### `default_copies` — built-in copies

The schema automatically copies opencode config from the host if they exist:

| Source (host) | Destination (VM) | Mode | Purpose |
|---|---|---|---|
| `~/.config/opencode/opencode.json` | `~/.config/opencode/opencode.json` | 0644 | opencode config |
| `~/.config/opencode/tui.json` | `~/.config/opencode/tui.json` | 0644 | TUI config |
| `~/.local/share/opencode/auth.json` | `~/.local/share/opencode/auth.json` | 0600 | opencode auth |

`_has_opencode_config` checks for any of these files. The comprehension in `files` only includes copies where `file.exists(c.source)` is true, so missing files are silently skipped.

The `copies` field combines `default_copies + custom_copies`, following the same pattern as `default_pkgs` / `custom_pkgs` and `default_mise_tools` / `custom_mise_tools`.

## Environment variables

The Taskfile reads credentials from env vars with `mise env --json` fallback (non-interactive shells don't source `mise activate`) and `gopass` as last resort:

| Var | mise key | gopass path | Default |
|---|---|---|---|
| `GITHUB_TOKEN` | `GITHUB_TOKEN` | — | — |
| `BESZEL_USER` | `BESZEL_USER` | `beszel/username` | `local@home.lan` |
| `BESZEL_PASSWORD` | `BESZEL_PASSWORD` | `beszel/password` | `local@home.lan` |
| `BESZEL_KEY` | `BESZEL_KEY` | `beszel/key` | (empty) |

Pattern: `echo "${ENV_VAR:-$(mise env --json | jq -r '.ENV_VAR // empty' || gopass show -o path || echo default)}"`.

## Beszel integration

The VM runs a `beszel-agent` container (podman quadlet) in **WebSocket mode** (no SSH):

- `DISABLE_SSH=true` — disables the agent's SSH server (KEY still required by the binary to start).
- `KEY` — the hub's SSH public key, from `BESZEL_KEY` env var (set via mise/chezmoi).
- `TOKEN` — universal API token, auto-fetched from the hub via `_superusers` auth (not `users` — the password was changed on the admin account). If no token exists, one is created automatically.
- `HUB_URL` — from `config.butane.beszel.url` (e.g. `http://10.10.10.1:8090` on Linux bridge, `http://localhost:8090` on macOS).
- `SYSTEM_NAME` — the VM's UUID (without `.local`). The `delete-beszel-system` task matches by this name.

The hub must be reachable from the VM. On Linux, this requires `PublishPort=0.0.0.0:8090:8090` on the beszel container + port `8090/tcp` in the `nm-shared` firewalld zone (both managed by chezmoi).

`config.k` only needs `beszel = { url = "..." }` — credentials and token are automatic.

## Conventions

- KCL files use the `.k` extension. `exemple.config.k` uses French spelling intentionally — do not "fix" it; existing docs/import paths may reference it.
- Logging in tasks goes through `scripts/utils.sh` `_log` / `_error_handler`, invoked via the Taskfile vars `{{ .log }}` and `{{ .error }}`. New tasks should use these instead of bare `echo` to keep the Nord-colored output consistent.
- Most internal tasks are `internal: true` + `silent: true` with a `status:` check so they are idempotent — `up` can be re-run safely and will skip already-done steps.
- `config.k` is gitignored and user-owned. Use `option('qemu_butane_user_name')` (not `_usr` — that was an undefined variable bug in the original template) for string interpolation of the username.
