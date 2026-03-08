# NOI Agent Browser Hardened Launcher

Hardened local Windows launcher for `zeroclaw` + `NOI`.

## Included files

- `NOI_Agent_Browser.bat`
- `NOI_Agent_Browser_Harden.ps1`

## What it does

- Forces the gateway to bind to `127.0.0.1`
- Requires pairing and keeps public bind disabled
- Locks down token and config file permissions
- Disables startup persistence by default
- Reuses a healthy local gateway when possible
- Keeps autonomy supervised and workspace-only
- Blocks remote computer-use endpoints

## Usage

Run:

```bat
NOI_Agent_Browser.bat
```

Dry run:

```bat
NOI_Agent_Browser.bat --dry-run
```

Enable startup shortcut explicitly:

```bat
NOI_Agent_Browser.bat --enable-startup
```

## Do not upload

Do not commit any of these local machine files:

- `bearer.token`
- `config.toml`
- `gateway.json`
- `logs/`
- `memory/`
- `sessions/`

## Notes

This launcher is meant for local-only use on Windows and is not an unrestricted remote control agent.
