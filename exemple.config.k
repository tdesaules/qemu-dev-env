import .schema as schema

config = schema.Qemu {
    hardware = schema.Hardware {
        cpu = 1
        memory = schema.Memory {
            size = 1024
        }
        disk = schema.Disk {
            size = 16
        }
    }
    butane = schema.Butane {
        custom_pkgs = [
            "htop"
        ]
        github = {
            token = option("github_token")
        }
        beszel = {
            url = "http://10.10.10.1:8090"
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
    }
}
