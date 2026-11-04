# SFTPGo service

For the Debian laptop (`192.168.1.19`) after `setup-laptop.sh` and `setup-homelab-hdd.sh` have been run. This service uses **the existing ext4 disk labeled `homelab-hdd`, mounted at `/mnt/homelab-hdd`**. It does not format the drive.

## Execute:

```bash
chmod +x service-sftpgo.sh
sudo ./service-sftpgo.sh install
```

The installer checks that the mounted ext4 partition's label and UUID match the fstab entry, creates the necessary storage directories, validates Compose, installs `homelab-sftpgo.service` and launches SFTPGo.

## Administration from the client desktop

Use the already configured SSH alias:

```bash
ssh -L 8080:127.0.0.1:8080 homelab
```

Keep that session open; in Desktop's browser open `http://127.0.0.1:8080/web/admin`. Set up the initial administrator, then create users and quotas. In SFTPGo, default user homes are `/srv/sftpgo/data/<username>` (stored on the HDD).

LAN SFTP clients connect to `192.168.1.19` port **2022**, with their *SFTPGo* credentials; host OpenSSH remains separate on port 22.

## Storage mapping

| Laptop host | Container | Purpose |
| --- | --- | --- |
| `~/homelab/services/sftpgo/state` (SSD) | `/srv/sftpgo` | SQLite database, application data and backups |
| `~/homelab/services/sftpgo/config` (SSD) | `/var/lib/sftpgo` | SFTP host keys, working directory |
| `/mnt/homelab-hdd/sftpgo-data` (USB HDD) | `/srv/sftpgo/data` | Uploaded files and user home directories |

Directories are owned by UID/GID 1000 (the official image's default user). Do not recursively change the ownership of the entire USB drive.

## Operations

Recommended service commands (on laptop):

```bash
sudo systemctl status homelab-sftpgo
sudo systemctl restart homelab-sftpgo
sudo systemctl stop homelab-sftpgo
sudo systemctl start homelab-sftpgo
sudo ./service-sftpgo.sh logs
```

`systemctl restart` stops and recreates the container via Compose, preserving bind-mounted data. `systemctl stop` stops it until started again or the next boot (unless disabled); `sudo systemctl disable --now homelab-sftpgo` disables automatic boot startup.

Verify mount and running container:

```bash
findmnt -M /mnt/homelab-hdd
sudo docker compose -f ~/homelab/services/sftpgo/compose.yaml ps
```

## Safety / reboot behavior

- systemd requires the HDD mount before starting SFTPGo. If disconnected at boot, the SFTPGo unit will not start successfully, but `nofail` allows Debian itself to boot. Reconnect, mount and `sudo systemctl start homelab-sftpgo`.
- `BindsTo=` ties SFTPGo's service to the mount unit during systemd-managed unmounts. **Do not physically disconnect the USB HDD while SFTPGo is running.** Sudden disconnects can cause I/O failures and data loss.
- Compose uses `restart: "no"` intentionally: Docker must not bypass the service's mount verification on restart. Start the service through systemd rather than manually running `docker compose up`.
- Compose also uses `create_host_path: false` to avoid Docker creating a missing HDD data folder automatically. It cannot replace the mount verification by itself.
- Web administration is bound to laptop loopback; access by SSH tunnel. Docker-published SFTP port 2022 is bound to `192.168.1.19` but is not LAN-only firewall enforcement. Docker port publishing can bypass UFW. Do not forward ports on the router; add Docker-aware ingress rules for untrusted networks.
- Back up both SSD `state`/`config` **and** HDD user data before reinstalling Debian. The SSD folders are not retained across a full wipe unless backed up.

Official image: https://hub.docker.com/r/drakkan/sftpgo
