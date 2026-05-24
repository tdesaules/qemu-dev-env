import .schema as schema

config = schema.Qemu {
    os.version = "44.20260419.3.1"
    checksum = {
        "x86_64" = "4988775076f6b94f33c47243e2f0fbb3ecd412b6cd7ad492faa98d2d705e9035"
        "aarch64" = "d7a66a4a69d83208ecfda180650d5681da6f572bed9c491057862be1d77fa0f3"
    }
    butane.custom_pkgs = []
    butane.custom_files = []
    butane.custom_units = []
}
