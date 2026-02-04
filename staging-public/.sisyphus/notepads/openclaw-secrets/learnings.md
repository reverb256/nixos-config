# OpenClaw Secrets Setup - Learnings

## [2026-02-01] Module Import Issues

### Problem: Services.openclaw option doesn't exist
**Root Cause**: OpenClaw NixOS module wasn't imported in host configurations
- Hosts imported `openclaw-common.nix` but not `openclaw.nix`
- Common module depends on main module being available first

**Fix**: Added `../../modules/openclaw.nix` import to all 4 host configs
- Import order matters: main module before common module
- Pattern follows existing module imports in hosts

---

## [2026-02-01] Module Validation Issues

### Problem 1: Invalid module-level meta section
**Root Cause**: NixOS modules should not have module-level `meta` attributes
- Only packages should have `meta`, not modules
- Error: `The option 'meta.description' does not exist`

**Fix**: Removed lines 169-178 (meta section) from openclaw.nix
- Modules should end with just closing brace, no meta attributes

### Problem 2: Invalid user option homeDir
**Root Cause**: Wrong option name for users.homeDir
- Correct option is `home`, not `homeDir`
- Error: `The option 'users.users.openclaw.homeDir' does not exist`

**Fix**: Changed `homeDir = cfg.stateDir` to `home = cfg.stateDir`
- NixOS `users.users.<name>` uses `home` attribute

### Problem 3: Home Manager auth configuration conflict
**Root Cause**: Auth configuration in both NixOS module and Home Manager
- Home Manager expected `auth.type` but structure didn't match NixOS module
- Error: `The option 'home-manager.users.j_kro.programs.openclaw.instances.default.config.auth.type' does not exist`

**Fixes Applied**:
1. **home.nix**: Removed auth block from home-manager config
2. **flake.nix**: Added nix-openclaw overlay for `pkgs.openclaw`
3. **openclaw-common.nix**: Fixed infinite recursion in mkMerge call

---

## [2026-02-01] Agenix Integration Pattern

### Successful Pattern Used
```nix
# secrets/secrets.nix - Public key definitions
"secret-name".publicKeys = allHosts;

# secrets/age-secrets.nix - NixOS age.secrets config
"secret-name" = {
  file = ./secret-name.age;
};
```

### Secrets Created
- `anthropic-api-key.age` - Claude API access
- `openai-api-key.age` - OpenAI API access  
- `openclaw-env.age` - Environment file for service

### Environment Variables (in openclaw-env.age)
```bash
ANTHROPIC_API_KEY=placeholder-value
OPENAI_API_KEY=placeholder-value
```

### Service Integration
- OpenClaw common module expects: `/run/agenix/openclaw-env`
- EnvironmentFile option properly configured in openclaw-common.nix
- All secrets encrypted for all 4 hosts using existing keys

---

## Key Takeaways

1. **Module Dependencies**: Always import main module before common modules
2. **NixOS vs Package Structure**: NixOS modules don't use `meta` attributes
3. **Option Names**: Use correct NixOS option names (`home` not `homeDir`)
4. **Avoid Conflicts**: Don't configure same feature in both NixOS and Home Manager
5. **Agenix Pattern**: Follow existing secret patterns for consistency