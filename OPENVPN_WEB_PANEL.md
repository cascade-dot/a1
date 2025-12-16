# 🌐 OpenVPN Web Management Panel

## Overview

The OpenVPN Web Management Panel is a built-in Flask-based web interface for managing OpenVPN clients and configurations. It provides a complete web UI with authentication, client management, and configuration generation.

## Features

### 🔐 Authentication
- **Username/Password Login** - Secure authentication
- **Session Management** - Auto-logout after 1 hour of inactivity
- **Multi-user Support** - Create multiple admin/user accounts
- **Password Hashing** - SHA256 password encryption
- **Admin Panel** - Manage users and change passwords

### 👥 Client Management
- **Create Clients** - Generate new OpenVPN client certificates
- **Download Configs** - Get `.ovpn` configuration files
- **QR Codes** - Generate scannable QR codes for mobile apps
- **List Clients** - View all configured clients
- **Revoke Access** - Immediately revoke client certificates
- **Certificate Lifecycle** - Automatic CRL (Certificate Revocation List) handling

### 📊 Server Information
- **Server Status** - Real-time VPN service status
- **Server IP** - Public IP address (auto-detected)
- **Port Information** - Current listening port
- **Client Statistics** - Total and configured client count

### 🎨 User Interface
- **Modern Design** - Clean, responsive interface
- **Dark Theme** - Easy on the eyes
- **Mobile Friendly** - Works on phones and tablets
- **Real-time Updates** - Auto-refresh every 30 seconds

## Installation

### Automatic (during OpenVPN setup)
The panel is installed automatically when you run:
```bash
sudo bash <(curl -s https://raw.githubusercontent.com/adminbk/cascade-vpn-universal/main/cascade-vpn)
# Select: [3] OpenVPN
```

### Manual Installation
```bash
cd /etc/openvpn
bash services/openvpn/install.sh
```

## Access

### URL
```
https://your-server-ip:8443
```

### Default Credentials
- **Username**: `admin`
- **Password**: Shown in console output during installation

Check logs for password:
```bash
grep -i password /var/log/openvpn/ui-setup.log
# Or view recent service output
journalctl -u openvpn-ui -n 50
```

## Using the Panel

### 1. Login
```
Visit https://your-server-ip:8443
Enter admin credentials
```

### 2. View Dashboard
- Server status (Running/Stopped)
- Current clients count
- Server IP and port

### 3. Create New Client
```
Click "+ Add Client"
Enter client name (alphanumeric, dash, underscore only)
Click "Create"
```

The system will:
1. Generate client certificate
2. Create `.ovpn` configuration file
3. Make it ready for download

### 4. Download Configuration
```
Click "⬇️ Download" button next to client
Save the .ovpn file
```

### 5. Generate QR Code
```
Click "📱 QR Code" button
Scan with OpenVPN mobile app
```

Perfect for mobile client setup without manual file transfer!

### 6. Revoke Client
```
Click "🗑️ Revoke" button
Confirm deletion
Client certificate is immediately revoked
```

### 7. Manage Users (Admin only)
```
Click "⚙️ Settings"
Add new users
Change your password
View all system users
```

## Configuration Files

### Panel Location
```
/opt/openvpn-ui/
├── openvpn-ui.py          # Main application
└── templates/
    ├── login.html          # Login page
    ├── dashboard.html      # Main dashboard
    └── settings.html       # Settings page
```

### User Database
```
/etc/openvpn/openvpn-ui-users.json
```

Contains user accounts with hashed passwords:
```json
{
  "admin": {
    "password_hash": "sha256_hash_here",
    "created": "2025-12-16T10:30:00",
    "role": "admin"
  },
  "user1": {
    "password_hash": "sha256_hash_here",
    "created": "2025-12-16T10:35:00",
    "role": "user"
  }
}
```

### Service
```bash
# Check status
sudo systemctl status openvpn-ui

# View logs
sudo journalctl -u openvpn-ui -f

# Restart service
sudo systemctl restart openvpn-ui

# Stop service
sudo systemctl stop openvpn-ui
```

## Security

### HTTPS
- SSL certificate auto-generated (self-signed)
- All traffic encrypted
- Add your own certificate if needed

### Authentication
- Session timeout: 1 hour
- Login required for all pages
- Password hashing: SHA256
- User roles: admin, user

### File Permissions
- User database: 600 (root-only)
- Client configs: 600 (root-only)
- Service runs as root (required for cert operations)

### Best Practices
1. **Change Default Password** - First thing after login
2. **Use Strong Passwords** - At least 12 characters
3. **Limited Admin Access** - Use least privilege principle
4. **HTTPS Only** - Never use HTTP for management
5. **Firewall Rules** - Restrict access to trusted IPs

## Client Configuration File Format

Generated `.ovpn` files include:
- CA certificate (inline)
- Client certificate (inline)
- Client private key (inline)
- TLS authentication key (inline)
- Server endpoint (IP and port)
- Encryption settings (AES-256-GCM)
- DNS settings
- Compression settings

**No external files needed** - Single `.ovpn` file contains everything!

## Troubleshooting

### Can't access panel
```bash
# Check if service is running
sudo systemctl is-active openvpn-ui

# Check logs
sudo journalctl -u openvpn-ui -n 50

# Restart service
sudo systemctl restart openvpn-ui
```

### Forgot admin password
```bash
# Reset to random password (check logs for it)
sudo systemctl restart openvpn-ui

# OR manually set password
sudo python3 -c "
import json, hashlib
users = json.load(open('/etc/openvpn/openvpn-ui-users.json'))
users['admin']['password_hash'] = hashlib.sha256(b'newpassword').hexdigest()
json.dump(users, open('/etc/openvpn/openvpn-ui-users.json', 'w'), indent=2)
"
```

### Certificate issues
```bash
# Regenerate SSL certificate
sudo systemctl restart openvpn-ui
```

### Port 8443 already in use
Edit `/opt/openvpn-ui/openvpn-ui.py` and change port:
```python
app.run(host='0.0.0.0', port=9443, ...)  # Change 8443 to 9443
```

Then restart:
```bash
sudo systemctl restart openvpn-ui
```

## API Endpoints

The panel provides REST APIs for programmatic access:

### Client Management
```bash
# List all clients
curl -X GET https://server:8443/api/clients

# Create client
curl -X POST https://server:8443/api/client/create \
  -H "Content-Type: application/json" \
  -d '{"name":"user1"}'

# Download config
curl https://server:8443/api/client/download/user1 \
  -o user1.ovpn

# Get QR code
curl https://server:8443/api/client/qr/user1

# Revoke client
curl -X POST https://server:8443/api/client/revoke \
  -H "Content-Type: application/json" \
  -d '{"name":"user1"}'
```

### Server Info
```bash
# Get server status
curl https://server:8443/api/server/info
```

**Note**: All API endpoints require valid session/authentication

## Integration with Cascade Mode

The web panel works seamlessly with cascade mode:

1. **Install OpenVPN on primary server** (cascade remote target)
2. **Panel is installed automatically**
3. **Access from anywhere** - Use primary server's public IP
4. **Generate configs there** - Clients connect through cascade tunnel
5. **Port forwarding** - 8443 can be forwarded if needed

Example:
```bash
# Setup cascade to remote server
sudo bash <(curl -s https://...cascade-vpn)
# Select: [2] Cascade mode
# Select: [3] OpenVPN
# Web panel available at: https://primary-server:8443
```

## Comparison with Other Solutions

| Feature | OpenVPN-UI (This) | Pritunl | OpenVPN-Admin |
|---------|------------------|---------|--------------|
| **Open Source** | ✅ Yes | ❌ No | ✅ Yes |
| **Web Interface** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Authentication** | ✅ Yes | ✅ Yes | ✅ Yes |
| **QR Codes** | ✅ Yes | ✅ Yes | ❌ No |
| **Multi-user** | ✅ Yes | ✅ Yes | ❌ No |
| **Certificate Mgmt** | ✅ Automatic | ✅ Automatic | ✅ Automatic |
| **Lightweight** | ✅ 500 lines | ❌ Heavy | ✅ Light |
| **Cost** | ✅ Free | ❌ Paid | ✅ Free |
| **Integration** | ✅ Cascade VPN | ❌ Standalone | ❌ Standalone |

## Future Enhancements

Potential additions:
- [ ] Traffic statistics per client
- [ ] Bandwidth limiting per client
- [ ] Client connection status
- [ ] Automatic certificate renewal
- [ ] Two-factor authentication
- [ ] Audit logs
- [ ] Backup/restore functionality
- [ ] Docker container support

## Support

For issues or questions:
- GitHub Issues: https://github.com/adminbk/cascade-vpn-universal/issues
- Documentation: See CASCADE_ARCHITECTURE.md

---

**Version**: 1.0.0 | December 2025 | MIT License
