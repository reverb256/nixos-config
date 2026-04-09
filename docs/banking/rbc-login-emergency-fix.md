# Emergency RBC Login Fix

## Quick Test: Clean Profile

```bash
zen --profile /tmp/zen-clean-rbc
```

Try logging into RBC. If this works, your privacy settings are blocking login.

## Permanent Fix: Banking Profile

### Option 1: Manual Setup (Fastest)

1. **Close Zen Browser completely**

2. **Create Banking Profile:**
   ```bash
   zen --ProfileManager
   ```
   - Click "Create Profile"
   - Name: "Banking"
   - Click "Finish"

3. **Launch Banking Profile:**
   ```bash
   zen -P Banking
   ```

4. **Verify Settings** (type `about:config` in address bar):
   - `privacy.resistFingerprinting` = `false` ✅
   - `javascript.enabled` = `true` ✅
   - `network.cookie.cookieBehavior` = `0` ✅

5. **Test RBC Login**

This profile has zero privacy hardening - just standard Firefox defaults. RBC should work.

### Option 2: Add to NixOS Config (Declarative)

Edit `/etc/nixos/modules/home-manager/zen-browser.nix` and add after the `default` profile:

```nix
profiles.banking = {
  id = 1;
  name = "banking";
  isDefault = false;

  containersForce = true;
  pinsForce = true;
  spacesForce = true;

  # Relaxed privacy for banking compatibility
  extraConfig = ''
    // Disable privacy features that break banking sites
    user_pref("privacy.resistFingerprinting", false);
    user_pref("network.http.referer.spoofSource", false);
    user_pref("network.cookie.cookieBehavior", 0); // Allow all cookies
    user_pref("privacy.trackingprotection.enabled", false);

    // Keep security features
    user_pref("dom.security.https_only_mode", true);
    user_pref("javascript.enabled", true);

    // Zen UI preferences
    user_pref("zen.workspaces.vertical", true);
    user_pref("zen.view.compact", true);
  '';

  // Minimal extensions - only Bitwarden
  extensions = with pkgs.nur.repos.rycee.firefox-addons; [
    bitwarden
  ];

  // Banking workspace
  spaces = {
    "RBC" = {
      id = "rbc-banking";
      icon = "🏦";
      position = 1000;
    };
  };
};
```

Then apply:
```bash
just switch
```

Launch with:
```bash
zen -P banking
```

## What's Breaking Login?

Most likely culprit: **Canvas fingerprinting protection**

RBC uses canvas for:
- Device fingerprinting (fraud prevention)
- Security verification
- CAPTCHA alternatives

When Zen blocks this, RBC's login fails silently.

**The fix:** Disable `privacy.resistFingerprinting` for banking.

## Testing Checklist

- [ ] Clean profile login works → It's your privacy settings
- [ ] Clean profile fails → It's RBC or network issue
- [ ] Banking profile login works → Use Banking profile going forward
- [ ] Still failing → Check specific errors in Browser Console (Ctrl+Shift+J)

## If Still Failing

Open Browser Console (`Ctrl+Shift+J`) while trying to login and look for:

1. **Red errors** (not warnings) - these show what's breaking
2. **Network tab** (`Ctrl+Shift+E` → Network) - see failed requests
3. **CORS errors** - cross-origin request blocking

Screenshot the console and we'll debug further.

## Temporary Workaround

If you need to access banking RIGHT NOW and nothing works:

1. Use a different browser (Chromium, unconfigured Firefox)
2. Use RBC's mobile app
3. Use a public computer (library, etc) - change password immediately after

---

**Last Updated:** 2026-03-21
**Status:** Emergency troubleshooting guide
