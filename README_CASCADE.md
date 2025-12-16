# 🚀 Cascade VPN Universal - One-Line Installation

**The simplest way to deploy a cascade VPN with port forwarding**

```bash
sudo bash <(curl -s https://raw.githubusercontent.com/adminbk/cascade-vpn-universal/main/cascade-vpn)
```

---

## 📖 What is Cascade VPN?

Cascade VPN allows you to:
1. **Setup VPN directly** on a single server
2. **Or use cascade mode**: VPN on one server, port forwarding on another

```
DIRECT MODE:
Client → VPN Server → Internet

CASCADE MODE:
Client → Local Server (Port Forward) → Primary Server (VPN) → Internet
```

---

## 🎯 Two Installation Modes

### Mode 1: Direct Installation ⚡
```bash
sudo bash <(curl -s https://raw.githubusercontent.com/adminbk/cascade-vpn-universal/main/cascade-vpn)
# Choose [1] Install VPN on this server
# Select protocol (VLESS+Reality / WireGuard / OpenVPN)
# Done! Clients connect directly
```

### Mode 2: Cascade Setup 🔄
```bash
# On your LOCAL server (acts as port forwarder)
sudo bash <(curl -s https://raw.githubusercontent.com/adminbk/cascade-vpn-universal/main/cascade-vpn)
# Choose [2] Setup port forwarding
# Enter PRIMARY server IP, username, password
# Select VPN protocol
# Script does everything automatically!
```

---

## 🔐 VPN Protocols

### ⭐ VLESS + Reality (Recommended)
- **Modern** - Latest Xray technology
- **Fast** - Minimal overhead  
- **Stealthy** - Disguised as normal HTTPS traffic
- **Port**: 443 (configurable)
- **Clients**: V2rayN (Windows/Mac), Xray (Linux), NekoBox (Android), ShadowRocket (iOS)

### ⭐ WireGuard (Recommended)
- **Simple** - Minimal configuration
- **Fast** - Kernel-level performance
- **Universal** - Works everywhere
- **Port**: 51820 UDP (configurable)
- **Clients**: WireGuard App (all platforms)

### OpenVPN
- **Compatible** - Works on all platforms
- **Proven** - Battle-tested technology
- **Flexible** - Many customization options
- **Port**: 1194 (configurable)
- **Clients**: OpenVPN Connect, TunnelBlick

---

## 📱 Recommended Client Applications

| VPN | Windows | macOS | Linux | iOS | Android |
|-----|---------|-------|-------|-----|---------|
| **VLESS+Reality** | V2rayN | V2rayN | Xray CLI | ShadowRocket | NekoBox |
| **WireGuard** | WireGuard | WireGuard | WireGuard | WireGuard | WireGuard |
| **OpenVPN** | OpenVPN Connect | TunnelBlick | OpenVPN | OpenVPN Connect | OpenVPN Connect |

---

## 🛠️ Port Forwarding Examples

### Scenario 1: VLESS+Reality
```
Primary Server: 192.168.1.100:443
Local Server forwards: 0.0.0.0:8443 → Primary:443

Client connects to: your_local_server:8443
```

### Scenario 2: WireGuard
```
Primary Server: 192.168.1.100:51820 (UDP)
Local Server forwards: 0.0.0.0:51820 → Primary:51820

Client connects to: your_local_server:51820
```

### Custom Port Mapping
```
You can map ANY local port to ANY remote port
Example: Local 8000 → Remote 443 (HTTPS)
```

---

## 🔧 What Gets Installed?

**On Primary Server:**
- ✅ VPN service (VLESS+Reality / WireGuard / OpenVPN)
- ✅ System optimization (kernel tuning)
- ✅ SSL certificates (Let's Encrypt ready)
- ✅ Client configs generation
- ✅ Firewall rules
- ✅ Monitoring & logs

**On Local Server (Cascade mode):**
- ✅ iptables port forwarding rules
- ✅ IP forwarding enabled
- ✅ SSH tunnel management
- ✅ Monitoring & logs

---

## ⚙️ Requirements

### Hardware
- 1+ Core CPU
- 512 MB RAM minimum
- 500 MB free disk space

### Operating System
- Ubuntu 18.04+
- Debian 10+
- CentOS 7+
- RHEL 7+

### Network
- Root access (sudo)
- For cascade: SSH access between servers
- Open necessary ports (443, 51820, etc.)

---

## 🚨 Troubleshooting

```bash
# Check internet connection
ping 8.8.8.8

# View installation logs
sudo tail -f /var/log/cascade-vpn/install.log

# Check if VPN is running
sudo systemctl status cascade-vpn

# View forwarding rules
sudo iptables -t nat -L -n -v

# Verify port is listening
sudo netstat -tlnp | grep cascade
```

---

## 📚 Full Documentation

- **[CASCADE_ARCHITECTURE.md](CASCADE_ARCHITECTURE.md)** - Detailed architecture & protocol comparison
- **[INSTALL_GUIDE.md](INSTALL_GUIDE.md)** - Complete installation guide  
- **[DEVELOPMENT_REPORT.md](DEVELOPMENT_REPORT.md)** - Technical details

---

## 🔒 Security

1. **Always use strong passwords**
2. **Change default ports** after installation
3. **Use SSH keys** instead of passwords when possible
4. **Enable firewall** on both servers
5. **Keep system updated**: `apt update && apt upgrade`

---

## 🤝 Support

- **GitHub**: https://github.com/adminbk/cascade-vpn-universal
- **Issues**: https://github.com/adminbk/cascade-vpn-universal/issues
- **Docs**: See links above

---

## 📝 License

MIT License - Free for personal and commercial use

---

**Ready to start?**

```bash
sudo bash <(curl -s https://raw.githubusercontent.com/adminbk/cascade-vpn-universal/main/cascade-vpn)
```

**Version**: 1.0.0 | **Updated**: December 2025
