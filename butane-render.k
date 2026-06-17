import .schema as schema
import .config as cfg

qemu = schema.Qemu {
    **(cfg.config if cfg.config else {})
}

butane = {
    variant = "fcos"
    version = "1.5.0"
    passwd.users = [
        {
            name = qemu.butane.user.name
            uid = qemu.butane.user.uid
            groups = ["wheel", "docker"]
            ssh_authorized_keys = [*qemu.butane.user.ssh_keys]
        }
    ]
    storage.directories = qemu.butane.directories
    storage.files = qemu.butane.files
    systemd.units = qemu.butane.units
}
