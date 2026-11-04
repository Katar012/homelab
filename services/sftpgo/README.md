# SFTPGo homelab service

## Purpose

SFTPGo v2.7.6 with WebClient HTTPS available on the LAN, WebAdmin accessible only via an SSH tunnel, and SFTP available on TCP 2022. The files/database are persistent across container recreation.

## Current endpoints

- WebClient: `https://192.168.1.19:8443/web/client`
- WebAdmin: `http://127.0.0.1:8080/web/admin` from desktop after running `ssh -L 8080:127.0.0.1:8080 homelab`
- SFTP: `192.168.1.19:2022`

## Storage

- SSD: `./state` -> `/srv/sftpgo`
- SSD: `./config` -> `/var/lib/sftpgo` (including `certs/webclient.crt` and `.key`)
- External HDD: `/mnt/homelab-hdd/sftpgo-data` -> `/srv/sftpgo/data`

The project needs the existing systemd mount and storage setup. The service script verifies the mounted ext4 disk's label and UUID against `/etc/fstab` before starting. Docker's independent restart is disabled to prevent bypassing this check.

## Update existing installation

1. Back up the existing `compose.yaml` and `service-sftpgo.sh` in `~/homelab/services/sftpgo`.
2. Replace both with the new copies; retain your existing `state/` and `config/` folders. **Do not remove the data directories or run `docker compose down -v`.**
3. Ensure your laptop still uses the LAN IP `192.168.1.19`. If it changes, update both port bindings in `compose.yaml` and `lan_ip` in the service script before installing. When renewing the certificate, generate a new certificate for the new IP.
4. On Debian: `sudo ./service-sftpgo.sh install` (generates the certificate if absent and restarts/starts through systemd). If the existing service is already running, use `sudo systemctl restart homelab-sftpgo.service` to recreate the container with the new configuration. Run `sudo docker compose ps` and `sudo docker compose logs --tail=50` to check.
5. Confirm you can access WebClient over HTTPS from a LAN device, and WebAdmin **only** via the SSH tunnel.

## HTTPS trust

`service-sftpgo.sh` generates a self-signed certificate with an IP SAN for `192.168.1.19`, valid for 365 days. The connection is encrypted, but browsers do not automatically trust the certificate and will display a warning. For trusted browser connections, replace it with a certificate signed by a CA trusted by every client. Do not distribute or import the private key (`webclient.key`).

The script reuses existing TLS files if both are present. It will not silently overwrite them. If you intentionally rotate the certificate, first back up the files and follow a controlled renewal process.

## Network / threat model

WebAdmin is disabled on the HTTPS binding; it listens on a separate container port that Docker publishes to **host** loopback only. LAN clients cannot normally reach `127.0.0.1:8080` on the laptop. HTTPS WebClient listens at the laptop's LAN IP, not on every host interface. Do not forward 8443 or 2022 on your internet router.

The REST API must remain enabled for WebClient functionality, so API security still depends on SFTPGo's authorization. Admin-token and admin API-key login methods are disabled on the LAN listener; authenticated admin API activity should still be tested against your threat model. Other local host users with Docker access have effectively root-level privileges. Docker-published ports can bypass UFW filtering; use router/firewall network policy if your LAN is not trusted.
