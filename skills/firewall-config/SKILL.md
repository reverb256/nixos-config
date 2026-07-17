---
name: firewall-config
description: Configure iptables, nftables, UFW, and cloud firewalls (AWS, GCP, Azure). Implement network segmentation, traffic filtering, and security zones. Use when securing network perimeters, implementing security zones, or restricting network access. (Now includes UFW configuration from deprecated firewall-configuration skill)
version: 2.0.0
---

# Firewall Configuration

Comprehensive firewall configuration for host-based firewalls (iptables, nftables, UFW) and cloud provider firewalls (AWS Security Groups, GCP Firewalls, Azure Network Security Groups).

## When to Use This Skill

Use this skill when:
- Configuring host-based firewalls (iptables, nftables, UFW)
- Setting up cloud provider firewalls
- Implementing network segmentation
- Creating security zones
- Restricting network access
- Implementing VPN rules
- Configuring NAT/port forwarding

---

## UFW (Uncomplicated Firewall)

UFW is designed for Ubuntu/Debian and provides a simple interface for managing iptables.

### Basic Configuration

```bash
# Install UFW
sudo apt install ufw

# Set default policies (deny incoming, allow outgoing)
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH BEFORE enabling!
sudo ufw allow 22/tcp
sudo ufw allow from 192.168.1.0/24 to any port 22

# Allow common services
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 3306/tcp  # MySQL
sudo ufw allow 5432/tcp  # PostgreSQL
sudo ufw allow 6379/tcp  # Redis
sudo ufw allow 27017/tcp # MongoDB

# Enable firewall
sudo ufw enable

# Check status
sudo ufw status verbose

# Disable (if needed)
sudo ufw disable
```

### Advanced UFW Rules

```bash
# Allow from specific IP
sudo ufw allow from 10.0.0.5

# Allow from subnet to specific port
sudo ufw allow from 192.168.1.0/24 to any port 3306

# Allow specific port range
sudo ufw allow 8000:9000/tcp

# Deny specific IP
sudo ufw deny from 203.0.113.4

# Rate limiting for SSH (prevents brute force)
sudo ufw limit 22/tcp
# This allows: 6 connections in 30 seconds, then blocks for 30 seconds

# Allow with comment
sudo ufw allow 80/tcp comment "Web server"

# Delete rule
sudo ufw delete allow 80/tcp

# Reset to defaults (deletes all rules)
sudo ufw reset
```

### UFW Application Profiles

```bash
# List available profiles
sudo ufw app list

# Show profile details
sudo ufw app info Apache

# Allow application
sudo ufw allow 'Apache Full'

# Deny application
sudo ufw deny 'Apache'
```

### UFW Configuration File

```bash
# /etc/default/ufw
IPTABLES="/sbin/iptables"
IP6TABLES="/sbin/ip6tables"
IPTABLES_PERSISTENT_RULES="/etc/iptables/rules.v4"
IP6TABLES_PERSISTENT_RULES="/etc/iptables/rules.v6"
MANAGED="yes"
```

### UFW for VPS Hardening

```bash
# Typical VPS setup
sudo ufw default deny incoming
sudo ufw default allow outgoing

# SSH
sudo ufw allow 22/tcp
sudo ufw limit 22/tcp

# Web services
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Monitoring (if needed)
sudo ufw allow from 10.0.0.0/8 to any port 9100

# Enable
sudo ufw enable

# Verify
sudo ufw status numbered
```

---

## iptables

iptables is the classic Linux firewall tool, powerful but more complex.

### Basic iptables Configuration

```bash
# Flush existing rules
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

# Set default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow loopback interface
iptables -A INPUT -i lo -j ACCEPT

# Allow established and related connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Drop invalid packets
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

# Allow SSH
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Allow HTTP/HTTPS
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Allow DNS
iptables -A INPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p tcp --dport 53 -j ACCEPT

# Save rules (Debian/Ubuntu)
iptables-save > /etc/iptables/rules.v4

# Save rules (RHEL/CentOS)
service iptables save
```

### Advanced iptables Rules

```bash
# Port forwarding
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080

# Source NAT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Destination NAT
iptables -t nat -A PREROUTING -d 1.2.3.4 -j DNAT --to-destination 192.168.1.10

# Block specific IP
iptables -A INPUT -s 203.0.113.4 -j DROP

# Allow from specific subnet
iptables -A INPUT -s 192.168.1.0/24 -j ACCEPT

# Log dropped packets
iptables -A INPUT -j LOG --log-prefix "[DROPPED] "

# Rate limiting (prevent DoS)
iptables -A INPUT -p tcp --dport 80 -m limit --limit 25/minute --limit-burst 100 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j DROP

# Syn flood protection
iptables -A INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT

# ICMP blocking (except ping)
iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s -j ACCEPT
iptables -A INPUT -p icmp -j DROP
```

### iptables for Web Server

```bash
#!/bin/bash

# Web server firewall script

# Flush rules
iptables -F
iptables -X

# Default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow SSH (rate limited)
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 -j DROP
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Allow HTTP/HTTPS
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Allow monitoring (from trusted IP)
iptables -A INPUT -s 10.0.0.5 -p tcp --dport 9100 -j ACCEPT

# Log and drop
iptables -A INPUT -j LOG --log-prefix "[FW-DROP] "
iptables -A INPUT -j DROP

# Save
iptables-save > /etc/iptables/rules.v4
```

### Making iptables Persistent

**Debian/Ubuntu:**
```bash
sudo apt install iptables-persistent
sudo iptables-save > /etc/iptables/rules.v4
```

**RHEL/CentOS:**
```bash
sudo yum install iptables-services
sudo service iptables save
sudo systemctl enable iptables
```

---

## nftables

nftables is the modern replacement for iptables, providing a unified framework.

### Basic nftables Configuration

```bash
#!/usr/sbin/nft -f

# Flush existing ruleset
flush ruleset

# Create table
table inet filter {
  # Input chain
  chain input {
    type filter hook input priority 0;
    policy drop;

    # Allow loopback
    iif "lo" accept

    # Allow established connections
    ct state established,related accept

    # Drop invalid packets
    ct state invalid drop

    # Allow SSH
    tcp dport 22 accept

    # Allow HTTP/HTTPS
    tcp dport { 80, 443 } accept

    # Allow DNS
    udp dport 53 accept
    tcp dport 53 accept
  }

  # Forward chain
  chain forward {
    type filter hook forward priority 0;
    policy drop;
  }

  # Output chain
  chain output {
    type filter hook output priority 0;
    policy accept;
  }
}
```

### Advanced nftables

```bash
#!/usr/sbin/nft -f

# Variables
define TRUSTED_NET = { 10.0.0.0/8, 192.168.0.0/16 }
define WEB_PORTS = { 80, 443 }
define DB_PORTS = { 3306, 5432 }

table inet filter {
  chain input {
    type filter hook input priority 0;
    policy drop;

    # Loopback
    iif "lo" accept

    # Established
    ct state established,related accept

    # Invalid
    ct state invalid drop

    # SSH (rate limited)
    tcp dport 22 limit rate 4/minute accept

    # Web ports
    tcp dport $WEB_PORTS accept

    # Database from trusted
    ip saddr $TRUSTED_NET tcp dport $DB_PORTS accept

    # Monitoring
    ip saddr 10.0.0.5 tcp dport 9100 accept

    # ICMP (limited)
    ip protocol icmp limit rate 5/second accept

    # Log and drop
    log prefix "nft-drop: " flags all
  }

  chain forward {
    type filter hook forward priority 0;
    policy drop;
  }

  chain output {
    type filter hook output priority 0;
    policy accept;
  }
}

# Save rules
nft list ruleset > /etc/nftables.conf
```

### NAT with nftables

```bash
#!/usr/sbin/nft -f

table ip nat {
  chain prerouting {
    type nat hook prerouting priority 0;
    policy accept;

    # Port forward 80 -> 8080
    tcp dport 80 dnat to 192.168.1.10:8080
  }

  chain postrouting {
    type nat hook postrouting priority 0;
    policy accept;

    # Masquerade
    oif eth0 masquerade
  }
}
```

### Making nftables Persistent

```bash
# Save rules
sudo nft list ruleset > /etc/nftables.conf

# Enable service
sudo systemctl enable nftables
sudo systemctl start nftables
```

---

## AWS Security Groups

### Create Security Group

```bash
# Create security group
aws ec2 create-security-group \
  --group-name web-sg \
  --description "Web server security group" \
  --vpc-id vpc-12345678

# Get security group ID
SG_ID=$(aws ec2 describe-security-groups \
  --group-names web-sg \
  --query 'SecurityGroups[0].GroupId' \
  --output text)
```

### Add Ingress Rules

```bash
# Allow SSH from specific IP
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr 203.0.113.4/32

# Allow HTTP from anywhere
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

# Allow HTTPS from anywhere
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0

# Allow from another security group (VPC internal)
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 3306 \
  --source-group sg-87654321
```

### Add Egress Rules

```bash
# Allow all outbound traffic
aws ec2 authorize-security-group-egress \
  --group-id $SG_ID \
  --protocol all \
  --cidr 0.0.0.0/0

# Or restrict to specific outbound
aws ec2 revoke-security-group-egress \
  --group-id $SG_ID \
  --protocol all \
  --cidr 0.0.0.0/0

aws ec2 authorize-security-group-egress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0
```

### Using JSON for Complex Rules

```bash
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --ip-permissions '[{
    "FromPort": 8000,
    "ToPort": 9000,
    "IpProtocol": "tcp",
    "IpRanges": [{"CidrIp": "10.0.0.0/8"}]
  }]'
```

---

## GCP Firewall Rules

### Create Firewall Rule

```bash
# Allow HTTP from anywhere
gcloud compute firewall-rules create allow-http \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:80 \
  --source-ranges=0.0.0.0/0 \
  --description="Allow HTTP traffic"

# Allow SSH from specific IP
gcloud compute firewall-rules create allow-ssh \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:22 \
  --source-ranges=203.0.113.4/32 \
  --description="Allow SSH from admin IP"

# Allow internal traffic
gcloud compute firewall-rules create allow-internal \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=all \
  --source-ranges=10.0.0.0/8 \
  --description="Allow internal VPC traffic"
```

### List and Delete Rules

```bash
# List all firewall rules
gcloud compute firewall-rules list

# Describe specific rule
gcloud compute firewall-rules describe allow-http

# Delete rule
gcloud compute firewall-rules delete allow-http
```

---

## Azure Network Security Groups (NSG)

### Create NSG

```bash
# Create NSG
az network nsg create \
  --resource-group myResourceGroup \
  --name web-nsg

# Get NSG ID
NSG_ID=$(az network nsg show \
  --resource-group myResourceGroup \
  --name web-nsg \
  --query id -o tsv)
```

### Add Security Rules

```bash
# Allow SSH from specific IP
az network nsg rule create \
  --resource-group myResourceGroup \
  --nsg-name web-nsg \
  --name allow-ssh \
  --access Allow \
  --protocol Tcp \
  --direction Inbound \
  --priority 100 \
  --source-address-prefix 203.0.113.4/32 \
  --source-port-range "*" \
  --destination-address-prefix "*" \
  --destination-port-range 22

# Allow HTTP from anywhere
az network nsg rule create \
  --resource-group myResourceGroup \
  --nsg-name web-nsg \
  --name allow-http \
  --access Allow \
  --protocol Tcp \
  --direction Inbound \
  --priority 110 \
  --source-address-prefix "*" \
  --source-port-range "*" \
  --destination-address-prefix "*" \
  --destination-port-range 80

# Allow HTTPS from anywhere
az network nsg rule create \
  --resource-group myResourceGroup \
  --nsg-name web-nsg \
  --name allow-https \
  --access Allow \
  --protocol Tcp \
  --direction Inbound \
  --priority 120 \
  --source-address-prefix "*" \
  --source-port-range "*" \
  --destination-address-prefix "*" \
  --destination-port-range 443
```

---

## Network Segmentation

### Creating Security Zones

```bash
# Using iptables
# DMZ zone (web servers)
iptables -A INPUT -i eth1 -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -i eth1 -p tcp --dport 443 -j ACCEPT

# Internal zone (app servers)
iptables -A INPUT -i eth2 -p tcp --dport 8000 -j ACCEPT

# Database zone (only from app servers)
iptables -A INPUT -i eth3 -s 10.0.1.0/24 -p tcp --dport 3306 -j ACCEPT
```

### Zero Trust Network

```bash
# Default deny all
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Only allow authenticated traffic (via VPN/IDS)
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -s 10.10.0.0/16 -j ACCEPT  # VPN network
```

---

## Best Practices

### General Firewall Rules

1. **Default Deny** - Always start with a default deny policy
2. **Minimal Rule Set** - Only allow what's necessary
3. **Rule Ordering** - Place specific rules before general ones
4. **Document Everything** - Label all rules with descriptions
5. **Regular Audits** - Review and remove unused rules
6. **Log Drops** - Log dropped packets for troubleshooting
7. **Test Before Deploying** - Test rules in non-production first
8. **Backup Rules** - Keep backups of working configurations

### Cloud Firewall Best Practices

1. **Least Privilege** - Restrict source ranges as much as possible
2. **Use Security Groups/Naming** - Name security groups by function
3. **Separate Layers** - Use both cloud and host firewalls
4. **Tag Resources** - Tag resources for rule association
5. **Regular Review** - Review cloud firewall rules monthly

### Monitoring and Troubleshooting

```bash
# List iptables rules with line numbers
iptables -L -n -v --line-numbers

# List nftables rules
nft list ruleset

# Check UFW status
sudo ufw status verbose
sudo ufw status numbered

# Monitor blocked packets
sudo tail -f /var/log/kern.log | grep DROP

# AWS - describe security groups
aws ec2 describe-security-groups --group-ids sg-12345678

# GCP - list firewall rules
gcloud compute firewall-rules list

# Azure - list NSG rules
az network nsg rule list --resource-group myRG --nsg-name web-nsg
```

---

## Related Skills

- `linux-hardening` - System security including firewall configuration
- `security-best-practices` - Web application and infrastructure security
- `k8s-security` - Kubernetes network policies
- `devops-automation` - Infrastructure as code for firewalls

---

## Resources

- [UFW Documentation](https://help.ubuntu.com/community/UFW)
- [iptables Tutorial](https://www.frozentux.net/iptables-tutorial/iptables-tutorial.html)
- [nftables Wiki](https://wiki.nftables.org/)
- [AWS Security Groups](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_SecurityGroups.html)
- [GCP Firewall Rules](https://cloud.google.com/vpc/docs/firewalls)
- [Azure NSG Documentation](https://docs.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview)
