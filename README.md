<div align="center">

<img src="icon.png" alt="Aether VPN Logo" width="100" height="100" style="border-radius: 20px;" />

# Aether VPN Panel
### Modern, Ultra-Fast Xray & V2Ray Web Management Dashboard

[![GitHub release](https://img.shields.io/github/v/release/xoxod33p/aether-panel?color=white&label=Release&style=flat-square)](https://github.com/xoxod33p/aether-panel/releases)
[![License](https://img.shields.io/github/license/xoxod33p/aether-panel?color=white&style=flat-square)](LICENSE)
[![Repo Size](https://img.shields.io/github/repo-size/xoxod33p/aether-panel?color=neutral&style=flat-square)](https://github.com/xoxod33p/aether-panel)

</div>

---

**Aether VPN** is a modern, high-performance web management panel for Xray and V2Ray. Featuring a sleek, minimalist dark cyber theme derived from Aether, complete English localization, multi-protocol support, automated SSL lifecycle management, and real-time server telemetry.

---

## ⚡ Features

- **Aether Minimalist Dark UI**: Precision-engineered dark aesthetic (`#000000` / `#0d0d0d`), high-contrast typography, and smooth glassmorphism.
- **100% English Interface**: Web dashboard, server terminal menus, dialogs, and setup wizard.
- **Full Protocol Suite**: VMess, VLESS, Trojan, Shadowsocks, Dokodemo-door, Socks, and HTTP.
- **Advanced Transports**: TCP, mKCP, WebSocket, HTTP/2, gRPC, and QUIC.
- **TLS / XTLS & Flow**: Full SNI routing, automatic fallback configuration, and XTLS support.
- **Automated SSL Lifecycle**: Built-in Acme.sh automation for 1-click Let's Encrypt certificates with auto-renewal.
- **Resource Telemetry**: Live visual meters for CPU, Memory, Swap, Disk, and real-time bandwidth throughput (↑ / ↓).
- **Client & Traffic Controls**: Per-user bandwidth quotas, expiration timers, and instant QR code sharing links.
- **Dedicated CLI Utility**: Native `aether-vpn` management CLI for terminal service control, credential resets, and diagnostics.

---

## 🚀 Quick Install & Upgrade

Run this single command on your Linux VPS (Debian 9+, Ubuntu 16+, CentOS 7+, Fedora 29+):

```bash
bash <(curl -Ls https://raw.githubusercontent.com/xoxod33p/aether-panel/main/install.sh)
```

---

## 🛠️ Management CLI Commands

Access the server management menu anytime by typing:

```bash
aether-vpn
```

| Command | Action |
| :--- | :--- |
| `aether-vpn` | Open interactive CLI menu |
| `aether-vpn start` | Start Aether VPN daemon |
| `aether-vpn stop` | Stop Aether VPN daemon |
| `aether-vpn restart` | Restart Aether VPN daemon |
| `aether-vpn status` | View service status |
| `aether-vpn enable` | Enable auto-start on boot |
| `aether-vpn disable` | Disable auto-start on boot |
| `aether-vpn log` | View live system logs |
| `aether-vpn update` | Update panel to latest release |

---

## 📦 Manual Installation

1. Switch to root user:
   ```bash
   sudo su
   cd ~
   ```
2. Download and unpack the release archive:
   ```bash
   rm -rf /usr/local/aether-vpn/ /usr/bin/aether-vpn
   tar -zxvf aether-vpn-linux-amd64.tar.gz
   chmod +x aether-vpn/aether-vpn aether-vpn/bin/xray-linux-*
   curl -Ls https://raw.githubusercontent.com/xoxod33p/aether-panel/main/aether-vpn.sh -o /usr/bin/aether-vpn
   chmod +x /usr/bin/aether-vpn
   cp -f aether-vpn/aether-vpn.service /etc/systemd/system/
   mv aether-vpn/ /usr/local/
   systemctl daemon-reload
   systemctl enable aether-vpn
   systemctl restart aether-vpn
   ```

---

## 🐳 Docker Deployment

```bash
docker run -itd --network=host \
    -v $PWD/db/:/etc/aether-vpn/ \
    -v $PWD/cert/:/root/cert/ \
    --name aether-vpn --restart=unless-stopped \
    xoxod33p/aether-panel:latest
```

---

## 🔒 Security Best Practices

1. Change the default port from standard ranges.
2. Configure a custom domain name and apply an SSL certificate using option 16 in the CLI.
3. Access the web panel securely over HTTPS.

---

## 📄 License

Distributed under the [GPL-3.0 License](LICENSE).
