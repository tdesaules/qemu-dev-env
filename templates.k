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
ConditionVirtualization=qemu
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
        /usr/bin/rpm-ostree install --apply-live --allow-inactive $$MISSING_PKGS && sync; \\
    fi'


[Install]
WantedBy=multi-user.target
"""
}

var_home_user_qemu_mount = lambda username: str -> str {
    """\
[Unit]
Description=Mount QEMU project workspace
ConditionVirtualization=qemu
Before=extract-kernel.service

[Mount]
What=qemu
Where=/var/home/${username}/.qemu
Type=9p
Options=trans=virtio,version=9p2000.L,rw,msize=512000,cache=loose

[Install]
WantedBy=multi-user.target
"""
}

var_home_user_qemu_automount = lambda username: str -> str {
    """\
[Unit]
Description=Automount QEMU project workspace
ConditionVirtualization=qemu

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
ConditionVirtualization=qemu

[Mount]
What=workspace
Where=/var/home/${username}/workspace
Type=9p
Options=trans=virtio,version=9p2000.L,rw,msize=512000,cache=loose
"""
}

var_home_user_workspace_automount = lambda username: str -> str {
    """\
[Unit]
Description=Automount Workspace Shared Directory in Home
ConditionVirtualization=qemu

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
ConditionVirtualization=qemu

[Mount]
What=starship
Where=/var/home/${username}/.config/starship
Type=9p
Options=trans=virtio,version=9p2000.L,ro,msize=512000,cache=loose

[Install]
WantedBy=multi-user.target
"""
}
