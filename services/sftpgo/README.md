# SFTPGo — Debian homelab

This Compose project runs `drakkan/sftpgo:v2.7.6` and is managed by a systemd service. Install it under `~/homelab/services/sftpgo/`.

## Prerequisites

- Docker Engine and Docker Compose plugin installed on the Debian server.
- External ext4 disk labeled `homelab-hdd`, mounted at `/mnt/homelab-hdd` with a UUID entry in `/etc/fstab`.
- Configure that disk first using `~/homelab/setup/setup-hdd.sh` if necessary.
- The laptop's IP should have a DHCP reservation so it remains stable.
- OpenSSL installed (`sudo apt install openssl` if missing).

## Install or repair

From this folder:

```bash
chmod +x service-sftpgo.sh
sudo ./service-sftpgo.sh install
sudo ./service-sftpgo.sh status
docker compose ps
```

`install` is safe to rerun: it creates absent `state/` and `config/` folders, generates a self-signed HTTPS certificate if absent, installs/enables its systemd unit, and **restarts** the service even if systemd previously reported `active (exited)`. It does not format or relabel the disk.

**Warning:** Deleting `state/` or `config/` destroys SFTPGo state, including local database/accounts, host keys and HTTPS certificates. The deployment can recreate the directories, but cannot recover deleted accounts or keys. Back them up before clearing them.

## Storage

| Debian host | Container | Purpose |
|---|---|---|
| `./state/` (SSD) | `/srv/sftpgo` | Database, backups, application state |
| `./config/` (SSD) | `/var/lib/sftpgo` | Working directory, host keys, self-signed HTTPS certificate |
| `/mnt/homelab-hdd/sftpgo-data/` (USB HDD) | `/srv/sftpgo/data` | SFTP user files |

The HDD is checked for an exact mount, ext4 filesystem, `homelab-hdd` label, and a UUID matching `/etc/fstab` **before service startup**. Docker's independent restart policy is disabled; systemd runs the check on startup. Do not run plain `docker compose up -d` when the USB disk may be missing because that bypasses the script's HDD verification.

## Network

`service-sftpgo.sh` discovers the Debian server's primary IPv4 address at managed startup and writes `LAN_IP=...` into `.env`. Docker Compose uses that IP for SFTP and HTTPS. A default IPv4 route is required. If the LAN address changes, the saved self-signed TLS certificate will no longer match: renew it deliberately after backing up the old cert/key.

- SFTP: `<server-ip>:2022` (SFTP client, not a browser)
- WebClient: `https://<server-ip>:8443/web/client` (LAN-facing HTTPS)
- WebAdmin: `http://127.0.0.1:8080/web/admin` (only over SSH tunnel)

On Linux Mint, forward the admin port:

```bash
ssh -L 8080:127.0.0.1:8080 homelab
```

Then open `http://127.0.0.1:8080/web/admin` on Linux Mint. The generated certificate is self-signed, so LAN browsers won't trust it until you explicitly configure trust. Never distribute the `.key` file.

## Operations

```bash
sudo systemctl restart homelab-sftpgo
sudo systemctl status homelab-sftpgo
sudo ./service-sftpgo.sh status
sudo ./service-sftpgo.sh logs
```

For a fresh start after deleting persistent directories, rerun `sudo ./service-sftpgo.sh install`. Check `docker compose ps`, `sudo journalctl -u homelab-sftpgo -n 80 --no-pager`, and `sudo docker compose logs --tail=80` if anything fails.

## Security notes

Admin's HTTP port is published only on host loopback. The LAN HTTPS listener has WebAdmin disabled; REST API remains enabled for WebClient and requires SFTPGo authentication and authorization. Docker-published ports can bypass simple UFW expectations. Do not forward ports 8443 or 2022 to the internet. The intended protection against a missing HDD is systemd startup ordering and the checked start command; Docker access remains root-equivalent and can bypass it.
