# Add Permissions to Your Existing Cloudflare Token

**Your current token**: `cfut_iotByCUQLpSaYNMwiS1IdIvYtjJTTGexDrPKCLev854ddfb5`

---

## Step 1: Find Your Token (30 seconds)

1. Go to: https://dash.cloudflare.com/profile/api-tokens
2. Find: **Akash Provider** (or your token name)
3. Click: **Edit** button

---

## Step 2: Add These Permissions (2 minutes)

### ✅ REQUIRED: Cloudflare Access (for Zero Trust)

**Account** → **Your Account** → **Cloudflare Access**:
```
☑️ Account - Cloudflare Access: Edit
☑️ Account - Cloudflare Access: Read
```

**Why needed**: Create and manage Zero Trust applications for provider security

### ✅ REQUIRED: Zone Management (for DNS + Tunnel)

**Zone** → **reverb256.ca**:
```
☑️ DNS - Edit
☑️ Zone - Read
☑️ Zone - Edit
☑️ SSL and Certificates - Edit
```

**Why needed**:
- DNS Edit: Manage provider DNS records
- Zone Read: View tunnel configuration
- Zone Edit: Modify tunnel settings
- SSL Certificates: Manage HTTPS for provider

### ✅ OPTIONAL: User Permissions (for convenience)

**User** (if available):
```
☑️ User - DNS Edit
☑️ User - Cloudflare Access
```

**Why needed**: Convenience permissions that work across all zones

---

## Step 3: Save Changes (30 seconds)

1. Click: **"Continue to summary"**
2. Review: Verify all permissions are added
3. Click: **"Update Token"**

**Important**: Your token value stays the same! Just adding permissions.

---

## What Each Permission Does

### Cloudflare Access Permissions

| Permission | What It Enables |
|------------|----------------|
| **Account - Cloudflare Access: Read** | List Zero Trust apps, view policies |
| **Account - Cloudflare Access: Edit** | Create apps, add policies, configure auth |

**Use cases**:
- ✅ Create Zero Trust application for provider
- ✅ Add email/GitHub authentication
- ✅ Configure access policies
- ✅ View access logs

### Zone Permissions

| Permission | What It Enables |
|------------|----------------|
| **DNS - Edit** | Add/remove DNS records for provider |
| **Zone - Read** | View zone settings, tunnel configuration |
| **Zone - Edit** | Modify zone settings, tunnel config |
| **SSL and Certificates - Edit** | Manage HTTPS certificates |

**Use cases**:
- ✅ Update provider DNS records
- ✅ Modify cloudflared tunnel configuration
- ✅ Configure SSL for provider endpoints
- ✅ Manage certificate renewal

---

## Before vs After

### Before (Current Token)

```
✅ Token verification
❌ Create Zero Trust apps
❌ Configure access policies
❌ Modify DNS records
❌ Manage tunnels
```

**What works**: Basic operations only

### After (With Added Permissions)

```
✅ Token verification
✅ Create Zero Trust apps
✅ Configure access policies
✅ Modify DNS records
✅ Manage tunnels
✅ Full automation
```

**What works**: Everything we need for Akash provider!

---

## How Permissions Work

### Permission Inheritance

When you grant permissions:

**Account-level** permissions apply to:
- All zones under your account
- All Cloudflare Access applications
- All account settings

**Zone-level** permissions apply to:
- Specific zone only (reverb256.ca)
- DNS records for that zone
- Tunnel settings for that zone

**User-level** permissions apply to:
- All zones (convenience)
- User-specific settings
- Cross-zone operations

### Permission Scopes

**Account** scope (widest):
```
Account → Cloudflare Access → Edit
→ Applies to ALL Access apps in account
```

**Zone** scope (narrower):
```
Zone → reverb256.ca → DNS → Edit
→ Applies ONLY to reverb256.ca DNS
```

**User** scope (convenience):
```
User → DNS Edit
→ Applies to ALL zones you own
```

---

## Testing Your Updated Token

### Test 1: Verify Token Works (After Permission Update)

```bash
# Wait 1-2 minutes for permissions to propagate
sleep 120

# Verify token
curl "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer cfut_iotByCUQLpSaYNMwiS1IdIvYtjJTTGexDrPKCLev854ddfb5" \
  | jq '.'

# Expected: Same response (token still valid)
```

### Test 2: List Zero Trust Applications

```bash
# Try listing Access apps (should work after permission update)
curl "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/access/apps" \
  -H "Authorization: Bearer cfut_iotByCUQLpSaYNMwiS1IdIvYtjJTTGexDrPKCLev854ddfb5" \
  2>&1 | head -20

# If permissions updated: Returns list of apps (or empty array)
# If permissions missing: Returns 403 Unauthorized
```

### Test 3: Get Zone Details

```bash
# Try getting zone info
curl "https://api.cloudflare.com/client/v4/zones/9062487114ef5404de8de6689cb54895" \
  -H "Authorization: Bearer cfut_iotByCUQLpSaYNMwiS1IdIvYtjJTTGexDrPKCLev854ddfb5" \
  | jq '.result | {id, name, status}'

# Expected: Zone details for reverb256.ca
```

---

## Troubleshooting

### "Authentication Error" After Permission Update

**Problem**: Still getting authentication errors

**Solution**:
1. **Wait for propagation**: Permissions take 1-2 minutes
2. **Check permission scope**: Ensure correct account/zone selected
3. **Verify token ID**: Make sure you edited the right token

### "Unauthorized" on Specific Endpoints

**Problem**: Some endpoints work, others don't

**Solution**:
1. Check which zone/account the endpoint requires
2. Verify you added permissions for that specific zone/account
3. Some operations need multiple permissions

### Can't Find Permission to Add

**Problem**: Don't see the permission listed

**Solution**:
1. **Search by name**: Use the search bar in permission picker
2. **Check account**: Some permissions are account-specific
3. **Contact support**: Some permissions require special access

---

## Permission Reference

### Full Permission List for Akash Provider

**Account Permissions**:
```
Account → Cloudflare Access
  ☑️ Read
  ☑️ Edit
```

**Zone Permissions** (for reverb256.ca):
```
Zone → DNS
  ☑️ Edit

Zone → Zone
  ☑️ Read
  ☑️ Edit

Zone → SSL and Certificates
  ☑️ Edit
```

**User Permissions** (optional):
```
User → DNS Edit
User → Cloudflare Access
```

### Minimal Permissions (if you want to be restrictive)

**If you only need Zero Trust**:
```
Account → Cloudflare Access: Edit
```

**If you only need DNS management**:
```
Zone → reverb256.ca → DNS: Edit
```

**If you only need tunnel management**:
```
Zone → reverb256.ca → Zone: Edit
```

---

## Security Considerations

### Principle of Least Privilege

**Best practice**: Grant only permissions you need

**For Zero Trust automation**:
- ✅ Account - Cloudflare Access: Edit
- ❌ All account permissions (too broad)

**For DNS automation**:
- ✅ Zone - DNS: Edit (reverb256.ca only)
- ❌ Account - All Zones: Edit (too broad)

### Token vs. API Key

**API Token** (what you're using):
- ✅ Fine-grained permissions
- ✅ Can be revoked
- ✅ Can have expiration
- ✅ Audit trail

**API Key** (legacy, not recommended):
- ❌ All-or-nothing permissions
- ❌ Harder to revoke
- ❌ No expiration
- ❌ Limited audit trail

---

## Quick Reference

### Permissions Checklist

Copy this checklist to ensure you have all permissions:

- [ ] **Account → Cloudflare Access: Read**
- [ ] **Account → Cloudflare Access: Edit**
- [ ] **Zone → reverb256.ca → DNS: Edit**
- [ ] **Zone → reverb256.ca → Zone: Read**
- [ ] **Zone → reverb256.ca → Zone: Edit**
- [ ] **Zone → reverb256.ca → SSL and Certificates: Edit**
- [ ] **User → DNS Edit** (optional)
- [ ] **User → Cloudflare Access** (optional)

### After Adding Permissions

1. Wait 1-2 minutes for propagation
2. Test token verification
3. Try listing Zero Trust apps
4. Try getting zone details
5. Verify all tests pass

---

## What's Next

### After Adding Permissions (5 minutes)

1. ✅ Permissions updated in dashboard
2. ✅ Wait 1-2 minutes for propagation
3. ✅ Test token with verification endpoint
4. ✅ Test listing Zero Trust apps
5. ✅ Test getting zone details

### Then We Can (Automated Setup)

1. 🚀 Create Zero Trust application via API
2. 🚀 Configure access policies via API
3. 🚀 Add authentication methods via API
4. 🚀 Test everything automatically

**Time savings**: 10 minutes (manual) → 2 minutes (automated)

---

## Support

**Cloudflare docs**: https://developers.cloudflare.com/api/
**Permission reference**: https://developers.cloudflare.com/api/permissions/

---

**Time to add permissions**: 2 minutes
**Impact**: Enables full automation for Akash provider
**Next**: Automated Zero Trust setup via API
