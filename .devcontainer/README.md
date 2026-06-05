# Devcontainer

Adapted from `~/dev/dev-environment/references/bun-sandbox/`. Same Bun base image
and Claude Code install path; project-specific tools added on top.

## Tools available inside the container

| Tool | Purpose |
|---|---|
| `stylua` | Format Lua addon source |
| `luacheck` | Lint Lua (unused vars, globals, shadowing) |
| `ruff` | Lint + format Python (`.analytics/`) |
| `python3` + `pip` | Run analytics scripts |
| `sqlite3` | Inspect `wow_addon_data.sqlite` from the shell |
| `gh`, `jq`, `git-delta` | Standard ops |

The OS user is still `bun` — that's the default user baked into the
`oven/bun:1-debian` base image. Leaving it as-is avoids a UID juggle; it's
purely cosmetic. Bun itself is unused by this project.

## Common commands

```sh
stylua AHLedger/                              # format an addon
luacheck AHLedger/ --no-global --globals C_  # lint (with WoW globals allowed)
ruff format .analytics/                       # format python
ruff check .analytics/                        # lint python
sqlite3 .analytics/wow_addon_data.sqlite      # inspect generated db
```

## Secrets

`load-secrets.sh` decrypts `~/.secrets-enc/github-token.gpg` into a podman
secret mounted at `/run/secrets/github-token` inside the container. The zsh
profile exports it as `GH_TOKEN` so `gh` works without prompting.
