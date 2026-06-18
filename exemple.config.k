import .schema as schema

config = schema.Qemu {
    butane = schema.Butane {
        custom_pkgs = []
        github = {
            token = option("github_token") or "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
        }
        custom_mise_tools = {
            "go" = "latest"
        }
        beszel = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOI+Po4d7GBDYGqpBdEb+YiBcui4BgPY2j12+kNMe/Sn"
            token = "38ae33f7-126e-4c2a-8622-b6444868771b"
            url = "http://192.168.2.1:8090"
        }
        files += []
        units += []
    }
}
