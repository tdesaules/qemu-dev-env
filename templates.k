etc_yum_repos_d_terra_repo = lambda -> str {
    """\
[terra]
name=Terra $releasever
baseurl=https://repos.fyralabs.com/terra$releasever
type=rpm
skip_if_unavailable=True
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://repos.fyralabs.com/terra$releasever/key.asc
enabled=1
enabled_metadata=1
metadata_expire=4h
"""
}

etc_hostname = lambda hostname: str -> str {
    """\
${hostname}.local
"""
}

etc_systemd_resolved_conf_d_mdns_conf = lambda -> str {
    """\
[Resolve]
MulticastDNS=yes
"""
}

etc_profile_d_terminal_fix_sh = lambda -> str {
    """\
export TERM=linux
export SYSTEMD_PAGER=cat
"""
}

etc_sudoers_d_user = lambda username: str -> str {
    """\
${username} ALL=(ALL) NOPASSWD: ALL
"""
}

etc_zincati_config_d_50_disable_updates_toml = lambda -> str {
    """\
[updates]
enabled = false
"""
}

install_system_pkgs_service = lambda default_pkgs: [str], custom_pkgs: [str] -> str {
    """\
[Unit]
Description=Provisioning System Packages
ConditionVirtualization=vm
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/bash -c ' \\
    set -e; \\
    MISSING_PKGS=""; \\
    for PKG in ${" ".join(default_pkgs + custom_pkgs)}; do \\
        if ! rpm -q "$$PKG" > /dev/null 2>&1; then \\
            MISSING_PKGS="$$MISSING_PKGS $$PKG"; \\
        fi; \\
    done; \\
    if [ -n "$$MISSING_PKGS" ]; then \\
        /usr/sbin/setenforce 0 || true; \\
        /usr/bin/rpm-ostree install --apply-live --allow-inactive $$MISSING_PKGS && sync; \\
    fi'


[Install]
WantedBy=multi-user.target
"""
}

run_topgrade_service = lambda username: str, github_token: str -> str {
    """\
[Unit]
Description=Topgrade System and User Tools Update
ConditionVirtualization=vm
After=install-system-pkgs.service
Wants=install-system-pkgs.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=${username}
Environment="HOME=/var/home/${username}" "GITHUB_TOKEN=${github_token}"
ExecStart=/usr/bin/topgrade --config /var/home/${username}/.config/topgrade.toml
StandardOutput=journal

[Install]
WantedBy=multi-user.target
"""
}

var_home_user_qemu_mount = lambda username: str -> str {
    """\
[Unit]
Description=Mount QEMU project workspace
ConditionVirtualization=vm
Before=extract-kernel.service

[Mount]
What=qemu
Where=/var/home/${username}/.qemu
Type=9p
Options=trans=virtio,version=9p2000.L,rw,msize=512000,cache=mmap

[Install]
WantedBy=multi-user.target
"""
}

var_home_user_qemu_automount = lambda username: str -> str {
    """\
[Unit]
Description=Automount QEMU project workspace
ConditionVirtualization=vm

[Automount]
Where=/var/home/${username}/.qemu

[Install]
WantedBy=multi-user.target
"""
}

var_home_user_workspace_mount = lambda username: str -> str {
    """\
[Unit]
Description=Mount Host Shared Directory in Home
ConditionVirtualization=vm

[Mount]
What=workspace
Where=/var/home/${username}/workspace
Type=9p
Options=trans=virtio,version=9p2000.L,rw,msize=512000,cache=mmap
"""
}

var_home_user_workspace_automount = lambda username: str -> str {
    """\
[Unit]
Description=Automount Workspace Shared Directory in Home
ConditionVirtualization=vm

[Automount]
Where=/var/home/${username}/workspace

[Install]
WantedBy=multi-user.target
"""
}

var_home_user_config_starship_mount = lambda username: str -> str {
    """\
[Unit]
Description=Mount Starship Config
ConditionVirtualization=vm

[Mount]
What=starship
Where=/var/home/${username}/.config/starship
Type=9p
Options=trans=virtio,version=9p2000.L,ro,msize=512000,cache=mmap

[Install]
WantedBy=multi-user.target
"""
}

var_home_user_config_mise_config_toml = lambda tools: {str:str} -> str {
    _lines = ["[tools]"] + ["\"${k}\" = \"${v}\"" for k, v in tools if v]
    "\n".join(_lines) + "\n"
}

var_home_user_config_topgrade_toml = lambda -> str {
    """\
[misc]
assume_yes = true
cleanup = true
no_self_update = true
disable = ["mise", "firmware", "containers", "toolbx"]

[commands]
"Mise" = "mise install --yes || (sleep 10 && mise install --yes) || true"
"""
}

var_home_user_bashrc_d_00_mise_sh = lambda username: str, github_token: str -> str {
    _token_line = ["export GITHUB_TOKEN=\"${github_token}\""] if github_token else []
    _mise_line = [
        """\
if [[ $- == *i* ]] && [ "$USER" = "${username}" ] && command -v mise >/dev/null 2>&1; then
    eval "$(mise activate bash)"
fi\
"""
    ]
    "\n".join(_token_line + _mise_line) + "\n"
}

var_home_user_bashrc_d_10_starship_sh = lambda username: str -> str {
    """\
if [[ $- == *i* ]] && [ "$USER" = "${username}" ]; then
    export STARSHIP_CONFIG="/var/home/${username}/.config/starship/config.toml"
    if command -v starship >/dev/null 2>&1; then
        eval "$(starship init bash)"
    fi
fi
"""
}

var_home_user_bashrc_d_20_fastfetch_sh = lambda username: str -> str {
    """\
if [[ $- == *i* ]] && [ "$USER" = "${username}" ] && command -v fastfetch >/dev/null 2>&1; then
    fastfetch
fi
"""
}

etc_polkit_1_rules_d_99_rpmostree_passwordless_rules = lambda -> str {
    """\
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.projectatomic.rpmostree1.") == 0 && subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
"""
}

etc_subuid = lambda username: str -> str {
    """\
${username}:100000:65536
"""
}

etc_subgid = lambda username: str -> str {
    """\
${username}:100000:65536
"""
}

var_home_user_hushlogin = lambda -> str {
    ""
}

etc_selinux_config = lambda -> str {
    """\
SELINUX=permissive
SELINUXTYPE=targeted
"""
}

configure_cockpit_service = lambda -> str {
    """\
[Unit]
Description=Configure and Enable Cockpit Service
After=install-system-pkgs.service
Wants=install-system-pkgs.service
ConditionPathExists=/usr/lib/systemd/system/cockpit.socket

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/bash -c ' \\
    /usr/bin/systemctl daemon-reload; \\
    /usr/bin/systemctl enable cockpit.socket; \\
    for i in $(seq 1 5); do \\
        /usr/bin/systemctl start cockpit.socket && break; \\
        sleep 2; \\
    done'

[Install]
WantedBy=multi-user.target
"""
}

etc_containers_systemd_beszel_agent_container = lambda key: str = "", token: str = "", hub_url: str = "", system_name: str = "" -> str {
    _key_part = "Environment=\"KEY=${key}\"\n" if key else ""
    _token_part = "Environment=\"TOKEN=${token}\"\n" if token else ""
    _hub_url_part = "Environment=\"HUB_URL=${hub_url}\"\n" if hub_url else ""
    _system_name_part = "Environment=\"SYSTEM_NAME=${system_name}\"\n" if system_name else ""
    """\
[Unit]
Description=Beszel Agent Container
After=network-online.target
Wants=network-online.target

[Container]
ContainerName=beszel-agent
Image=docker.io/henrygd/beszel-agent:latest
Network=host
PodmanArgs=--pid=host
Volume=/run/podman/podman.sock:/var/run/docker.sock:ro
Volume=/var/lib/beszel-agent:/var/lib/beszel-agent
Environment="DISABLE_SSH=true"
${_key_part}${_token_part}${_hub_url_part}${_system_name_part}[Service]
Restart=always

[Install]
WantedBy=multi-user.target
"""
}
