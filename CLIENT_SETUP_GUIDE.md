# 📱 Client Setup Guide - Cascade VPN Universal

## Quick Start

Your VPN is installed and waiting! Here's how to connect from your device.

---

## 🖥️ WINDOWS

### VLESS + Reality Setup

**Applications (choose one):**
- V2rayN - https://github.com/2dust/v2rayN/releases
- Clash for Windows - https://github.com/Fndroid/clash_for_windows_pkg/releases
- NekoBox - https://github.com/MatsuriDayo/NekoBoxForAndroid (portable)

**Steps:**
1. Download and install application
2. Download config file from your server (`client-config.json`)
3. Import config file (File → Import → URL/File)
4. Click "Connect" or toggle VPN on

### WireGuard Setup

**Application:**
- WireGuard App - https://www.wireguard.com/install

**Steps:**
1. Download WireGuard from official site
2. Download config file from your server (`client.conf`)
3. Open WireGuard app
4. Click "Import Tunnel(s) from File"
5. Select downloaded config file
6. Click the tunnel name to connect

### WireGuard with UDP2Raw (if blocked)

If WireGuard doesn't work (blocked by ISP), use UDP2Raw masking:

**Setup on Windows:**
1. Download UDP2Raw: https://github.com/wangyu-/udp2raw-tunnel
2. Extract the `.exe` file
3. Create batch file `start-vpn.bat`:
```batch
@echo off
REM UDP2Raw wrapper for WireGuard
udp2raw.exe -c -r YOUR_SERVER_IP:443 -l 127.0.0.1:51820 -k YOUR_PASSWORD --cipher xor

REM Then in WireGuard config, change Endpoint from:
REM   Endpoint = YOUR_SERVER_IP:51820
REM To:
REM   Endpoint = 127.0.0.1:51820
```
4. Run the batch file before connecting with WireGuard
5. Open WireGuard and activate tunnel

### OpenVPN Setup

**Application:**
- OpenVPN Connect - https://openvpn.net/client-connect-vpn

**Steps:**
1. Download and install OpenVPN Connect
2. Download config file from server (`client.ovpn`)
3. Open OpenVPN Connect
4. File → Import → Select config
5. Click Connect

---

## 🍎 macOS

### VLESS + Reality Setup

**Applications (choose one):**
- V2rayN for macOS - https://github.com/2dust/v2rayN/releases
- NekoBox - App Store
- Clash for macOS - https://github.com/Fndroid/clash_for_windows_pkg

**Steps:**
1. Install from link above
2. Download config file
3. Import config in application
4. Toggle VPN on

### WireGuard Setup

**Application:**
- WireGuard for macOS - https://www.wireguard.com/install

**Steps:**
1. Install via App Store or official site
2. Download config file
3. Open WireGuard
4. File → Import from File
5. Select config
6. Click Activate

### WireGuard with UDP2Raw

**Setup:**
```bash
# Install via Homebrew
brew install udp2raw

# Create wrapper script: ~/start-vpn.sh
#!/bin/bash
udp2raw -c -r YOUR_SERVER_IP:443 \
  -l 127.0.0.1:51820 \
  -k YOUR_PASSWORD \
  --cipher xor

# Make executable
chmod +x ~/start-vpn.sh

# Run before WireGuard
./start-vpn.sh

# In WireGuard config, change:
# Endpoint = 127.0.0.1:51820
```

### OpenVPN Setup

**Application:**
- Tunnelblick - https://tunnelblick.net
- TunnelBlick has native OpenVPN support

**Steps:**
1. Download and install Tunnelblick
2. Download `.ovpn` config
3. Double-click config file
4. Click Connect

---

## 🐧 Linux (Desktop)

### VLESS + Reality Setup

**Applications:**
- Xray CLI (terminal) - https://github.com/XTLS/Xray-core
- V2rayN (with Wine) - https://github.com/2dust/v2rayN
- NekoBox - https://github.com/MatsuriDayo/NekoBoxForAndroid

**GUI Method (recommended):**
```bash
# Install NekoBox (easiest)
wget https://github.com/MatsuriDayo/NekoBoxForAndroid/releases/download/.../...
tar -xzf nekobox.tar.gz
./nekobox

# Then import your config file via GUI
```

**CLI Method (if no GUI):**
```bash
# Create config: ~/.config/xray/config.json
# Download from server and place there

# Install Xray
sudo bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# Start service
sudo systemctl start xray
sudo systemctl enable xray

# Check status
sudo systemctl status xray
```

### WireGuard Setup

**Application:**
```bash
# Install (most distros)
sudo apt install wireguard wireguard-tools

# Or on Fedora/RHEL:
sudo dnf install wireguard-tools

# Or on macOS:
brew install wireguard-tools
```

**Setup:**
```bash
# Download config from server to: /tmp/wg0.conf
sudo cp /tmp/wg0.conf /etc/wireguard/

# Make interface
sudo wg-quick up wg0

# Check status
sudo wg show

# Turn off
sudo wg-quick down wg0
```

### WireGuard with UDP2Raw

**Setup:**
```bash
# Install dependencies
sudo apt install build-essential git

# Download UDP2Raw
wget https://github.com/wangyu-/udp2raw-tunnel/releases/download/[version]/udp2raw_linux_[arch].tar.gz
tar -xzf udp2raw_linux_[arch].tar.gz

# Create wrapper script: ~/wg-with-udp2raw.sh
#!/bin/bash

# Start UDP2Raw
./udp2raw -c \
  -r YOUR_SERVER_IP:443 \
  -l 127.0.0.1:51820 \
  -k YOUR_PASSWORD \
  --cipher xor &

# Edit your WireGuard config to use localhost
# Endpoint = 127.0.0.1:51820

# Start WireGuard
sudo wg-quick up wg0

# Make executable and run
chmod +x ~/wg-with-udp2raw.sh
./wg-with-udp2raw.sh
```

### OpenVPN Setup

**Installation:**
```bash
sudo apt install openvpn

# Copy config
sudo cp client.ovpn /etc/openvpn/client/

# Start
sudo systemctl start openvpn-client@client

# Check status
sudo systemctl status openvpn-client@client
```

---

## 📱 iOS

### VLESS + Reality Setup

**Applications:**
1. **Stash** - https://stash.ws (Recommended)
   - Most reliable for VLESS
   - Free + Pro options
   
2. **ShadowRocket** - App Store (Paid)
   - Powerful and flexible
   - Best UI
   
3. **Quantumult X** - App Store (Paid)
   - Advanced routing
   - Script support

**Setup (Stash):**
1. Download Stash from App Store
2. Get config URL from server
3. Open Stash → Settings → Subscription
4. Add new subscription URL
5. Pull config
6. Toggle VPN on

**Setup (ShadowRocket):**
1. Download ShadowRocket
2. Tap + button
3. Paste config or scan QR code
4. Save and toggle on

### WireGuard Setup

**Application:**
- WireGuard - App Store (Free)

**Setup:**
1. Download WireGuard
2. Tap + (add tunnel)
3. Create from File or QR Code
4. Paste config contents
5. Save
6. Toggle to activate

---

## 🤖 Android

### VLESS + Reality Setup

**Applications:**
1. **NekoBox** - https://github.com/MatsuriDayo/NekoBoxForAndroid
   - Best for Android
   - Free and open-source
   
2. **V2rayNG** - https://github.com/2dust/v2rayNG
   - Simple and reliable
   - Good UI
   
3. **Clash** - https://github.com/MetaCubeX/ClashMetaForAndroid
   - Powerful
   - Advanced features

**Setup (NekoBox):**
1. Download APK from GitHub releases
2. Install APK
3. Open NekoBox
4. Tap + button
5. Import from clipboard or QR code
6. Tap profile to connect

**Setup (V2rayNG):**
1. Install from GitHub
2. Tap + to add new profile
3. Manual input or scan QR code
4. Save
5. Tap profile to connect

### WireGuard Setup

**Application:**
- WireGuard - Google Play

**Setup:**
1. Install from Play Store
2. Tap + button
3. Create from file or QR
4. Import config file
5. Toggle on

### WireGuard with UDP2Raw

For Android, UDP2Raw requires more complex setup. **Alternatives:**
- Use VLESS + Reality (simpler, just as effective)
- Use Clash with UDP2Raw proxy rule (advanced)
- Try different protocol: OpenVPN may not be blocked

---

## 🔑 Getting Your Config Files

### From Server Terminal:

**For VLESS + Reality:**
```bash
cat /var/cascade-vpn/clients/vless-reality-config.json
# Or download directly
scp admin@server:/var/cascade-vpn/clients/vless-reality-config.json ./
```

**For WireGuard:**
```bash
# Show config
sudo wg show wg0
# Or get config file
cat /etc/wireguard/wg0.conf
```

**For OpenVPN:**
```bash
cat /var/cascade-vpn/clients/client.ovpn
```

### Via Web Interface (if available):

If wg-easy is installed:
```
http://YOUR_SERVER_IP:51821
```

---

## ✅ Testing Connection

### Windows/macOS/Linux:

```bash
# Check if connected
curl https://ifconfig.me

# Should return server's public IP if connected
# If returns your real IP = not connected
```

### Mobile:

- Open any website (like google.com)
- Check IP at https://whatismyipaddress.com
- Should show server's IP if connected

---

## 🚨 Troubleshooting

### "Can't connect"

**Windows:**
- Check if VPN app is running
- Try running as administrator
- Disable antivirus temporarily
- Check firewall rules: `netstat -ano | findstr :443`

**macOS/Linux:**
- Check interface: `ip addr show` or `ifconfig`
- Check status: `sudo systemctl status cascade-vpn`
- Check logs: `journalctl -u cascade-vpn -f`
- Permissions: Commands may need `sudo`

**Mobile:**
- Check if WiFi/mobile data is on
- Toggle airplane mode on/off
- Reinstall app
- Try different VPN config if available

### "Connection is slow"

- Check server load: `top` or `htop`
- Try different protocol:
  - VLESS+Reality: Low overhead
  - WireGuard: Fastest
  - OpenVPN: Most compatible
- Switch to closer/faster server if available

### "IP is still showing my real location"

- Ensure VPN toggle is ON
- Check if DNS is leaked: https://dnsleaktest.com
- Some apps bypass VPN
- Try "Block unencrypted traffic" setting in VPN app
- Use VPN with killswitch enabled

### "Port is blocked/ISP blocked my VPN"

**Solution 1: Use UDP2Raw masking**
- Makes traffic look like HTTPS
- Most ISPs allow HTTPS

**Solution 2: Change port**
- Ask admin to change from 443 to 8443, 9443, etc
- Or use port 80 (HTTP) if allowed

**Solution 3: Use different protocol**
- VLESS+Reality: Hardest to block
- WireGuard+UDP2Raw: Second hardest
- OpenVPN: Easier to block, try obfuscation

---

## 📚 More Information

**Architecture Details:**
- See: CASCADE_ARCHITECTURE.md

**Server Management:**
- See: HOW_TO_USE.txt

**Troubleshooting Server:**
- See: INSTALL_GUIDE.md

**GitHub Issues:**
- https://github.com/adminbk/cascade-vpn-universal/issues

---

## 🔐 Security Tips

✅ **Always:**
- Connect to official server IPs only
- Verify server fingerprints/certificates
- Use strong passwords if password-protected
- Keep your VPN app updated
- Don't share config files publicly

❌ **Never:**
- Share your private keys
- Store passwords in config files
- Use untrusted public WiFi for setup
- Disable certificate verification
- Disable encryption for "speed"

---

**Version**: 1.0.0 | December 2025
