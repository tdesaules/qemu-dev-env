import .schema as schema

config = schema.Qemu {
    butane = schema.Butane {
        custom_pkgs = []
        github_token = option("github_token") or "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
        custom_mise_tools = {
            "go" = "latest"
        }
        files += []
        units += []
    }
}
