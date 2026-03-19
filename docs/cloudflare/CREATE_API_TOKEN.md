# Create Cloudflare API Token with Full Permissions

**5-minute guide to creating a master token for automation**

---

## Why You Need a New Token

**Current token**: Limited permissions (good for verification)
**New token**: Full permissions (needed for Zero Trust API automation)

**What the new token can do**:
- ✅ Create Zero Trust applications automatically
- ✅ Configure access policies via API
- ✅ Manage DNS records
- ✅ Full automation without manual dashboard work

---

## Step 1: Go to Token Creation (30 seconds)

1. Open: https://dash.cloudflare.com/profile/api-tokens
2. Click: **"Create Token"** button

---

## Step 2: Choose Token Template (30 seconds)

Click: **"Create Custom Token"**

---

## Step 3: Configure Permissions (2 minutes)

### Permissions to Add

**Zone** → **reverb256.ca**:
```
✅ DNS - Edit
✅ Zone - Read
✅ Zone - Edit
✅ SSL and Certificates - Edit
```

**Account** → **Cloudflare Access**:
```
✅ Account - Cloudflare Access: Edit
✅ Account - Cloudflare Access: Read
```

**User** Settings:
```
✅ User - DNS Edit
✅ User - Cloudflare Access
```

---

## Step 4: Token Settings (1 minute)

**Name**: Akash Provider - Full Access

**Expiration**:
- Option A: **No expiration** (permanent, recommended)
- Option B: **1 year** (more secure, requires rotation)

**Client IP Address Restriction**:
- Leave empty (access from anywhere)
- OR add your IP for extra security

---

## Step 5: Create and Copy Token (30 seconds)

1. Click: **"Continue to summary"**
2. Review permissions
3. Click: **"Create Token"**
4. **IMPORTANT**: Copy the token NOW (you won't see it again!)

Token format: `cfut_XXXXXXXXXXXXXXXXXXXXXXXXX`

---

## Step 6: Test Your New Token (30 seconds)

```bash
# Replace with your new token
export CF_TOKEN="cfut_YOUR_NEW_TOKEN_HERE"

# Test token
curl "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer $CF_TOKEN" \
  | jq '.'

# Expected output:
# {
#   "result": {
#     "status": "active",
#     ...
#   },
#   "success": true
# }
```

---

## Step 7: Use Your New Token (1 minute)

Now you can use this token to:

### Create Zero Trust Application Automatically

```bash
# Create Zero Trust app
curl -X POST "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/access/apps" \
  -H "Authorization: Bearer $CF_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Akash Provider - Reverb256",
    "session_duration": "24h",
    "type": "self_hosted"
  }'
```

### Configure Access Policies

```bash
# Add policy
curl -X POST "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/access/apps/YOUR_APP_ID/policies" \
  -H "Authorization: Bearer $CF_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Provider Owner",
    "decision": "allow",
    "include": {
      "email": {
        "email": ["your-email@example.com"]
      }
    }
  }'
```

---

## Security Best Practices

### ✅ DO

- **Store token securely**: Use agenix or environment variables
- **Rotate regularly**: Every 90 days if using expiration
- **Use minimal permissions**: Only grant what you need
- **Monitor usage**: Check token usage logs regularly

### ❌ DON'T

- **Don't commit to git**: Never store in repositories
- **Don't share publicly**: Keep it secret
- **Don't use in production**: Create separate prod/dev tokens
- **Don't forget to revoke**: Revoke old tokens when rotating

---

## Store Your Token Securely

### Option 1: Environment Variable (Temporary)

```bash
# Add to ~/.bashrc or ~/.zshrc
export CF_TOKEN="cfut_YOUR_NEW_TOKEN_HERE"

# Source it
source ~/.bashrc
```

### Option 2: Agenix (Recommended - NixOS)

```bash
# Create secret
cd /etc/nixos/secrets

# Create agenix secret for token
agenix -e cloudflare-token.nix

# Add token content
# CF_TOKEN=cfut_YOUR_NEW_TOKEN_HERE

# Rekey
agenix -r
```

### Option 3: Systemd Credentials (Production)

```bash
# Create credential file
sudo mkdir -p /etc/cloudflare
sudo chmod 700 /etc/cloudflare

# Store token
echo "cfut_YOUR_NEW_TOKEN_HERE" | sudo tee /etc/cloudflare/token
sudo chmod 600 /etc/cloudflare/token
```

---

## Token Permissions Reference

### Required Permissions

| Permission | ID | Purpose |
|------------|-----|---------|
| DNS - Edit | (auto) | Manage DNS records |
| Zone - Read | (auto) | Read zone configuration |
| Zone - Edit | (auto) | Modify zone settings |
| Cloudflare Access - Edit | (auto) | Create Zero Trust apps |
| Cloudflare Access - Read | (auto) | Read access policies |

### All Permissions Available

**Account**:
- Account Settings - Edit
- Account Settings - Read
- Account - Cloudflare Access: Edit
- Account - Cloudflare Access: Read

**Zone**:
- DNS - Edit
- SSL and Certificates - Edit
- Zone - Edit
- Zone - Read

**User**:
- User - DNS Edit
- User - Cloudflare Access
- User - Zone Read
- User - Zone Edit

---

## Troubleshooting

### Token Not Working

**Problem**: "Unauthorized" error

**Solution**:
1. Check token is copied correctly (no extra spaces)
2. Verify permissions include required scopes
3. Check token hasn't expired
4. Ensure IP restrictions aren't blocking you

### Can't See Token After Creation

**Problem**: Didn't copy token, can't find it

**Solution**:
1. Go to: https://dash.cloudflare.com/profile/api-tokens
2. Find your token in the list
3. Click: **"Edit"** (but you can't see the token again)
4. **Must create new token** (old tokens can't be viewed)

### Token Expired

**Problem**: Token stopped working

**Solution**:
1. Check expiration date in dashboard
2. Create new token with extended expiration
3. Update all scripts/services using old token
4. Revoke old token

---

## Next Steps

### Immediate (Today)

1. ✅ Create full-access token (5 minutes)
2. ✅ Test token verification
3. ✅ Store token securely with agenix

### This Week

1. 🔄 Use token to create Zero Trust app
2. 🔄 Automate access policy configuration
3. 🔄 Set up token rotation schedule

### Ongoing

1. 📋 Monitor token usage logs
2. 📋 Rotate tokens quarterly
3. 📋 Revoke unused tokens

---

## API Token Dashboard

**Manage tokens**: https://dash.cloudflare.com/profile/api-tokens

**What you can see**:
- Token name
- Creation date
- Expiration date
- Last used date
- Permissions summary

**What you can do**:
- Revoke tokens
- Edit name (not permissions)
- View usage logs

---

## Token vs. API Key

### API Token (What You're Creating)

**Best for**:
- ✅ Automation
- ✅ Scripting
- ✅ API access
- ✅ Security (can be revoked)

**Not for**:
- ❌ Client-side JavaScript
- ❌ Mobile apps
- ❌ Public-facing applications

### API Key (Alternative)

**Best for**:
- ✅ Simple integrations
- ✅ Legacy systems
- ✅ Basic authentication

**Not for**:
- ❌ Fine-grained permissions
- ❌ Security (harder to revoke)

---

**Time to complete**: 5 minutes
**Security impact**: HIGH (secure automation)
**Next**: Use token to automate Zero Trust setup
