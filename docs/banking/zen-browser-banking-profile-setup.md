# Zen Browser - Banking Profile with Relaxed Privacy

## Why Separate Profile?

The default Zen profile has **hardened privacy settings** (fingerprinting resistance, tracking protection, canvas blocking) that break some banking sites. A dedicated Banking profile allows you to:

- Keep default profile hardened for general browsing
- Have relaxed settings specifically for financial institutions
- Isolate banking sessions from regular browsing

## Quick Setup (Manual)

### Step 1: Create New Profile

1. Close Zen Browser completely
2. Run: `zen --ProfileManager`
3. Click "Create Profile"
4. Name it "Banking"
5. Choose profile directory (default: `~/.zen/banking/`)
6. Click "Finish"

### Step 2: Launch with Relaxed Settings

The Banking profile starts with default Firefox/Zen settings (no privacy hardening):

```bash
zen -P banking
```

### Step 3: Configure Banking Profile Settings

**Type in address bar:** `about:config`

**Relax these settings for banking compatibility:**

```
# Disable fingerprinting resistance (breaks some banking sites)
privacy.resistFingerprinting = false

# Allow referer headers (banking sites may require for navigation)
network.http.referer.spoofSource = false

# Standard cookie behavior (allow first-party, allow third-party)
network.cookie.cookieBehavior = 0

# Disable strict tracking protection (use standard instead)
privacy.trackingprotection.enabled = false
privacy.trackingprotection.pbmode.enabled = false

# Keep HTTPS-only mode (security, not privacy)
dom.security.https_only_mode = true
```

### Step 4: Install Essential Extensions Only

In the Banking profile, install **minimal** extensions:
- Bitwarden (password manager) - already in your config
- Skip: uBlock, NoScript, Privacy Badger, Canvas blockers

### Step 5: Set Up Banking Sites

1. Navigate to RBC Royal Bank
2. Login and save credentials to Bitwarden
3. Create bookmarks for banking sites
4. Test functionality - no more canvas fingerprinting errors

## Automate with NixOS (Optional)

If you want the Banking profile managed declaratively, add to `zen-browser.nix`:

```nix
programs.zen-browser = {
  enable = true;

  # Existing default profile (hardened)...

  # New Banking profile (relaxed privacy)
  profiles.banking = {
    id = 1;
    name = "banking";
    isDefault = false;

    containersForce = true;
    pinsForce = true;
    spacesForce = true;

    # Banking-specific about:config
    extraConfig = ''
      // Relaxed privacy for banking compatibility
      user_pref("privacy.resistFingerprinting", false);
      user_pref("network.http.referer.spoofSource", false);
      user_pref("network.cookie.cookieBehavior", 0); // Allow all cookies
      user_pref("privacy.trackingprotection.enabled", false);

      // Keep security features
      user_pref("dom.security.https_only_mode", true);

      // Banking workspace
      user_pref("zen.workspaces.vertical", true);
    '';

    # Minimal extensions for banking
    extensions = with pkgs.nur.repos.rycee.firefox-addons; [
      bitwarden
      # Skip: ublock-origin, noscript, privacy-badger
    ];

    # Banking workspace
    spaces = {
      "RBC" = {
        id = "rbc-primary";
        icon = "🏦";
        position = 1000;
      };
      "TD" = {
        id = "td-secondary";
        icon = "🏦";
        position = 2000;
      };
    };
  };
};
```

After adding this, run:
```bash
just switch  # Apply Home Manager changes
```

## Launch Banking Profile

**Manually:**
```bash
zen -P banking
```

**With systemd user service** (add to your config):
```nix
systemd.user.services.zen-banking = {
  Unit = {
    Description = "Zen Browser - Banking Profile";
  };
  Service = {
    ExecStart = "${pkgs.zen-browser}/bin/zen -P banking";
    Restart = "on-abnormal";
  };
  Install.WantedBy = ["graphical-session.target"];
};
```

Then: `systemctl --user start zen-banking`

## Trade-offs

### Banking Profile Pros:
- ✅ Banking sites work without errors
- ✅ Isolated from regular browsing (separate cookies, history, cache)
- ✅ Can still use Bitwarden for passwords
- ✅ Keeps main profile hardened

### Banking Profile Cons:
- ❌ Manual profile switching required
- ❌ No tracking protection on banking sites
- ❌ Need to install extensions separately
- ❌ Double browser instances = more RAM usage

## Alternative: Use Firefox ESR for Banking

If you don't want a second Zen profile, use Firefox ESR specifically for banking:

```nix
programs.firefox = {
  enable = true;
  profiles.banking = {
    # Relaxed settings for banking...
  };
};
```

This gives you a completely separate browser with no privacy hardening.

## Security Considerations

**Is relaxed privacy safe for banking?**

Yes, because:
- Banks use HTTPS encryption (you're forcing HTTPS-only mode)
- Banks have their own security (fraud detection, 2FA, device auth)
- Your threat model for banking is different from general browsing
- You're isolating banking to a separate profile/container

**What you're giving up:**
- Canvas fingerprinting protection (banks track you anyway)
- Tracker blocking (banks don't load third-party trackers typically)
- Referer hiding (banks need to know where you came from for navigation)

## Recommendation

**For temporary RBC access:** Use extension exceptions (Option 1)

**For regular banking:** Create Banking profile (Option 2)

**For maximum security:** Use a separate Firefox ESR installation just for banking

---

**Last Updated:** 2026-03-21
