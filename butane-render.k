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
        {
            name = "dev"
            groups = ["wheel", "docker"]
            password_hash = "$6$eSbOkv5OLtXL/yW5$9dxuwxUDK1DPpgY1ntHkBPCrElYCwPeghRUNVU0cDcKM6kGLmC5F2lPTSiU0IGLRTj7HntWArLIiuU2Oi7h8i1"
        }
    ]
    storage.directories = qemu.butane.directories
    storage.files = qemu.butane.files
    systemd.units = qemu.butane.units
}
