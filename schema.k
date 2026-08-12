import file
import crypto
import .templates as templates

_taskfile_dir = option("taskfile_dir") or "."
_username = option("qemu_butane_user_name") or "null"
_groupname = option("qemu_butane_group_name") or _username
_uid = int(option("qemu_butane_user_id") or "1000")
_uuid = file.read("${_taskfile_dir}/.uuid").strip() if file.exists("${_taskfile_dir}/.uuid") else crypto.uuid()
_workspace = "${file.read_env('HOME')}/.qemu/${_uuid}"
_mac_hex = _uuid.replace("-", "")
_mac = "52:54:00:" + _mac_hex[0:2] + ":" + _mac_hex[2:4] + ":" + _mac_hex[4:6]
_host_os = option("qemu_host_os") or "null"
_os_arch = option("qemu_host_arch") or "null"
_aio_opt = ",aio=io_uring" if _host_os == "linux" else ""
_os_name: str = "fedora"
_os_edition: str = "coreos"
_os_version: str = "44.20260720.3.1"
_os_streams: str = "stable"
_checksum_x86_64 = "1bdc3c59b16508b9c24ac85b7d2543261a02bef5fae4ec5820511b4e7d66a338"
_checksum_aarch64 = "e3e848071b3afa3453df7247fe94ce9978e210879adfb1f53610f63ed8912777"

_edk2_candidates = [
    "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
    "/usr/share/qemu/edk2-aarch64-code.fd"
    "/usr/share/AAVMF/AAVMF_CODE.fd"
]
_edk2_path = option("qemu_edk2_path") or ([p for p in _edk2_candidates if file.exists(p)][0] if [p for p in _edk2_candidates if file.exists(p)] else "")
_starship_config_dir = "${file.read_env('HOME')}/.config/starship"
_has_starship = file.exists(_starship_config_dir)
_opencode_config_dir = "${file.read_env('HOME')}/.config/opencode"
_opencode_data_dir = "${file.read_env('HOME')}/.local/share/opencode"
_has_opencode_config = file.exists("${_opencode_config_dir}/opencode.json") or file.exists("${_opencode_config_dir}/tui.json") or file.exists("${_opencode_data_dir}/auth.json")
_ssh_key_paths = [
    "${file.read_env('HOME')}/.ssh/id_ed25519.pub"
    "${file.read_env('HOME')}/.ssh/id_rsa.pub"
]
_existing_ssh_keys = [file.read(p).strip() for p in _ssh_key_paths if file.exists(p)]

schema Qemu:
    uuid: str = "${_uuid}"
    workspace: str = "${_workspace}"
    host_os: str = "${_host_os}"
    os: Os {}
    checksum: Checksum {}
    hardware: Hardware {}
    command: Command = Command {
        options = [
            "-name ${uuid}"
            "-M ${'q35,vmport=off' if os.arch == 'x86_64' else 'virt,highmem=off'}"
            "-accel ${'hvf' if host_os == 'darwin' else 'kvm'}"
            "-cpu host"
            "-smp ${hardware.cpu}"
            "-m ${str(hardware.memory.size)}${hardware.memory.unit}"
            "-display none"
            "-daemonize"
            "-nodefaults"
            "-pidfile ${workspace}/qemu.pid"
            "-device virtio-rng-pci"
            *([
                "-drive if=pflash,format=raw,readonly=on,file=${_edk2_path}"
            ] if os.arch == "aarch64" and _edk2_path else [])
            "-drive if=virtio,format=qcow2,file=${workspace}/qemu.qcow2,cache=unsafe${_aio_opt}"
            "-fw_cfg name=opt/com.coreos/config,file=${_taskfile_dir}/config.ign"
            "-netdev vmnet-shared,id=net0" if host_os == "darwin" else "-netdev bridge,id=net0,br=br-qemu"
            "-device virtio-net-pci,netdev=net0,mac=${_mac}"
            "-fsdev local,id=fsdev0,path=${workspace},security_model=passthrough"
            "-device virtio-9p-pci,fsdev=fsdev0,mount_tag=qemu"
            "-fsdev local,id=fsdev1,path=${file.read_env('PWD')},security_model=passthrough"
            "-device virtio-9p-pci,fsdev=fsdev1,mount_tag=workspace"
            *([
                "-fsdev local,id=fsdev2,path=${_starship_config_dir},security_model=passthrough,readonly=on"
                "-device virtio-9p-pci,fsdev=fsdev2,mount_tag=starship"
            ] if _has_starship else [])
            "-serial file:${workspace}/qemu.log"
        ]
    }
    butane: Butane {}

schema Os:
    arch: str = "${_os_arch}"
    name: str = "${_os_name}"
    edition: str = "${_os_edition}"
    version: str = "${_os_version}"
    streams: str = "${_os_streams}"

schema Checksum:
    x86_64: str = "${_checksum_x86_64}"
    aarch64: str = "${_checksum_aarch64}"

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

schema Command:
    sudo: bool = True
    binary: str = "qemu-system-${_os_arch}"
    options: [str] = []

schema Butane:
    user: ButaneUser = ButaneUser {}
    hostname: str = "${_uuid}"
    default_pkgs: [str] = [
        "git"
        "terra-release"
        "topgrade"
        "mise"
        "cockpit-ws"
        "cockpit-system"
        "cockpit-ostree"
        "cockpit-podman"
    ]
    custom_pkgs: [str] = []
    github: Github = Github {}
    beszel?: Beszel
    default_mise_tools: {str:str} = {
        "github:starship/starship" = "latest"
        "github:fastfetch-cli/fastfetch" = "latest"
    }
    custom_mise_tools: {str:str} = {}
    mise_tools: {str:str} = default_mise_tools | custom_mise_tools
    custom_files: [ButaneFile] = []
    default_copies: [ButaneCopy] = []
    custom_copies: [ButaneCopy] = []
    copies: [ButaneCopy] = default_copies + custom_copies
    directories: [ButaneDirectory]
    files: [ButaneFile]
    units: [ButaneUnit]

    directories = [
        {
            path = "/var/home/${user.name}/.config"
            mode = 493
        }
        {
            path = "/var/home/${user.name}/.config/starship"
            mode = 493
        }
        {
            path = "/var/home/${user.name}/.config/mise"
            mode = 493
        }
        {
            path = "/var/home/${user.name}/.local"
            mode = 493
        }
        {
            path = "/var/home/${user.name}/.local/share"
            mode = 493
        }
        {
            path = "/var/home/${user.name}/.local/state"
            mode = 493
        }
        {
            path = "/var/home/${user.name}/.config/opencode"
            mode = 493
        }
        {
            path = "/var/home/${user.name}/.local/share/opencode"
            mode = 493
        }
        {
            path = "/var/home/${user.name}/.bashrc.d"
            mode = 493
            user = {}
            group = {}
        }
    ] + ([
        {
            path = "/var/lib/beszel-agent"
            mode = 493
            user = { name = "root" }
            group = { name = "root" }
        }
    ] if beszel else [])
    default_copies = [
        {
            source = "${_opencode_config_dir}/opencode.json"
            path = "/var/home/${user.name}/.config/opencode/opencode.json"
        }
        {
            source = "${_opencode_config_dir}/tui.json"
            path = "/var/home/${user.name}/.config/opencode/tui.json"
        }
        {
            source = "${_opencode_data_dir}/auth.json"
            path = "/var/home/${user.name}/.local/share/opencode/auth.json"
            mode = 384
        }
    ] if _has_opencode_config else []
    files = [
        {
            path = "/etc/zincati/config.d/50-disable-updates.toml"
            mode = 420
            contents.inline = templates.etc_zincati_config_d_50_disable_updates_toml()
        }
        {
            path = "/etc/yum.repos.d/terra.repo"
            mode = 420
            contents.inline = templates.etc_yum_repos_d_terra_repo()
        }
        {
            path = "/etc/hostname"
            mode = 420
            contents.inline = templates.etc_hostname(hostname)
        }
        {
            path = "/etc/systemd/resolved.conf.d/mdns.conf"
            mode = 420
            contents.inline = templates.etc_systemd_resolved_conf_d_mdns_conf()
        }
        {
            path = "/etc/profile.d/terminal-fix.sh"
            mode = 420
            contents.inline = templates.etc_profile_d_terminal_fix_sh()
        }
        {
            path = "/etc/sudoers.d/${user.name}"
            mode = 288
            contents.inline = templates.etc_sudoers_d_user(user.name)
        }
        {
            path = "/var/home/${user.name}/.config/mise/config.toml"
            mode = 420
            user = {}
            group = {}
            contents.inline = templates.var_home_user_config_mise_config_toml(mise_tools)
        }
        {
            path = "/var/home/${user.name}/.config/topgrade.toml"
            mode = 420
            user = {}
            group = {}
            contents.inline = templates.var_home_user_config_topgrade_toml()
        }
        {
            path = "/var/home/${user.name}/.bashrc.d/00-mise.sh"
            mode = 420
            user = {}
            group = {}
            contents.inline = templates.var_home_user_bashrc_d_00_mise_sh(user.name, github.token)
        }
        {
            path = "/var/home/${user.name}/.bashrc.d/10-starship.sh"
            mode = 420
            user = {}
            group = {}
            contents.inline = templates.var_home_user_bashrc_d_10_starship_sh(user.name)
        }
        {
            path = "/var/home/${user.name}/.bashrc.d/20-fastfetch.sh"
            mode = 420
            user = {}
            group = {}
            contents.inline = templates.var_home_user_bashrc_d_20_fastfetch_sh(user.name)
        }
        {
            path = "/etc/polkit-1/rules.d/99-rpmostree-passwordless.rules"
            mode = 420
            contents.inline = templates.etc_polkit_1_rules_d_99_rpmostree_passwordless_rules()
        }
        {
            path = "/etc/subuid"
            mode = 420
            contents.inline = templates.etc_subuid(user.name)
        }
        {
            path = "/etc/subgid"
            mode = 420
            contents.inline = templates.etc_subgid(user.name)
        }
        {
            path = "/var/home/${user.name}/.hushlogin"
            mode = 420
            user = {}
            group = {}
            contents.inline = templates.var_home_user_hushlogin()
        }
        {
            path = "/etc/sudoers.d/dev"
            mode = 288
            contents.inline = templates.etc_sudoers_d_user("dev")
        }
        {
            path = "/etc/selinux/config"
            mode = 420
            contents.inline = templates.etc_selinux_config()
        }
    ] + ([
        {
            path = "/etc/containers/systemd/beszel-agent.container"
            mode = 420
            contents.inline = templates.etc_containers_systemd_beszel_agent_container(beszel.key or "", beszel.token or "", beszel.url or "", hostname)
        }
    ] if beszel and beszel.token else []) + custom_files + [
        {
            path = c.path
            mode = c.mode
            user = c.user or {}
            group = c.group or {}
            contents.inline = file.read(c.source)
        }
        for c in copies if file.exists(c.source)
    ]
    units = [
        {
            name = "install-system-pkgs.service"
            enabled = True
            contents = templates.install_system_pkgs_service(default_pkgs, custom_pkgs)
        }
        {
            name = "run-topgrade.service"
            enabled = True
            contents = templates.run_topgrade_service(user.name, github.token)
        }
        {
            name = "var-home-${user.name}-.qemu.mount"
            enabled = False
            contents = templates.var_home_user_qemu_mount(user.name)
        }
        {
            name = "var-home-${user.name}-.qemu.automount"
            enabled = True
            contents = templates.var_home_user_qemu_automount(user.name)
        }
        {
            name = "var-home-${user.name}-workspace.mount"
            enabled = False
            contents = templates.var_home_user_workspace_mount(user.name)
        }
        {
            name = "var-home-${user.name}-workspace.automount"
            enabled = True
            contents = templates.var_home_user_workspace_automount(user.name)
        }
        {
            name = "configure-cockpit.service"
            enabled = True
            contents = templates.configure_cockpit_service()
        }
        {
            name = "podman.socket"
            enabled = True
        }
    ] + ([
        {
            name = "var-home-${user.name}-.config-starship.mount"
            enabled = True
            contents = templates.var_home_user_config_starship_mount(user.name)
        }
    ] if _has_starship else [])

schema ButaneUser:
    name: str = "${_username}"
    uid: int = _uid
    ssh_keys: [str] = _existing_ssh_keys

schema ButaneFile:
    path: str
    mode: int
    overwrite: bool = True
    user?: ButaneFileUser
    group?: ButaneFileGroup
    contents: ButaneFileContents

schema ButaneFileUser:
    name: str = _username

schema ButaneFileGroup:
    name: str = _groupname

schema ButaneCopy:
    source: str
    path: str
    mode: int = 420
    user?: ButaneFileUser
    group?: ButaneFileGroup

schema ButaneDirectory:
    path: str
    mode: int
    user: ButaneDirectoryUser = ButaneDirectoryUser {}
    group: ButaneDirectoryGroup = ButaneDirectoryGroup {}

schema ButaneDirectoryUser:
    name: str = _username

schema ButaneDirectoryGroup:
    name: str = _groupname

schema ButaneFileContents:
    inline: str

schema ButaneUnit:
    name: str
    enabled: bool = True
    contents?: str

schema Beszel:
    key: str = option("beszel_key") or ""
    token: str = option("beszel_token") or ""
    url?: str
    username: str = "local@home.lan"
    password: str = "local@home.lan"

schema Github:
    token: str = ""
