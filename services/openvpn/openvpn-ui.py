#!/usr/bin/env python3
# services/openvpn/openvpn-ui.py - OpenVPN Web Management Panel

import os
import sys
import json
import subprocess
import hashlib
import secrets
from datetime import datetime, timedelta
from pathlib import Path
from functools import wraps

from flask import Flask, render_template, request, jsonify, send_file, session, redirect, url_for
import qrcode
from io import BytesIO
import base64

# Configuration
OPENVPN_DIR = "/etc/openvpn"
CLIENTS_DIR = "/var/cascade-vpn/openvpn-clients"
EASYRSA_DIR = f"{OPENVPN_DIR}/easy-rsa"
PKI_DIR = f"{EASYRSA_DIR}/pki"
CONFIG_FILE = f"{OPENVPN_DIR}/server.conf"
USERS_FILE = "/etc/openvpn/openvpn-ui-users.json"
SESSION_TIMEOUT = 3600  # 1 hour

# Create Flask app
app = Flask(__name__, template_folder=None, static_folder=None)
app.secret_key = secrets.token_hex(32)

# =============================================================================
# AUTHENTICATION FUNCTIONS
# =============================================================================

def hash_password(password):
    """Hash password using SHA256"""
    return hashlib.sha256(password.encode()).hexdigest()

def load_users():
    """Load users from JSON file"""
    if not os.path.exists(USERS_FILE):
        return {}
    try:
        with open(USERS_FILE, 'r') as f:
            return json.load(f)
    except:
        return {}

def save_users(users):
    """Save users to JSON file"""
    with open(USERS_FILE, 'w') as f:
        json.dump(users, f, indent=2)
    os.chmod(USERS_FILE, 0o600)

def init_admin_user():
    """Initialize default admin user if none exists"""
    users = load_users()
    if not users:
        # Create default admin with random password
        admin_pass = secrets.token_urlsafe(12)
        users['admin'] = {
            'password_hash': hash_password(admin_pass),
            'created': datetime.now().isoformat(),
            'role': 'admin'
        }
        save_users(users)
        print(f"\n{'='*60}")
        print("DEFAULT ADMIN USER CREATED")
        print(f"{'='*60}")
        print(f"Username: admin")
        print(f"Password: {admin_pass}")
        print(f"URL: http://your-server-ip:8443")
        print(f"{'='*60}\n")
        return admin_pass
    return None

def login_required(f):
    """Decorator for login requirement"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'username' not in session:
            return redirect(url_for('login'))
        # Check session timeout
        if 'login_time' in session:
            if datetime.now() - datetime.fromisoformat(session['login_time']) > timedelta(seconds=SESSION_TIMEOUT):
                session.clear()
                return redirect(url_for('login'))
            session['login_time'] = datetime.now().isoformat()
        return f(*args, **kwargs)
    return decorated_function

# =============================================================================
# OPENVPN MANAGEMENT FUNCTIONS
# =============================================================================

def get_server_info():
    """Get server configuration info"""
    try:
        # Read server IP from config
        server_ip = subprocess.check_output(
            "curl -s ifconfig.me 2>/dev/null || echo 'Unknown'",
            shell=True,
            text=True
        ).strip()
        
        # Read port from config
        port = "1194"
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, 'r') as f:
                for line in f:
                    if line.startswith('port '):
                        port = line.split()[1]
                        break
        
        return {
            'ip': server_ip,
            'port': port,
            'status': 'Running' if is_openvpn_running() else 'Stopped'
        }
    except:
        return {'ip': 'Unknown', 'port': '1194', 'status': 'Unknown'}

def is_openvpn_running():
    """Check if OpenVPN service is running"""
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', 'openvpn@server'],
            capture_output=True,
            text=True
        )
        return result.returncode == 0
    except:
        return False

def get_all_clients():
    """Get list of all configured clients"""
    clients = []
    if not os.path.exists(f"{PKI_DIR}/issued"):
        return clients
    
    try:
        for cert_file in os.listdir(f"{PKI_DIR}/issued"):
            if cert_file.endswith('.crt') and cert_file != 'server.crt':
                client_name = cert_file[:-4]
                config_file = f"{CLIENTS_DIR}/{client_name}.ovpn"
                
                clients.append({
                    'name': client_name,
                    'config_exists': os.path.exists(config_file),
                    'config_size': os.path.getsize(config_file) if os.path.exists(config_file) else 0,
                    'created': datetime.fromtimestamp(
                        os.path.getctime(f"{PKI_DIR}/issued/{cert_file}")
                    ).strftime('%Y-%m-%d %H:%M:%S')
                })
    except:
        pass
    
    return sorted(clients, key=lambda x: x['name'])

def create_client(client_name):
    """Create new OpenVPN client"""
    try:
        os.chdir(EASYRSA_DIR)
        
        # Generate request
        result = subprocess.run(
            ['./easyrsa', 'gen-req', client_name, 'nopass'],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            return False, f"Failed to generate request: {result.stderr}"
        
        # Sign certificate
        result = subprocess.run(
            ['./easyrsa', 'sign-req', 'client', client_name, 'nopass'],
            capture_output=True,
            text=True,
            input='yes\n'  # Confirm signing
        )
        if result.returncode != 0:
            return False, f"Failed to sign certificate: {result.stderr}"
        
        return True, "Client created successfully"
    except Exception as e:
        return False, str(e)

def generate_client_config(client_name, server_ip=None):
    """Generate OpenVPN config file"""
    try:
        if server_ip is None:
            server_ip = get_server_info()['ip']
        
        server_port = "1194"
        proto = "udp"
        
        # Read server config
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, 'r') as f:
                content = f.read()
                for line in content.split('\n'):
                    if line.startswith('port '):
                        server_port = line.split()[1]
                    if line.startswith('proto '):
                        proto = line.split()[1]
        
        # Check certificates
        cert_file = f"{PKI_DIR}/issued/{client_name}.crt"
        key_file = f"{PKI_DIR}/private/{client_name}.key"
        ca_file = f"{PKI_DIR}/ca.crt"
        ta_file = f"{OPENVPN_DIR}/ta.key"
        
        if not all(os.path.exists(f) for f in [cert_file, key_file, ca_file, ta_file]):
            return False, "Certificate files not found"
        
        # Read certificate contents
        with open(ca_file, 'r') as f:
            ca_content = f.read()
        with open(cert_file, 'r') as f:
            cert_content = f.read()
        with open(key_file, 'r') as f:
            key_content = f.read()
        with open(ta_file, 'r') as f:
            ta_content = f.read()
        
        # Generate config
        config = f"""client
dev tun
proto {proto}
remote {server_ip} {server_port}

resolv-retry infinite
nobind

remote-cert-tls server
tls-auth [inline] 1

cipher AES-256-GCM
ncp-ciphers "AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305"

setenv opt block-outside-dns
dhcp-option DNS 1.1.1.1
dhcp-option DNS 8.8.8.8

compress lz4-v2

user nobody
group nogroup

persist-key
persist-tun

verb 3
mute 20

<ca>
{ca_content}</ca>

<cert>
{cert_content}</cert>

<key>
{key_content}</key>

<tls-auth>
{ta_content}</tls-auth>
"""
        
        # Write config file
        os.makedirs(CLIENTS_DIR, exist_ok=True)
        config_file = f"{CLIENTS_DIR}/{client_name}.ovpn"
        with open(config_file, 'w') as f:
            f.write(config)
        os.chmod(config_file, 0o600)
        
        return True, f"Config generated: {config_file}"
    except Exception as e:
        return False, str(e)

def revoke_client(client_name):
    """Revoke client certificate"""
    try:
        os.chdir(EASYRSA_DIR)
        
        # Revoke
        result = subprocess.run(
            ['./easyrsa', 'revoke', client_name],
            capture_output=True,
            text=True,
            input='yes\n'
        )
        if result.returncode != 0:
            return False, f"Failed to revoke: {result.stderr}"
        
        # Generate new CRL
        result = subprocess.run(
            ['./easyrsa', 'gen-crl'],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            return False, f"Failed to generate CRL: {result.stderr}"
        
        return True, "Client revoked successfully"
    except Exception as e:
        return False, str(e)

def get_client_config(client_name):
    """Read client config file"""
    config_file = f"{CLIENTS_DIR}/{client_name}.ovpn"
    if os.path.exists(config_file):
        with open(config_file, 'r') as f:
            return f.read()
    return None

def generate_qr_code(client_name, server_ip=None):
    """Generate QR code for client config"""
    try:
        config = get_client_config(client_name)
        if not config:
            return None
        
        qr = qrcode.QRCode(
            version=None,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(config)
        qr.make(fit=True)
        
        img = qr.make_image(fill_color="black", back_color="white")
        img_io = BytesIO()
        img.save(img_io, 'PNG')
        img_io.seek(0)
        
        return base64.b64encode(img_io.getvalue()).decode()
    except:
        return None

# =============================================================================
# FLASK ROUTES
# =============================================================================

@app.route('/login', methods=['GET', 'POST'])
def login():
    """Login page"""
    if request.method == 'POST':
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '').strip()
        
        users = load_users()
        if username in users and users[username]['password_hash'] == hash_password(password):
            session['username'] = username
            session['login_time'] = datetime.now().isoformat()
            return redirect(url_for('dashboard'))
        else:
            return render_template('login.html', error='Invalid username or password')
    
    return render_template('login.html')

@app.route('/logout')
def logout():
    """Logout"""
    session.clear()
    return redirect(url_for('login'))

@app.route('/')
@login_required
def dashboard():
    """Main dashboard"""
    server_info = get_server_info()
    clients = get_all_clients()
    return render_template('dashboard.html', 
                         server_info=server_info,
                         clients=clients,
                         username=session.get('username'))

@app.route('/api/clients')
@login_required
def api_clients():
    """API: Get all clients"""
    return jsonify(get_all_clients())

@app.route('/api/client/create', methods=['POST'])
@login_required
def api_create_client():
    """API: Create new client"""
    data = request.json
    client_name = data.get('name', '').strip()
    
    if not client_name or not client_name.replace('_', '').replace('-', '').isalnum():
        return jsonify({'success': False, 'error': 'Invalid client name'}), 400
    
    # Check if exists
    if os.path.exists(f"{PKI_DIR}/issued/{client_name}.crt"):
        return jsonify({'success': False, 'error': 'Client already exists'}), 400
    
    # Create client
    success, message = create_client(client_name)
    if not success:
        return jsonify({'success': False, 'error': message}), 500
    
    # Generate config
    success, message = generate_client_config(client_name)
    if not success:
        return jsonify({'success': False, 'error': message}), 500
    
    return jsonify({'success': True, 'message': 'Client created successfully'})

@app.route('/api/client/download/<client_name>')
@login_required
def api_download_client(client_name):
    """API: Download client config"""
    config_file = f"{CLIENTS_DIR}/{client_name}.ovpn"
    if not os.path.exists(config_file):
        return jsonify({'error': 'Config not found'}), 404
    
    return send_file(config_file, as_attachment=True, 
                    download_name=f'{client_name}.ovpn',
                    mimetype='text/plain')

@app.route('/api/client/qr/<client_name>')
@login_required
def api_qr_code(client_name):
    """API: Get QR code for client"""
    qr_data = generate_qr_code(client_name)
    if not qr_data:
        return jsonify({'error': 'Could not generate QR code'}), 500
    
    return jsonify({'qr_code': f'data:image/png;base64,{qr_data}'})

@app.route('/api/client/revoke', methods=['POST'])
@login_required
def api_revoke_client():
    """API: Revoke client"""
    data = request.json
    client_name = data.get('name', '').strip()
    
    success, message = revoke_client(client_name)
    if not success:
        return jsonify({'success': False, 'error': message}), 500
    
    # Remove config file
    config_file = f"{CLIENTS_DIR}/{client_name}.ovpn"
    if os.path.exists(config_file):
        os.remove(config_file)
    
    return jsonify({'success': True, 'message': 'Client revoked successfully'})

@app.route('/api/server/info')
@login_required
def api_server_info():
    """API: Get server info"""
    return jsonify(get_server_info())

@app.route('/settings', methods=['GET', 'POST'])
@login_required
def settings():
    """Settings page (admin only)"""
    users = load_users()
    if session.get('username') not in [u for u, d in users.items() if d.get('role') == 'admin']:
        return redirect(url_for('dashboard'))
    
    if request.method == 'POST':
        action = request.form.get('action')
        
        if action == 'change_password':
            old_password = request.form.get('old_password', '')
            new_password = request.form.get('new_password', '')
            confirm_password = request.form.get('confirm_password', '')
            
            if not (old_password and new_password and confirm_password):
                return render_template('settings.html', 
                                     error='All fields are required',
                                     users=users)
            
            if new_password != confirm_password:
                return render_template('settings.html',
                                     error='Passwords do not match',
                                     users=users)
            
            current_user = session.get('username')
            if users[current_user]['password_hash'] != hash_password(old_password):
                return render_template('settings.html',
                                     error='Old password is incorrect',
                                     users=users)
            
            users[current_user]['password_hash'] = hash_password(new_password)
            save_users(users)
            return render_template('settings.html',
                                 message='Password changed successfully',
                                 users=users)
        
        elif action == 'add_user':
            new_username = request.form.get('username', '').strip()
            new_password = request.form.get('password', '').strip()
            
            if not (new_username and new_password):
                return render_template('settings.html',
                                     error='Username and password are required',
                                     users=users)
            
            if new_username in users:
                return render_template('settings.html',
                                     error='User already exists',
                                     users=users)
            
            users[new_username] = {
                'password_hash': hash_password(new_password),
                'created': datetime.now().isoformat(),
                'role': 'user'
            }
            save_users(users)
            return render_template('settings.html',
                                 message=f'User {new_username} created successfully',
                                 users=users)
    
    return render_template('settings.html', users=users)

# =============================================================================
# MAIN
# =============================================================================

if __name__ == '__main__':
    # Initialize admin user
    init_admin_user()
    
    # Create templates directory
    os.makedirs('templates', exist_ok=True)
    
    # Run app
    app.run(host='0.0.0.0', port=8443, ssl_context='adhoc', debug=False)
