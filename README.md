# ServerInit

Cloud-init focused server bootstrap scripts.

This repository currently contains one installer that installs only `3x-ui` and configures it for cloud-init usage:
- You can use shared credentials (`--username`, `--password`) for both panel and Linux user.
- Or you can set separate credentials for panel and Linux user.
- A Linux user is created/updated and granted root-like sudo access.
- Panel path is optional (`--path`) and defaults to root (`/`).
- Panel port is optional (`--port`) and defaults to `2053`.
- SSL cert setup is skipped by default (HTTP panel).
- `apt-get update` is always executed before install.
- `sudo`, `nload`, `fzf`, and `figlet` are installed automatically.

## Files
- `scripts/install-3x-ui.sh`: main installer script.
- `cloud-init/3x-ui-cloud-init.yaml`: ready cloud-init example.

## Quick Usage
Run directly on a Debian/Ubuntu server:

```bash
sudo bash scripts/install-3x-ui.sh \
  --username "myadmin" \
  --password "MyStrongPassword!"
```

Use different credentials for 3x-ui and Linux user:

```bash
sudo bash scripts/install-3x-ui.sh \
  --panel-username "paneladmin" \
  --panel-password "PanelStrongPassword!" \
  --server-username "serveradmin" \
  --server-password "ServerStrongPassword!"
```

Default panel port is `2053` unless you set `--port`.

Run directly from GitHub (no local clone required):

```bash
curl -fsSL https://raw.githubusercontent.com/KiaTheRandomGuy/ServerInit/main/scripts/install-3x-ui.sh -o /usr/local/bin/install-3x-ui.sh
chmod +x /usr/local/bin/install-3x-ui.sh
sudo /usr/local/bin/install-3x-ui.sh --username "myadmin" --password "MyStrongPassword!"
```

Set a custom panel path:

```bash
sudo bash scripts/install-3x-ui.sh \
  --username "myadmin" \
  --password "MyStrongPassword!" \
  --path "panel"
```

Set a custom panel port:

```bash
sudo bash scripts/install-3x-ui.sh \
  --username "myadmin" \
  --password "MyStrongPassword!" \
  --port "8443"
```

Pin a specific 3x-ui version:

```bash
sudo bash scripts/install-3x-ui.sh \
  --username "myadmin" \
  --password "MyStrongPassword!" \
  --version "v2.6.5"
```

## Parameters
- `--username` (optional): shared username for both panel and Linux user.
- `--password` (optional): shared password for both panel and Linux user.
- `--panel-username` (optional): 3x-ui panel username.
- `--panel-password` (optional): 3x-ui panel password.
- `--server-username` (optional): Linux username.
  - Linux username must match: lowercase letters/numbers/`_`/`-`, start with letter or `_`, max 32 chars.
- `--server-password` (optional): Linux user password.
- Credentials requirement: you must provide values for both panel and server credentials either:
  - via shared `--username` + `--password`, or
  - via separate `--panel-*` and `--server-*` flags.
- `--path` (optional): custom panel URI path.
  - Example: `--path panel` gives `/panel/`.
  - Default: root path `/` (no custom path).
- `--port` (optional): panel port.
  - Example: `--port 8443`.
  - Default: `2053`.
- `--version` (optional): release tag to install.
  - Default: latest release from `MHSanaei/3x-ui`.
- `--dry-run` (optional): prints commands without executing.

## Cloud-init Example
Use `cloud-init/3x-ui-cloud-init.yaml` directly and change credential values as needed.

Example with custom path:

```yaml
#cloud-config
package_update: true
packages:
  - curl

runcmd:
  - [bash, -lc, "curl -fsSL https://raw.githubusercontent.com/KiaTheRandomGuy/ServerInit/main/scripts/install-3x-ui.sh -o /usr/local/bin/install-3x-ui.sh"]
  - [chmod, "+x", "/usr/local/bin/install-3x-ui.sh"]
  - [bash, "-lc", "/usr/local/bin/install-3x-ui.sh --panel-username 'paneladmin' --panel-password 'PanelStrongPassword!' --server-username 'serveradmin' --server-password 'ServerStrongPassword!' --path 'panel' --port '8443'"]
```

## Behavior Notes
- Script is designed for Debian/Ubuntu (`apt-get` + `systemd` required).
- SSL cert config inside 3x-ui is reset/disabled by default.
- Panel port is set to `2053` by default.
- Panel and Linux credentials can be shared or separate.
- Linux user gets `NOPASSWD` sudo (`ALL=(ALL:ALL) NOPASSWD:ALL`).
- `sudo`, `nload`, `fzf`, and `figlet` are installed during dependency setup.
- Installer sets credentials and path after unpacking 3x-ui files.
- Service is enabled and started automatically.

## Validation Commands
```bash
bash -n scripts/install-3x-ui.sh
bash scripts/install-3x-ui.sh --help
bash scripts/install-3x-ui.sh --username test --password test --dry-run
```
