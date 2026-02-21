# ServerInit

Cloud-init focused server bootstrap scripts.

This repository currently contains one installer that installs only `3x-ui` and configures it for cloud-init usage:
- You can use shared credentials (`--username`, `--password`) for both panel and Linux user.
- Or you can set separate credentials for panel and Linux user.
- A Linux user is created/updated and granted root-like sudo access.
- Panel path is optional (`--path`) and defaults to root (`/`).
- Panel port is optional (`--port`) and defaults to `2053`.
- SSL cert setup is skipped by default (HTTP panel).
- SSH password authentication is enforced (`PasswordAuthentication yes`).
- `apt-get update` is always executed before install.
- `sudo`, `nload`, `fzf`, and `figlet` are installed automatically.
- If `3x-ui` is already healthy/running, the script skips reinstall by default.

## Files
- `scripts/install-3x-ui.sh`: main installer script.
- `cloud-init/3x-ui-cloud-init.yaml`: ready cloud-init example.

## Quick Usage
Run directly on a Debian/Ubuntu server:

```bash
PANEL_USER="myadmin"
PANEL_PASS="MyStrongPassword!"

sudo bash scripts/install-3x-ui.sh \
  --username "${PANEL_USER}" \
  --password "${PANEL_PASS}"
```

Use different credentials for 3x-ui and Linux user:

```bash
PANEL_USER="paneladmin"
PANEL_PASS="PanelStrongPassword!"
SERVER_USER="serveradmin"
SERVER_PASS="ServerStrongPassword!"

sudo bash scripts/install-3x-ui.sh \
  --panel-username "${PANEL_USER}" \
  --panel-password "${PANEL_PASS}" \
  --server-username "${SERVER_USER}" \
  --server-password "${SERVER_PASS}"
```

Default panel port is `2053` unless you set `--port`.

Run directly from GitHub (no local clone required):

```bash
PANEL_USER="myadmin"
PANEL_PASS="MyStrongPassword!"

curl -fsSL https://raw.githubusercontent.com/KiaTheRandomGuy/ServerInit/main/scripts/install-3x-ui.sh -o /usr/local/bin/install-3x-ui.sh
chmod +x /usr/local/bin/install-3x-ui.sh
sudo /usr/local/bin/install-3x-ui.sh --username "${PANEL_USER}" --password "${PANEL_PASS}"
```

## One-Command Recipes
Run full cloud-config on an existing Ubuntu server (for testing):

```bash
curl -fsSL https://raw.githubusercontent.com/KiaTheRandomGuy/ServerInit/main/cloud-init/3x-ui-cloud-init.yaml | sudo cloud-init devel schema --config-file /dev/stdin >/dev/null && curl -fsSL https://raw.githubusercontent.com/KiaTheRandomGuy/ServerInit/main/cloud-init/3x-ui-cloud-init.yaml | sudo tee /root/cloud-init-3x-ui.yaml >/dev/null && sudo cloud-init single --name cc_runcmd --frequency always --file /root/cloud-init-3x-ui.yaml
```

Install 3x-ui + create/update Linux admin user in one command:

```bash
PANEL_USER="paneladmin"; PANEL_PASS="PanelStrongPassword!"; SERVER_USER="serveradmin"; SERVER_PASS="ServerStrongPassword!"; PANEL_PORT="2053"; bash <(curl -fsSL https://raw.githubusercontent.com/KiaTheRandomGuy/ServerInit/main/scripts/install-3x-ui.sh) --panel-username "${PANEL_USER}" --panel-password "${PANEL_PASS}" --server-username "${SERVER_USER}" --server-password "${SERVER_PASS}" --port "${PANEL_PORT}"
```

Create a Linux sudo user only (without touching 3x-ui):

```bash
SERVER_USER="serveradmin"; SERVER_PASS="ServerStrongPassword!"; sudo useradd -m -s /bin/bash "${SERVER_USER}" && echo "${SERVER_USER}:${SERVER_PASS}" | sudo chpasswd && sudo usermod -aG sudo "${SERVER_USER}" && echo "${SERVER_USER} ALL=(ALL:ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/90-${SERVER_USER}" >/dev/null && sudo chmod 440 "/etc/sudoers.d/90-${SERVER_USER}" && sudo visudo -cf "/etc/sudoers.d/90-${SERVER_USER}"
```

Set a custom panel path:

```bash
PANEL_USER="myadmin"
PANEL_PASS="MyStrongPassword!"
PANEL_PATH="panel"

sudo bash scripts/install-3x-ui.sh \
  --username "${PANEL_USER}" \
  --password "${PANEL_PASS}" \
  --path "${PANEL_PATH}"
```

Set a custom panel port:

```bash
PANEL_USER="myadmin"
PANEL_PASS="MyStrongPassword!"
PANEL_PORT="8443"

sudo bash scripts/install-3x-ui.sh \
  --username "${PANEL_USER}" \
  --password "${PANEL_PASS}" \
  --port "${PANEL_PORT}"
```

Pin a specific 3x-ui version:

```bash
PANEL_USER="myadmin"
PANEL_PASS="MyStrongPassword!"
XUI_VERSION="v2.6.5"

sudo bash scripts/install-3x-ui.sh \
  --username "${PANEL_USER}" \
  --password "${PANEL_PASS}" \
  --version "${XUI_VERSION}"
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
- `--force` (optional): force reinstall even if `3x-ui` is already healthy/running.
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
- SSH password authentication is enabled by scanning:
  - `/etc/ssh/sshd_config`
  - `/etc/ssh/sshd_config.d/*.conf`
  and replacing `PasswordAuthentication no` with `yes`, or adding a drop-in if missing.
- Panel port is set to `2053` by default.
- Panel and Linux credentials can be shared or separate.
- If panel is already healthy and running, reinstall is skipped unless `--force` is passed.
- Linux user gets `NOPASSWD` sudo (`ALL=(ALL:ALL) NOPASSWD:ALL`).
- `sudo`, `nload`, `fzf`, and `figlet` are installed during dependency setup.
- Installer sets credentials and path after unpacking 3x-ui files.
- Service is enabled and started automatically.

## Cloud-init Reboot Behavior
- `runcmd` runs once per instance on first boot, not on every reboot.
- It runs again only if you reprovision the server or manually clean cloud-init state.

## Validation Commands
```bash
bash -n scripts/install-3x-ui.sh
bash scripts/install-3x-ui.sh --help
bash scripts/install-3x-ui.sh --username test --password test --dry-run
```
