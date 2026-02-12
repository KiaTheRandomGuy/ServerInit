# ServerInit

Cloud-init focused server bootstrap scripts.

This repository currently contains one installer that installs only `3x-ui` and configures it for cloud-init usage:
- Username and password are set from CLI flags (`--username`, `--password`).
- Panel path is optional (`--path`) and defaults to root (`/`).
- SSL cert setup is skipped by default (HTTP panel).
- `apt-get update` is always executed before install.

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

Set a custom panel path:

```bash
sudo bash scripts/install-3x-ui.sh \
  --username "myadmin" \
  --password "MyStrongPassword!" \
  --path "panel"
```

Pin a specific 3x-ui version:

```bash
sudo bash scripts/install-3x-ui.sh \
  --username "myadmin" \
  --password "MyStrongPassword!" \
  --version "v2.6.5"
```

## Parameters
- `--username` (required): panel username.
- `--password` (required): panel password.
- `--path` (optional): custom panel URI path.
  - Example: `--path panel` gives `/panel/`.
  - Default: root path `/` (no custom path).
- `--version` (optional): release tag to install.
  - Default: latest release from `MHSanaei/3x-ui`.
- `--dry-run` (optional): prints commands without executing.

## Cloud-init Example
Use `cloud-init/3x-ui-cloud-init.yaml` and replace:
- `<YOUR_GITHUB_USER>`
- `<YOUR_REPO>`
- default username/password values

Example with custom path:

```yaml
#cloud-config
package_update: true
packages:
  - curl

runcmd:
  - [bash, -lc, "curl -fsSL https://raw.githubusercontent.com/<YOUR_GITHUB_USER>/<YOUR_REPO>/main/scripts/install-3x-ui.sh -o /usr/local/bin/install-3x-ui.sh"]
  - [chmod, "+x", "/usr/local/bin/install-3x-ui.sh"]
  - [bash, "-lc", "/usr/local/bin/install-3x-ui.sh --username 'myadmin' --password 'MyStrongPassword!' --path 'panel'"]
```

## Behavior Notes
- Script is designed for Debian/Ubuntu (`apt-get` + `systemd` required).
- SSL cert config inside 3x-ui is reset/disabled by default.
- Installer sets credentials and path after unpacking 3x-ui files.
- Service is enabled and started automatically.

## Validation Commands
```bash
bash -n scripts/install-3x-ui.sh
bash scripts/install-3x-ui.sh --help
bash scripts/install-3x-ui.sh --username test --password test --dry-run
```
