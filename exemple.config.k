import .schema as schema

config = schema.Qemu {
    hardware = schema.Hardware {
        cpu = 2
        memory = schema.Memory {
            size = 4096
        }
        disk = schema.Disk {
            size = 30
        }
    }
    butane = schema.Butane {
        custom_pkgs = [
            "htop"
        ]
        github = {
            token = option("github_token")
        }
        custom_mise_tools = {
            "go" = "latest"
        }
        custom_files = [
            {
                path = "/var/home/${option('qemu_butane_user_name')}/hello-files"
                mode = 420
                contents.inline = "hello files\n"
            }
            {
                path = "/etc/containers/systemd/test-demo.container"
                mode = 420
                contents.inline = """\
[Container]
ContainerName=test-demo
Image=docker.io/library/alpine:latest
Exec=sleep 1000

[Install]
WantedBy=multi-user.target
"""
            }
        ]
        custom_copies = [
            {
                source = "/home/tdesaules/.config/some-tool/config.toml"
                path = "/var/home/${option('qemu_butane_user_name')}/.config/some-tool/config.toml"
            }
        ]
        units += [
            {
                name = "create-hello-units.service"
                enabled = True
                contents = """\
[Unit]
Description=Create hello-units file
After=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/bash -c "echo 'hello units' > /var/home/${option('qemu_butane_user_name')}/hello-units && chown ${option('qemu_butane_user_name')}:${option('qemu_butane_user_name')} /var/home/${option('qemu_butane_user_name')}/hello-units && chmod 644 /var/home/${option('qemu_butane_user_name')}/hello-units"

[Install]
WantedBy=multi-user.target
"""
            }
        ]
        beszel = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOI+P..."
            token = "38ae33f7-126e-4c2a-8622-b644........"
            url = "http://192.168.2.1:8090"
        }
    }
}
