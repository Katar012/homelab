# HOMELAB

Contenerized services for a Debian 13 Laptop

## REQUIREMENTS:

1. This setup assumes there are two Linux PCs, a server (Laptop) and a client (Desktop)
2. Static server IP: 192.168.1.19
3. Static client IP: 192.168.1.5
4. Server and Client usernames: juan
5. This setup assumes there's one EXT4 HDD labeled homelab-hdd connected via USB to the server

## SETUP
---

1. `git clone https://github.com/Katar012/homelab`
2. `cd homelab/setup/`
3. `chmod +x setup-laptop.sh setup-desktop.sh setup-homelab-hdd.sh`
4. Execute in order:
    - In server `./setup-laptop.sh`
    - In client `./setup-desktop.sh`
    - `sudo ./setup-homelab-hdd.sh` (make sure to copy and paste homelab-hdd's UUID when prompetd)


## SERVICES
---

No service will be enabled by default, to set them up follow these instructions below

---

### SFTPGo

File transfer and local cloud service for common files.

In server:
1. `cd homelab/services/sftpgo/`
2. `chmod +x service-sftpgo.sh`
3. `sudo ./service-sftpgo.sh install`

In client:
1. `ssh -L 8080:127.0.0.1:8080 homelab`
2. on web browser http://127.0.0.1:8080/web/admin
3. setup admin user




