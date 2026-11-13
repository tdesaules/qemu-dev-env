"""Small metadata view consumed by Task; provisioning uses butane-render.k."""
import .config as cfg

# Hidden binding: never serialize the full provisioning payload into a Task var.
_qemu = cfg.config
config = {
    uuid = _qemu.uuid
    workspace = _qemu.workspace
    os = _qemu.os
    checksum = _qemu.checksum
    hardware = _qemu.hardware
    command = _qemu.command
    butane = {
        github = {token = _qemu.butane.github.token}
        if _qemu.butane.beszel:
            beszel = {url = _qemu.butane.beszel.url or ""}
    }
}
