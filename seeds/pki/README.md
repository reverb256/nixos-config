# PKI Seeds - Agenix Secret Templates

This directory contains templates for agenix-encrypted secrets.

## Certificate Generation Workflow

1. **Generate Certificates**
   ```bash
   cd /etc/nixos/modules/pki
   ./gen-certs.sh
   ```

2. **Encrypt Private Keys with Agenix**
   ```bash
   cd /etc/nixos

   # CA private key
   agenix -e secrets/kubernetes-ca.age
   # Paste: output/private/ca-key.pem

   # API server private key
   agenix -e secrets/apiserver-key.age
   # Paste: output/private/apiserver-key.pem

   # etcd peer private key
   agenix -e secrets/etcd-peer-key.age
   # Paste: output/private/etcd-peer-key.pem

   # etcd node private keys
   agenix -e secrets/etcd-zephyr-key.age
   # Paste: output/private/etcd-zephyr-key.pem

   agenix -e secrets/etcd-nexus-key.age
   # Paste: output/private/etcd-nexus-key.pem

   agenix -e secrets/etcd-sentry-key.age
   # Paste: output/private/etcd-sentry-key.pem

   # Controller manager private key
   agenix -e secrets/controller-manager-key.age
   # Paste: output/private/controller-manager-key.pem

   # Scheduler private key
   agenix -e secrets/scheduler-key.age
   # Paste: output/private/scheduler-key.pem

   # Admin private key
   agenix -e secrets/admin-key.age
   # Paste: output/private/admin-key.pem
   ```

3. **Create Kubeconfig**
   ```bash
   # Base64 encode certificates
   CA_B64=$(base64 -w0 output/certs/ca.pem)
   ADMIN_CERT_B64=$(base64 -w0 output/certs/admin.pem)
   ADMIN_KEY_B64=$(base64 -w0 output/private/admin-key.pem)

   # Update kubeconfig template with actual values
   sed -e "s/BASE64_ENCODED_CA_PEM/$CA_B64/g" \
       -e "s/BASE64_ENCODED_ADMIN_PEM/$ADMIN_CERT_B64/g" \
       -e "s/BASE64_ENCODED_ADMIN_KEY_PEM/$ADMIN_KEY_B64/g" \
       seeds/pki/kubeconfig-admin.yaml.age > admin-kubeconfig.yaml

   # Encrypt kubeconfig
   agenix -e secrets/admin-kubeconfig.age < admin-kubeconfig.yaml
   ```

## Secret Reference

| Secret | Purpose | Nodes |
|--------|---------|-------|
| `kubernetes-ca.age` | CA certificate (public) | All |
| `apiserver-key.age` | API server private key | Masters |
| `etcd-peer-key.age` | etcd peer private key | Masters |
| `etcd-zephyr-key.age` | etcd server key (Zephyr) | Zephyr |
| `etcd-nexus-key.age` | etcd server key (Nexus) | Nexus |
| `etcd-sentry-key.age` | etcd server key (Sentry) | Sentry |
| `controller-manager-key.age` | Controller manager key | Masters |
| `scheduler-key.age` | Scheduler key | Masters |
| `admin-key.age` | Admin client key | Masters |
| `admin-kubeconfig.age` | Admin kubeconfig | Optional |
| `service-account-key.age` | Service account signing key | Masters |
| `front-proxy-client-key.age` | Front proxy client key | Masters |
| `tokens.age` | Bootstrap tokens | Masters |

## Security Notes

1. **Never commit private keys to git**
2. **Store .age files in git** (they're encrypted)
3. **Rotate certificates annually**
4. **Backup CA private key securely**
5. **Use different CA for front proxy** (best practice)
