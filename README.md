# QEMU-DEV-ENV

Disposable Fedora CoreOS VM in QEMU, configured end-to-end through KCL → butane → ignition.
Cross-platform (macOS + Linux). No application code — only a `task` (go-task) Taskfile and KCL config files.

## Prerequisites

### Host dependencies

| Tool | macOS | Linux |
|---|---|---|
| `qemu-system-*` | `brew install qemu` | `dnf install qemu-system-x86` |
| `butane` | `brew install butane` | via mise or download from [GitHub](https://github.com/coreos/butane/releases) |
| `kcl` | `brew install kcl-lang/tap/kcl` | via mise |
| `jq` | `brew install jq` | via mise |
| `curl` / `gpgv` | pre-installed | pre-installed |
| `shasum` / `sha256sum` | pre-installed (Perl) | `sha256sum` (coreutils) |
| `task` (go-task) | `brew install go-task` | via mise |

Verify: `task -t taskfile.qemu.yaml check`

### Environment variables

| Var | Purpose | Source |
|---|---|---|
| `GITHUB_TOKEN` | mise tool installs (avoids API rate limits) | env / mise |
| `BESZEL_USER` | Beszel hub admin email | mise / gopass |
| `BESZEL_PASSWORD` | Beszel hub admin password | mise / gopass |
| `BESZEL_KEY` | Beszel hub SSH public key | mise / gopass |

### Linux networking (bridge)

Linux uses a NetworkManager bridge `br-qemu` (`ipv4.method shared`) for VM networking with mDNS support. The bridge profile, `/etc/qemu/bridge.conf`, and firewalld rules are managed by [chezmoi](https://www.chezmoi.io), not by this repo.

### sudo

`up` launches QEMU via `sudo` — host must allow passwordless `sudo qemu`.

## Quick start

```bash
# 1. Copy the example config (note: French spelling "exemple")
cp exemple.config.k config.k
# Edit config.k: set beszel.url, custom packages, files, units, etc.

# 2. Verify dependencies
task -t taskfile.qemu.yaml check

# 3. Start the VM (downloads image, builds config, launches QEMU, waits for SSH)
task -t taskfile.qemu.yaml up

# 4. Connect
task -t taskfile.qemu.yaml ssh

# 5. Destroy when done
task -t taskfile.qemu.yaml down
```

## Tasks

| Task | Description |
|---|---|
| `up` | Full lifecycle: check → download → verify → build → bridge → launch → wait → SSH |
| `down` | Stop VM, deactivate bridge, clean beszel hub, delete workspace + generated files |
| `status` | VM status (JSON) |
| `ssh` | SSH into the VM |
| `logs` | QEMU serial log |
| `mgmt` | Open Cockpit web UI |
| `stop` | Stop the VM without destroying |
| `check` | Verify host dependencies |

All tasks require `-t taskfile.qemu.yaml`.

## Config flow

```
config.k (user)          → KCL schema → JSON (kcl_dataset var)
butane-render.k          → config.bu (butane YAML)
butane --strict          → config.ign (ignition JSON)
QEMU -fw_cfg             → VM boots with ignition config
```

### `config.k`

Gitignored, user-owned. Copy `exemple.config.k` as a template. Must:
- `import .schema as schema`
- Bind `config = schema.Qemu { ... }`
- Use `option('qemu_butane_user_name')` for username interpolation (not `_usr`)

### Generated artifacts (all gitignored)

`config.k`, `config.bu`, `config.ign`, `.uuid`, `.task/*`

### VM workspace

`~/.qemu/<uuid>/` — holds the qcow2, pid, log, and Fedora GPG key. Not under the repo.

The `.uuid` file in repo root is the VM identity. Do not delete it between runs or `up` will regenerate it and orphan the old workspace.

## Cross-platform

| Aspect | macOS (M-series) | Linux (x86_64) |
|---|---|---|
| Binary | `qemu-system-aarch64` | `qemu-system-x86_64` |
| Machine | `virt,highmem=off` | `q35,vmport=off` |
| Accel | `hvf` | `kvm` |
| Network | `vmnet-shared` (mDNS native) | `bridge,br=br-qemu` (NM shared) |
| I/O | `cache=unsafe` | `cache=unsafe,aio=io_uring` |
| EDK2 | `/opt/homebrew/.../edk2-aarch64-code.fd` | `/usr/share/AAVMF/AAVMF_CODE.fd` |

## Beszel integration

The VM runs a `beszel-agent` container (podman quadlet) in WebSocket mode:

- `DISABLE_SSH=true` — no SSH server on the agent
- `TOKEN` — universal API token, auto-fetched from the hub
- `HUB_URL` — from `config.butane.beszel.url`
- `SYSTEM_NAME` — VM UUID (used by `down` for cleanup)

`config.k` only needs `beszel = { url = "..." }` — credentials and token are automatic via `BESZEL_USER` / `BESZEL_PASSWORD` / `BESZEL_KEY` env vars.

## Files

| File | Purpose |
|---|---|
| `taskfile.qemu.yaml` | go-task Taskfile (non-default name) |
| `schema.k` | KCL schema: VM hardware, QEMU command, butane contents |
| `templates.k` | KCL lambda strings: repo files, systemd units, sudoers |
| `butane-render.k` | KCL entrypoint: merges schema + config → butane YAML |
| `exemple.config.k` | Example config template (French spelling intentional) |
| `scripts/utils.sh` | Nord-colored logging (`_log` / `_error_handler`) |
| `config.k` | User config (gitignored) |
| `AGENTS.md` | Agent instructions for OpenCode sessions |
