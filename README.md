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
# Edit config.k: set beszel.url, custom packages, files, copies, units, etc.

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

## `config.k` — complete reference

`config.k` is gitignored and user-owned. Copy `exemple.config.k` as a template:

```bash
cp exemple.config.k config.k
```

Every `config.k` must:

1. `import .schema as schema`
2. Bind `config = schema.Qemu { ... }`
3. Use `option('qemu_butane_user_name')` for username interpolation (not `_usr`)

### Minimal config

```kcl
import .schema as schema

config = schema.Qemu {
    butane = schema.Butane {
        github = {
            token = option("github_token")
        }
    }
}
```

This gives you a VM with all defaults: 1 vCPU, 1024 MB RAM, 16 GB disk, default packages, default mise tools, and no Beszel monitoring.

### Full config with all options

```kcl
import .schema as schema

config = schema.Qemu {
    hardware = schema.Hardware {
        cpu = 2
        memory = schema.Memory {
            size = 2048
            unit = "M"
        }
        disk = schema.Disk {
            size = 32
            unit = "G"
        }
    }
    butane = schema.Butane {
        github = {
            token = option("github_token")
        }
        custom_pkgs = [
            "htop"
            "tmux"
        ]
        custom_mise_tools = {
            "go" = "latest"
            "node" = "20"
        }
        custom_files = [
            {
                path = "/var/home/${option('qemu_butane_user_name')}/hello.txt"
                mode = 420
                contents.inline = "hello world\n"
            }
        ]
        custom_copies = [
            {
                source = "${file.read_env('HOME')}/.config/some-tool/config.toml"
                path = "/var/home/${option('qemu_butane_user_name')}/.config/some-tool/config.toml"
            }
        ]
        beszel = {
            url = "http://10.10.10.1:8090"
        }
        units += [
            {
                name = "my-service.service"
                enabled = True
                contents = """\
[Unit]
Description=My Service
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/echo "hello"

[Install]
WantedBy=multi-user.target
"""
            }
        ]
    }
}
```

---

### Hardware

```kcl
hardware = schema.Hardware {
    cpu = 2                    # number of vCPUs (default: 1)
    memory = schema.Memory {
        size = 2048            # default: 1024
        unit = "M"             # "M" or "G" (default: "M")
    }
    disk = schema.Disk {
        size = 32               # default: 16
        unit = "G"              # (default: "G")
    }
}
```

All fields are optional — omit `hardware` entirely to use defaults (1 vCPU, 1024 MB RAM, 16 GB disk).

---

### Packages (`custom_pkgs`)

Additional RPM packages installed via `rpm-ostree install --apply-live` at boot by the `install-system-pkgs.service` unit. Merged with the default package list.

```kcl
butane = schema.Butane {
    custom_pkgs = [
        "htop"
        "tmux"
        "neovim"
        "ripgrep"
    ]
}
```

**Default packages** (always installed):

| Package | Purpose |
|---|---|
| `git` | Version control |
| `terra-release` | [Terra](https://github.com/FyraLabs/terra) third-party repo (provides `topgrade`, `mise`, etc.) |
| `topgrade` | System + user tool updates |
| `mise` | Runtime version manager |
| `cockpit-ws` | Cockpit web service |
| `cockpit-system` | Cockpit system module |
| `cockpit-ostree` | Cockpit ostree module |
| `cockpit-podman` | Cockpit podman module |

---

### Mise tools (`custom_mise_tools`)

Additional [mise](https://mise.jdx.dev/) tools, merged with defaults and written to `~/.config/mise/config.toml`. Installed at boot by `run-topgrade.service` (which runs `mise install --yes`).

```kcl
butane = schema.Butane {
    custom_mise_tools = {
        "go" = "latest"
        "node" = "20"
        "python" = "3.12"
        "rust" = "latest"
    }
}
```

**Default mise tools** (always installed):

| Tool | Version |
|---|---|
| `github:starship/starship` | `latest` |
| `github:fastfetch-cli/fastfetch` | `latest` |

---

### Custom files (`custom_files`)

Files with inline content defined directly in `config.k`. Created at ignition provisioning time.

```kcl
butane = schema.Butane {
    custom_files = [
        # Simple text file in the user's home
        {
            path = "/var/home/${option('qemu_butane_user_name')}/hello.txt"
            mode = 420                          # 0644 (rw-r--r--)
            contents.inline = "hello world\n"
        }
        # Podman quadlet container
        {
            path = "/etc/containers/systemd/my-app.container"
            mode = 420
            contents.inline = """\
[Container]
ContainerName=my-app
Image=docker.io/library/nginx:latest
PublishPort=8080:80

[Install]
WantedBy=multi-user.target
"""
        }
        # Root-owned config file
        {
            path = "/etc/my-app/config.conf"
            mode = 288                          # 0440 (r--r-----)
            user = { name = "root" }
            group = { name = "root" }
            contents.inline = "key=value\n"
        }
    ]
}
```

**`ButaneFile` schema:**

| Field | Type | Default | Description |
|---|---|---|---|
| `path` | `str` | — | Absolute path in the VM |
| `mode` | `int` | — | File mode in **decimal** (see [mode reference](#file-modes)) |
| `overwrite` | `bool` | `True` | Overwrite if file exists |
| `user` | `{ name: str }` | butane user | File owner (use `{ name = "root" }` for root) |
| `group` | `{ name: str }` | butane group | File group |
| `contents.inline` | `str` | — | File content (string) |

---

### Custom copies (`custom_copies`)

Host files read at **build time** via `file.read()` and baked into the ignition config as inline butane files. The VM gets its own writable copy — no 9p mount needed. Changes on the host require a VM rebuild (`down` + `up`) to take effect.

```kcl
butane = schema.Butane {
    custom_copies = [
        # Copy a config file from the host
        {
            source = "${file.read_env('HOME')}/.config/some-tool/config.toml"
            path = "/var/home/${option('qemu_butane_user_name')}/.config/some-tool/config.toml"
            mode = 420                          # 0644 (default)
        }
        # Copy with custom owner
        {
            source = "/etc/some-root-config.conf"
            path = "/etc/some-root-config.conf"
            mode = 288                          # 0440
            user = { name = "root" }
            group = { name = "root" }
        }
    ]
}
```

**`ButaneCopy` schema:**

| Field | Type | Default | Description |
|---|---|---|---|
| `source` | `str` | — | Host filesystem path (read at build time) |
| `path` | `str` | — | VM path |
| `mode` | `int` | `420` (0644) | File mode in decimal |
| `user` | `{ name: str }` | butane user | File owner |
| `group` | `{ name: str }` | butane group | File group |

Missing source files are silently skipped (the comprehension filters on `file.exists(c.source)`).

**Default copies** (automatic, if they exist on the host):

| Source (host) | Destination (VM) | Mode | Purpose |
|---|---|---|---|
| `~/.config/opencode/opencode.json` | `~/.config/opencode/opencode.json` | 0644 | opencode config |
| `~/.config/opencode/tui.json` | `~/.config/opencode/tui.json` | 0644 | TUI config |
| `~/.local/share/opencode/auth.json` | `~/.local/share/opencode/auth.json` | 0600 | opencode auth |

---

### Systemd units (`units +=`)

Append custom systemd units. The `+=` operator adds to the default unit list (which includes `install-system-pkgs.service`, `run-topgrade.service`, 9p mounts, `configure-cockpit.service`, `podman.socket`).

```kcl
butane = schema.Butane {
    units += [
        # Oneshot service that runs at boot
        {
            name = "create-hello.service"
            enabled = True
            contents = """\
[Unit]
Description=Create hello file
After=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/bash -c "echo 'hello' > /var/home/${option('qemu_butane_user_name')}/hello"

[Install]
WantedBy=multi-user.target
"""
        }
        # Podman socket (if not already enabled by default)
        {
            name = "podman.socket"
            enabled = True
        }
    ]
}
```

**`ButaneUnit` schema:**

| Field | Type | Default | Description |
|---|---|---|---|
| `name` | `str` | — | Unit filename (e.g. `my-service.service`) |
| `enabled` | `bool` | `True` | Enable at boot |
| `contents` | `str` | — | Full unit file content (omit for units with no body, like sockets) |

All units use `ConditionVirtualization=vm` (not `qemu` — `qemu` only matches TCG emulation, not KVM/hvf).

---

### Beszel monitoring (`beszel`)

The VM runs a `beszel-agent` container (podman quadlet) in WebSocket mode. Only `url` is required in `config.k` — credentials and token are automatic.

```kcl
butane = schema.Butane {
    beszel = {
        url = "http://10.10.10.1:8090"   # Linux bridge (hub IP)
        # url = "http://localhost:8090"   # macOS
    }
}
```

| Field | Type | Default | Description |
|---|---|---|---|
| `url` | `str` | — | Beszel hub URL reachable from the VM |
| `key` | `str` | `option("beszel_key")` | Hub SSH public key (from `BESZEL_KEY` env var) |
| `token` | `str` | `option("beszel_token")` | Universal API token (auto-fetched from hub) |
| `username` | `str` | `local@home.lan` | Hub admin email (from `BESZEL_USER`) |
| `password` | `str` | `local@home.lan` | Hub admin password (from `BESZEL_PASSWORD`) |

The agent uses:
- `DISABLE_SSH=true` — no SSH server on the agent
- `TOKEN` — auto-fetched from the hub via `_superusers` auth
- `SYSTEM_NAME` — the VM's UUID (without `.local`)

On Linux, the hub must be reachable: requires `PublishPort=0.0.0.0:8090:8090` on the beszel container + port `8090/tcp` in the `nm-shared` firewalld zone (both managed by chezmoi).

---

### GitHub token (`github`)

Used by `mise` for tool installs (avoids GitHub API rate limits) and by `topgrade`. Passed to the VM via the `00-mise.sh` bashrc snippet.

```kcl
butane = schema.Butane {
    github = {
        token = option("github_token")
    }
}
```

If omitted, mise/topgrade will still work but may hit rate limits.

---

### Available `option()` calls

These KCL options are injected by the Taskfile at build time:

| Option | Value | Source |
|---|---|---|
| `option('qemu_butane_user_name')` | lowercased `whoami` | Taskfile var |
| `option('qemu_butane_user_id')` | `id -u` | Taskfile var |
| `option('qemu_host_arch')` | `x86_64` or `aarch64` | `uname -m` |
| `option('qemu_host_os')` | `linux` or `darwin` | `uname -s` |
| `option('github_token')` | GitHub token | `GITHUB_TOKEN` env var |
| `option('beszel_token')` | Beszel API token | auto-fetched from hub |
| `option('beszel_key')` | Beszel SSH key | `BESZEL_KEY` env var |
| `option('taskfile_dir')` | Taskfile directory | `{{ .TASKFILE_DIR }}` |
| `option('qemu_edk2_path')` | EDK2 pflash path | override (aarch64 only) |

Additionally, `file.read_env('HOME')` and `file.read_env('PWD')` give access to the host's home directory and current working directory.

---

### File modes

Butane/Ignition uses **decimal** integers for file modes. Common values:

| Decimal | Octal | Permissions | Typical use |
|---|---|---|---|
| `420` | `0644` | `rw-r--r--` | Regular config files (default) |
| `384` | `0600` | `rw-------` | Secrets (e.g. auth.json) |
| `493` | `0755` | `rwxr-xr-x` | Directories, executables |
| `288` | `0440` | `r--r-----` | Root-readable config (sudoers) |

---

### What's included by default

When you create a VM, these are provisioned automatically (no config needed):

**Users** (from `butane-render.k`):

| User | UID | Groups | Notes |
|---|---|---|---|
| `core` | 2000 | — | Default FCOS user (moved to 2000 to avoid UID conflict with host user) |
| `<your_username>` | host UID | `wheel`, `docker` | Main user, SSH keys from `~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub` |
| `dev` | — | `wheel`, `docker` | Secondary user with password hash |

**9p shared mounts** (host → VM):

| Mount tag | VM path | Source (host) | Mode |
|---|---|---|---|
| `qemu` | `~/.qemu` | `~/.qemu/<uuid>/` (VM workspace) | read-write |
| `workspace` | `~/workspace` | repo directory (`$PWD`) | read-write |
| `starship` | `~/.config/starship` | `~/.config/starship` | read-only (if exists) |

**Systemd units:**

| Unit | Purpose |
|---|---|
| `install-system-pkgs.service` | Installs default + custom RPM packages |
| `run-topgrade.service` | Runs `topgrade` (installs mise tools, updates system) |
| `var-home-<user>-.qemu.{mount,automount}` | 9p mount of VM workspace |
| `var-home-<user>-workspace.{mount,automount}` | 9p mount of repo directory |
| `var-home-<user>-.config-starship.mount` | 9p mount of starship config (if exists) |
| `configure-cockpit.service` | Enables and starts Cockpit |
| `podman.socket` | Podman API socket |

**Files** (key ones):

| Path | Purpose |
|---|---|
| `/etc/zincati/config.d/50-disable-updates.toml` | Disable auto-updates |
| `/etc/yum.repos.d/terra.repo` | Terra third-party repo |
| `/etc/hostname` | `<uuid>.local` |
| `/etc/systemd/resolved.conf.d/mdns.conf` | Enable mDNS |
| `/etc/sudoers.d/<user>` | Passwordless sudo for user |
| `/etc/sudoers.d/dev` | Passwordless sudo for dev user |
| `/etc/polkit-1/rules.d/99-rpmostree-passwordless.rules` | Passwordless rpm-ostree |
| `/etc/selinux/config` | SELinux permissive |
| `~/.config/mise/config.toml` | Mise tools config |
| `~/.config/topgrade.toml` | Topgrade config |
| `~/.bashrc.d/00-mise.sh` | Mise activation + GitHub token |
| `~/.bashrc.d/10-starship.sh` | Starship prompt |
| `~/.bashrc.d/20-fastfetch.sh` | Fastfetch on login |

---

### Tips

- **Rebuild after config changes**: `task -t taskfile.qemu.yaml down && task -t taskfile.qemu.yaml up`
- **Debug failed package install**: `ssh <user>@<uuid>.local 'sudo journalctl -u install-system-pkgs.service'`
- **Debug failed topgrade**: `ssh <user>@<uuid>.local 'sudo journalctl -u run-topgrade.service'`
- **Access Cockpit**: `task -t taskfile.qemu.yaml mgmt` or browse to `https://<uuid>.local:9090`
- **Do not delete `.uuid`**: it's the VM identity. Deleting it orphans the old workspace at `~/.qemu/<uuid>/`.

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
