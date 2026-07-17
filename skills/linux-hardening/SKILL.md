---
name: linux-hardening
description: Apply CIS benchmarks and secure Linux servers. Configure SSH, manage users, create non-root sudo users, implement firewall rules, and enable security features. Use when hardening Linux systems for production or meeting security compliance requirements. (Now includes SSH hardening from deprecated ssh-hardening skill)
version: 2.0.0
---

# Linux Hardening

Secure Linux servers following CIS benchmarks and security best practices. Includes comprehensive SSH hardening, user management, firewall configuration, kernel hardening, file permissions, and audit configuration.

## When to Use This Skill

Use this skill when:
- Hardening production servers
- Meeting compliance requirements (CIS, NIST, PCI-DSS)
- Implementing security baselines
- Configuring secure SSH access
- Creating non-root sudo users
- Setting up firewall rules
- Implementing audit logging

---

## SSH Hardening

### Comprehensive sshd_config

```bash
# /etc/ssh/sshd_config

# ====================
# Basic Security
# ====================
Protocol 2
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes

# ====================
# Connection Limits
# ====================
MaxAuthTries 3
MaxStartups 10:30:100
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 60

# ====================
# User Restrictions
# ====================
AllowUsers deploy admin monitoring
DenyUsers root
AllowGroups sshusers
DenyGroups wheel

# ====================
# Network Restrictions
# ====================
ListenAddress 0.0.0.0
Port 22
# Or change to non-standard port
# Port 2222

GatewayPorts no
X11Forwarding no
AllowTcpForwarding no
PermitTunnel no

# ====================
# Authentication Methods
# ====================
AuthenticationMethods publickey
PubkeyAuthentication yes
PubkeyAcceptedKeyTypes +ssh-rsa,ssh-ed25519
AuthorizedKeysFile .ssh/authorized_keys

# ====================
# Security Options
# ====================
UsePAM yes
StrictModes yes
Compression no
TCPKeepAlive yes
PermitEmptyPasswords no
IgnoreRhosts yes
HostbasedAuthentication no
IgnoreUserKnownHosts no
RhostsRSAAuthentication no

# ====================
# Logging
# ====================
SyslogFacility AUTH
LogLevel VERBOSE

# ====================
# Crypto
# ====================
Ciphers aes256-gcm@openssh.com,chacha20-poly1305@openssh.com,aes256-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group16-sha512

# ====================
# Banner
# ====================
Banner /etc/ssh/banner.txt
```

### SSH Banner

```bash
# /etc/ssh/banner.txt
***************************************************************************
*           WARNING: AUTHORIZED ACCESS ONLY                  *
*           Unauthorized access is prohibited                  *
*           All connections are logged and monitored           *
*           Violators will be prosecuted                      *
***************************************************************************
```

### Creating Non-Root Sudo Users

```bash
# Create a new user
sudo adduser deploy

# Add to sudo group
sudo usermod -aG sudo deploy

# Create .ssh directory
sudo mkdir -p /home/deploy/.ssh
sudo chmod 700 /home/deploy/.ssh

# Add public key
sudo tee /home/deploy/.ssh/authorized_keys << 'EOF'
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... your-public-key-here
EOF
sudo chmod 600 /home/deploy/.ssh/authorized_keys

# Set ownership
sudo chown -R deploy:deploy /home/deploy/.ssh

# Test SSH access
ssh deploy@your-server

# Verify sudo works
ssh deploy@your-server "sudo whoami"
```

### SSH Key Management

```bash
# Generate new SSH key (client side)
ssh-keygen -t ed25519 -C "deploy@example.com" -f ~/.ssh/deploy_key

# Copy to server
ssh-copy-id -i ~/.ssh/deploy_key.pub deploy@server.example.com

# Or manually copy
cat ~/.ssh/deploy_key.pub | ssh deploy@server.example.com "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"

# Disable password for specific user (after keys are set)
sudo passwd -l deploy
```

### Two-Factor Authentication (2FA) for SSH

```bash
# Install Google Authenticator
sudo apt install libpam-google-authenticator

# Generate QR code for user
google-authenticator

# Configure PAM
# Add to /etc/pam.d/sshd:
# auth required pam_google_authenticator.so

# Add to /etc/ssh/sshd_config:
# ChallengeResponseAuthentication yes
```

---

## User Security

### Password Policy

```bash
# Install password quality library
sudo apt install libpam-pwquality

# /etc/security/pwquality.conf
minlen = 14
dcredit = -1
ucredit = -1
ocredit = -1
lcredit = -1
minclass = 4
maxrepeat = 3
enforce_for_root

# Check password quality
pwquality check your-password
```

### Account Lockout Policy

```bash
# /etc/pam.d/common-account
account required pam_faillock.so preauth silent audit deny=5 unlock_time=900

# Lock inactive accounts after 30 days
useradd -D -f 30

# Lock inactive accounts
passwd -l username

# Unlock account
passwd -u username
```

### Sudo Configuration

```bash
# /etc/sudoers.d/security
# Require password for sudo
Defaults env_reset
Defaults timestamp_timeout=15
Defaults lecture=always

# Log sudo usage
Defaults logfile=/var/log/sudo.log
Defaults log_output
Defaults !syslog

# Restrict commands for specific groups
%webadmin ALL=(root) /usr/sbin/nginx -t, /usr/sbin/nginx -s reload
%dbadmin ALL=(root) /usr/sbin/service mysql *

# Allow monitoring users passwordless access to specific commands
%monitoring ALL=(root) NOPASSWD:\
  /usr/bin/htop, /usr/bin/df, /usr/bin/uptime

# Edit sudoers safely
sudo visudo
```

### User Auditing

```bash
# List all users
cut -d: -f1 /etc/passwd

# List users with UID >= 1000
awk -F: '($3 >= 1000) {print}' /etc/passwd

# Check for users without passwords
sudo awk -F: '($2 == "" || $2 == "*") {print}' /etc/shadow

# Find users with UID 0 (root equivalent)
sudo awk -F: '($3 == 0) {print}' /etc/passwd

# Check sudo access
sudo -l -U username
```

---

## Firewall Configuration

### UFW (Uncomplicated Firewall)

```bash
# Enable UFW
sudo apt install ufw

# Set defaults
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (before enabling!)
sudo ufw allow 22/tcp
sudo ufw allow from 192.168.1.0/24 to any port 22

# Allow specific services
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 3306/tcp  # MySQL
sudo ufw allow 5432/tcp  # PostgreSQL

# Allow from specific IPs
sudo ufw allow from 10.0.0.5 to any

# Rate limiting
sudo ufw limit 22/tcp

# Enable firewall
sudo ufw enable

# Check status
sudo ufw status verbose

# Disable
sudo ufw disable

# Delete rule
sudo ufw delete allow 80/tcp
```

### iptables

```bash
# Set default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# Allow established connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow SSH
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Allow HTTP/HTTPS
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Allow DNS
iptables -A INPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p tcp --dport 53 -j ACCEPT

# Drop invalid packets
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

# Save rules
iptables-save > /etc/iptables/rules.v4

# Restore on boot
iptables-restore < /etc/iptables/rules.v4
```

### nftables

```bash
# Basic nftables configuration
sudo nft create table inet filter

# Add chain
sudo nft add chain inet filter input { type filter hook input priority 0 \; }

# Allow loopback
sudo nft add rule inet filter input iif lo accept

# Allow established connections
sudo nft add rule inet filter input ct state established,related accept

# Allow SSH
sudo nft add rule inet filter input tcp dport 22 accept

# Allow HTTP/HTTPS
sudo nft add rule inet filter input tcp dport { 80, 443 } accept

# Drop everything else
sudo nft add rule inet filter input drop

# Save
sudo nft list ruleset > /etc/nftables.conf

# Load on boot
sudo systemctl enable nftables
```

---

## Kernel Hardening

### sysctl Configuration

```bash
# /etc/sysctl.d/99-security.conf

# ====================
# Network Security
# ====================
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# ====================
# IP Spoofing Protection
# ====================
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# ====================
# Memory Protection
# ====================
kernel.randomize_va_space = 2
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.kexec_load_disabled = 1

# ====================
# Filesystem
# ====================
fs.suid_dumpable = 0
fs.protected_regular = 1
fs.protected_fifos = 1
fs.protected_symlinks = 1

# ====================
# Core Dumps
# ====================
kernel.core_pattern = |/bin/false
fs.suid_dumpable = 0

# Apply changes
sudo sysctl -p /etc/sysctl.d/99-security.conf
```

---

## File Permissions

### Critical File Permissions

```bash
# Secure sensitive files
chmod 600 /etc/shadow
chmod 644 /etc/passwd
chmod 640 /etc/sudoers
chmod 700 /root
chmod 600 /etc/ssh/sshd_config
chmod 644 /etc/ssh/ssh_config
chmod 755 /home/*
chmod 700 /home/*/.ssh

# Remove world-writable from home directories
find /home -perm -0002 -type d -exec chmod o-w {} \;

# Find world-writable files
find / -type f -perm -0002 -ls 2>/dev/null

# Find SUID files
find / -perm -4000 -type f -ls 2>/dev/null

# Find SGID files
find / -perm -2000 -type f -ls 2>/dev/null
```

### Sticky Bit for Shared Directories

```bash
# /tmp should be sticky
chmod 1777 /tmp
chmod 1777 /var/tmp

# Check sticky bit
ls -ld /tmp
# Output: drwxrwxrwt
```

---

## Service Hardening

### Disable Unused Services

```bash
# List all services
systemctl list-unit-files --type=service

# Stop and disable services
sudo systemctl stop telnet
sudo systemctl disable telnet
sudo systemctl stop rsh
sudo systemctl disable rsh

# List listening ports
sudo ss -tulpn

# Disable services not needed
sudo systemctl stop cups
sudo systemctl disable cups
```

### Disable Uncommon Filesystems

```bash
# /etc/modprobe.d/disable-filesystems.conf
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
install squashfs /bin/true
install udf /bin/true
```

---

## Audit Configuration

### Auditd Setup

```bash
# Install auditd
sudo apt install auditd

# /etc/audit/rules.d/audit.rules

# Monitor critical files
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/sudoers -p wa -k actions

# Monitor login events
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock -p wa -k logins

# Monitor SSH
-w /etc/ssh/sshd_config -p wa -k ssh
-w /var/log/auth.log -p wa -k ssh

# Monitor privileged commands
-a always,exit -F arch=b64 -S execve -F auid>=1000 -F auid!=4294967295 -k privileged

# Monitor network configuration
-w /etc/network/ -p wa -k network
-w /etc/hosts -p wa -k network

# Monitor cron
-w /etc/crontab -p wa -k cron
-w /etc/cron.d/ -p wa -k cron
-w /var/spool/cron/ -p wa -k cron

# Load rules
sudo augenrules

# Restart auditd
sudo systemctl restart auditd

# View logs
sudo ausearch -k ssh
sudo aureport -av
```

### Log Rotation

```bash
# /etc/logrotate.d/custom
/var/log/auth.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
}

# Test logrotate
sudo logrotate -d /etc/logrotate.conf
```

---

## Intrusion Detection

### Fail2ban

```bash
# Install fail2ban
sudo apt install fail2ban

# /etc/fail2ban/jail.local
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
destemail = admin@example.com
sendername = fail2ban

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 5

# Start fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Check status
sudo fail2ban-client status
sudo fail2ban-client status sshd

# Unban IP
sudo fail2ban-client set sshd unbanip 192.168.1.100
```

---

## Additional Security Measures

### SELinux/AppArmor

```bash
# For RHEL/CentOS - SELinux
sudo setenforce 1
sudo sestatus

# For Ubuntu/Debian - AppArmor
sudo aa-status
sudo aa-enforce /etc/apparmor.d/*

# Add profile for application
sudo aa-genprof /usr/bin/myapp
```

### Automatic Updates

```bash
# Ubuntu/Debian
sudo apt install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades

# RHEL/CentOS
sudo yum install yum-cron
sudo systemctl enable yum-cron
sudo systemctl start yum-cron
```

### Host-Based Intrusion Detection (HIDS)

```bash
# Install AIDE
sudo apt install aide

# Initialize
sudo aide --init
sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# Check integrity
sudo aide --check

# Update database
sudo aide --update
```

---

## Security Checklists

### Initial Setup Checklist

- [ ] Change default root password or disable root login
- [ ] Create non-root sudo user with SSH key
- [ ] Configure SSH hardening
- [ ] Set up firewall (UFW/iptables/nftables)
- [ ] Install and configure fail2ban
- [ ] Enable automatic security updates
- [ ] Configure audit logging
- [ ] Set up log rotation
- [ ] Secure critical file permissions
- [ ] Disable unused services

### Regular Maintenance

- [ ] Review and install security updates weekly
- [ ] Review logs daily
- [ ] Check for unauthorized SSH access
- [ ] Review user accounts
- [ ] Audit SUID/SGID files
- [ ] Review firewall rules
- [ ] Run vulnerability scans
- [ ] Check fail2ban banned IPs

---

## Related Skills

- `firewall-config` - Comprehensive firewall configuration
- `security-best-practices` - Web application and infrastructure security
- `security-scanning-security-hardening` - Multi-layer security scanning
- `owasp-security-check` - Security audit guidelines (merged into security-best-practices)

---

## Resources

- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks/)
- [SSH Hardening Guide](https://www.ssh.com/academy/ssh/hardening-best-practices)
- [Ubuntu Security Guide](https://ubuntu.com/server/docs/security)
- [Red Hat Security Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/)
