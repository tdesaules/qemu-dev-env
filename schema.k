import file
import crypto
import .templates as templates

_taskfile_dir = option("taskfile_dir") or "."
_username = option("qemu_butane_user_name") or "null"
_groupname = option("qemu_butane_group_name") or _username
_uid = int(option("qemu_butane_user_id") or "1000")
_uuid = file.read("${_taskfile_dir}/.uuid").strip() if file.exists("${_taskfile_dir}/.uuid") else crypto.uuid()
_workspace = "${file.read_env('HOME')}/.qemu/${_uuid}"
_host_os = option("qemu_host_os") or "null"
_os_arch = option("qemu_host_arch") or "null"
_os_name: str = "fedora"
_os_edition: str = "coreos"
_os_version: str = "44.20260419.3.1"
_os_streams: str = "stable"
_checksum_x86_64 = "4988775076f6b94f33c47243e2f0fbb3ecd412b6cd7ad492faa98d2d705e9035"
_checksum_aarch64 = "d7a66a4a69d83208ecfda180650d5681da6f572bed9c491057862be1d77fa0f3"

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
            "-M ${'q35' if os.arch == 'x86_64' else 'virt,highmem=off'}"
            "-accel ${'hvf' if host_os == 'darwin' else 'kvm'}"
            "-cpu host"
            "-smp ${hardware.cpu}"
            "-m ${str(hardware.memory.size)}${hardware.memory.unit}"
            "-display none"
            "-daemonize"
            "-nodefaults"
            "-pidfile ${workspace}/qemu.pid"
            "-device virtio-rng-pci"
            "-drive if=pflash,format=raw,readonly=on,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
            "-drive if=virtio,format=qcow2,file=${workspace}/${os.name}-${os.edition}-${os.version}-${os.arch}.qcow2,cache=unsafe"
            "-fw_cfg name=opt/com.coreos/config,file=${_taskfile_dir}/config.ign"
            "-netdev vmnet-shared,id=net0" if host_os == "darwin" else "-netdev user,id=net0"
            "-device virtio-net-pci,netdev=net0"
            "-fsdev local,id=fsdev0,path=${workspace},security_model=passthrough"
            "-device virtio-9p-pci,fsdev=fsdev0,mount_tag=qemu"
            "-fsdev local,id=fsdev1,path=${file.read_env('PWD')},security_model=passthrough"
            "-device virtio-9p-pci,fsdev=fsdev1,mount_tag=workspace"
            "-fsdev local,id=fsdev2,path=${file.read_env('HOME')}/.config/starship,security_model=passthrough,readonly=on"
            "-device virtio-9p-pci,fsdev=fsdev2,mount_tag=starship"
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
    default_pkgs: [str] = ["git", "terra-release", "topgrade", "mise"]
    custom_pkgs: [str] = []
    directories: [ButaneDirectory] = [
        {
            path = "/var/home/${user.name}/.config"
            mode = 493
        }
    ]
    files: [ButaneFile] = [
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
    ]
    units: [ButaneUnit] = [
        {
            name = "install-system-pkgs.service"
            enabled = True
            contents = templates.install_system_pkgs_service(default_pkgs, custom_pkgs)
        }
        {
            name = "var-home-${user.name}-.qemu.mount"
            enabled = True
            contents = templates.var_home_user_qemu_mount(user.name)
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
            name = "var-home-${user.name}-.config-starship.mount"
            enabled = True
            contents = templates.var_home_user_config_starship_mount(user.name)
        }
    ]

schema ButaneUser:
    name: str = "${_username}"
    uid: int = _uid
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
    name: str = _username

schema ButaneDirectoryGroup:
    name: str = _groupname

schema ButaneFileContents:
    inline: str

schema ButaneUnit:
    name: str
    enabled: bool = True
    contents: str

