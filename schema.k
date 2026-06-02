import file
import crypto

schema Qemu:
    uuid: str = file.read("${option('taskfile_dir')}/.uuid").strip() if file.exists("${option('taskfile_dir')}/.uuid") else crypto.uuid()
    workspace: str = "${file.read_env('HOME')}/.qemu/${uuid}"
    os: Os {}
    checksum: Checksum {}
    hardware: Hardware {}
    butane: Butane {}

schema Os:
    name: str = "fedora"
    edition: str = "coreos"
    version: str = "44"
    streams: str = "stable"

schema Checksum:
    x86_64: str = "empty"
    aarch64: str = "empty"

schema Hardware:
    cpu: int = 1
    memory: Memory {}
    disk: Disk {}

schema Memory:
    size: int = 1024
    unit: str = "M"

schema Disk:
    size: int = 16
    unit: str = "G"

schema Butane:
    user: ButaneUser = ButaneUser {}
    hostname: str = option("qemu_butane_hostname") or "qemu-hostname"
    default_pkgs: [str] = ["git", "topgrade", "mise"]
    custom_pkgs: [str] = []
    directories: [ButaneDirectory] = [
        {
            path = "/var/home/${user.name}/.config"
            mode = 493
        }
    ]
    files: [ButaneFile] = [
        {
            path = "/etc/hostname"
            mode = 420
            contents.inline = """\
${hostname}
"""
        }
        {
            path = "/etc/profile.d/terminal-fix.sh"
            mode = 420
            contents.inline = """\
export TERM=linux
export SYSTEMD_PAGER=cat
"""
        }
        {
            path = "/etc/containers/containers.conf"
            mode = 420
            contents.inline = """\
[containers]
netns="host"
dns_servers = ["1.1.1.1", "8.8.8.8"]
mtu = 1450
"""
        }
        {
            path = "/etc/subuid"
            mode = 420
            contents.inline = """\
${user.name}:100000:65536
"""
        }
        {
            path = "/etc/subgid"
            mode = 420
            contents.inline = """\
${user.name}:100000:65536
"""
        }
        {
            path = "/etc/sudoers.d/${user.name}"
            mode = 288
            contents.inline = """\
${user.name} ALL=(ALL) NOPASSWD: ALL
"""
        }
    ] + custom_files
    custom_files: [ButaneFile] = []
    units: [ButaneUnit] = [
        {
            name = "install-system-pkgs.service"
            enabled = True
            contents = """\
[Unit]
Description=Provisioning System Packages
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/bash -c ' \\
    MISSING_PKGS=""; \\
    for PKG in ${" ".join(default_pkgs + custom_pkgs)}; do \\
        if ! rpm -q "\${PKG}" &> /dev/null; then \\
            MISSING_PKGS="\${MISSING_PKGS} \${PKG}"; \\
        fi; \\
    done; \\
    if [ -n "\${MISSING_PKGS}" ]; then \\
        /usr/bin/rpm-ostree install --apply-live --allow-inactive \${MISSING_PKGS}; \\
    fi'

[Install]
WantedBy=multi-user.target
"""
        }
        {
            name = "var-home-${user.name}-.qemu.mount"
            enabled = True
            contents = """\
[Unit]
Description=Mount QEMU project workspace
ConditionVirtualization=qemu
Before=extract-kernel.service

[Mount]
What=qemu
Where=/var/home/${user.name}/.qemu
Type=9p
Options=trans=virtio,version=9p2000.L,rw,msize=104857600,cache=loose

[Install]
WantedBy=multi-user.target
"""
        }
        {
            name = "extract-kernel.service"
            enabled = True
            contents = """\
[Unit]
Description=Extract Kernel and Initramfs for Host Direct Boot
Requires=var-home-${user.name}-.qemu.mount
After=var-home-${user.name}-.qemu.mount
ConditionPathExists=!/var/home/${user.name}/qemu/kernels/vmlinuz

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/usr/bin/mkdir -p /var/home/${user.name}/.qemu/kernels
ExecStart=/usr/bin/bash -c 'cp /boot/vmlinuz-* /var/home/${user.name}/.qemu/kernels/vmlinuz && cp /boot/initramfs-* /var/home/${user.name}/.qemu/kernels/initramfs'

[Install]
WantedBy=multi-user.target
"""
        }
        {
            name = "var-home-${user.name}-workspace.mount"
            enabled = True
            contents = """\
[Unit]
Description=Mount Host Shared Directory in Home
ConditionVirtualization=qemu

[Mount]
What=workspace
Where=/var/home/${user.name}/workspace
Type=9p
Options=trans=virtio,version=9p2000.L,rw,msize=104857600,cache=loose

[Install]
WantedBy=multi-user.target
"""
        }
        {
            name = "var-home-${user.name}-.config-starship.mount"
            enabled = True
            contents = """\
[Unit]
Description=Mount Starship Config (ReadOnly)
ConditionVirtualization=qemu

[Mount]
What=starship
Where=/var/home/${user.name}/.config/starship
Type=9p
Options=trans=virtio,version=9p2000.L,ro,msize=104857600,cache=loose

[Install]
WantedBy=multi-user.target
"""
        }
    ] + custom_units
    custom_units: [ButaneUnit] = []

schema ButaneUser:
    name: str = option("qemu_butane_user_name") or "empty"
    uid: int = int(option("qemu_butane_user_id") or "1000")
    default_ssh_key_path: str = "${file.read_env('HOME')}/.ssh/id_ed25519.pub"
    ssh_keys: [str] = [file.read(default_ssh_key_path).strip()] if file.exists(default_ssh_key_path) else []

schema ButaneFile:
    path: str
    mode: int
    overwrite: bool = True
    contents: ButaneFileContents

schema ButaneDirectory:
    path: str
    mode: int
    user: ButaneDirectoryUser = ButaneDirectoryUser {}
    group: ButaneDirectoryGroup = ButaneDirectoryGroup {}

schema ButaneDirectoryUser:
    name: str = option("qemu_butane_user_name") or "empty"

schema ButaneDirectoryGroup:
    name: str = option("qemu_butane_group_name") or option("qemu_butane_user_name")

schema ButaneFileContents:
    inline: str

schema ButaneUnit:
    name: str
    enabled: bool = True
    contents: str

