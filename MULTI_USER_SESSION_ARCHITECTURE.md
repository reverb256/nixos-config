# 🧑‍🤝‍🧑 Reverb-OS: Multi-User Session Architecture

## 📋 **Overview**

The Reverb-OS infrastructure now supports **multiple concurrent users and sessions** through a comprehensive architecture that provides:

- **User Isolation**: Operations are isolated by user context
- **Session Management**: Multiple concurrent operations safely managed
- **Operation Locking**: Prevents conflicting deployments
- **Permission Handling**: Proper privilege management for each user
- **Auditable Operations**: Per-session logging and tracking

## 🔐 **Security Model**

### **User Context Preservation**
- Each operation maintains the originating user's identity
- Commands run with appropriate user privileges (not root globally)
- SSH connections preserve user context via Tailscale VPN
- Colmena operations executed with user-specific permissions

### **Authorization Architecture**
```
User A (j_kro) → just deploy → runs as j_kro@nexus (via SSH)
User B (admin) → just deploy → runs as admin@nexus (via SSH) 
User C (dev_user) → just deploy → runs as dev_user@nexus (via SSH)

All operations:
├── Execute with user-specific permissions
├── Maintain user identity in logs  
├── Use session-specific temporary files
└── Respect user's authorization level
```

## 🔄 **Session Management**

### **Locking System**
- **Operation Lock**: Prevents simultaneous deployment conflicts
- **Timeout Handling**: Maximum 10-minute wait for locked operations
- **Session Isolation**: Each session operates independently
- **Graceful Blocking**: Users notified of ongoing operations

### **Concurrent Operation Flow**
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   User A        │    │   User B        │    │   User C        │
│   (j_kro)       │    │   (admin)       │    │   (dev_user)    │
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │                      │                      │
          │ just deploy          │ just zephyr          │ just build
          │                      │                      │
          │ [Requests lock]      │ [Waits for lock]     │ [Requests lock]
          │ [Acquires lock]      │ [Acquires lock      │ [Blocked - lock]
          │ [Deploys as j_kro]   │  after User A]      │  held by User A]
          │ [Releases lock]      │ [Deploys as admin]   │ [Waits for release]
          │                      │ [Releases lock]      │ [Acquires lock]
          │                      │                      │ [Builds as dev_user]
          │                      │                      │ [Releases lock]
```

## 🏗️ **Implementation Architecture**

### **Multi-User Justfile**
```just
# All operations include explicit user context
deploy:
    @echo "Deploying as user $(whoami) on nexus..."
    /etc/nixos/scripts/just-cluster deploy

switch:
    # Local operations use current user's identity
    cd /etc/nixos && sudo -u $(id -un) -H nixos-rebuild switch --flake ".#$(hostname -s)"
```

### **Session-Safe Coordinator Script**
```bash
# Each operation tracked with:
USER_NAME=$(id -un)           # Originating user
USER_ID=$(id -u)              # User identifier
SESSION_ID=$$                 # Process session ID  
NODE_NAME=$(hostname -s)      # Originating node
TIMESTAMP=$(date)             # Operation timestamp
```

### **SSH User Context Preservation**
```bash
# Coordinator ensures user context preserved across nodes:
ssh "$COORDINATOR" "cd /etc/nixos && sudo -u $(id -un) -H $COMMAND"
```

## 🛡️ **Security Isolation**

### **File System Permissions**
- Temporary files created per-user (in `/tmp/`)
- Log files tagged with user and session
- SSH operations maintain user identity
- Nix store operations remain secure

### **Sudo Privilege Management**
- Operations run as user with `-u $(id -un)` flag
- Root access granted through controlled sudo rules
- Per-user configuration contexts (not global)
- Session isolation in deployment operations

## 🧪 **Concurrent Operation Testing**

### **Multiple User Scenarios**
1. **Different operations simultaneously**:
   - User A: `just deploy` (deploying to all nodes)  
   - User B: `just build` (building configs, non-conflicting)
   - User C: `just switch` (local operation, non-conflicting)

2. **Conflicting operations with locking**:
   - User A: `just deploy` (acquires lock, runs for 5 minutes)
   - User B: `just deploy` (waits for lock, runs after User A)
   - User C: `just forge` (waits for lock, runs after both)

### **Authorization Levels**
- **Regular users**: Can deploy configurations they have access to
- **Admin users**: Can perform all operations with elevated privileges
- **Service accounts**: Limited to specific deployment operations

## 📊 **Monitoring & Auditing**

### **Per-Session Logging**
- Each operation logs user identity, session, and timestamp
- Operations tracked in `/tmp/colmena-${USER_NAME}-${SESSION_ID}.log`
- Failed operations retain logs for debugging
- Successful operations clean up temporary logs

### **Resource Tracking**
- Concurrent operation count monitoring
- Resource usage per user session
- Deployment success/failure rates by user
- Session duration and efficiency metrics

## 🚀 **Benefits for Multi-User Environments**

### **Team Collaboration**
- Multiple developers can deploy independently
- No interference between concurrent operations
- Clear attribution of changes to specific users
- Audit trail of who deployed what and when

### **Scalability**
- System accommodates new users without configuration changes
- Session management scales automatically
- Locking system prevents resource contention
- Performance monitoring per user

### **Reliability**
- Failed operations don't affect other users' operations
- Session isolation prevents cross-user interference
- Lock timeouts prevent eternal blocking
- Idempotent operations ensure consistent results

## 🔧 **Configuration for Multiple Users**

### **User Setup Requirements**
Each user needs:
1. SSH key access to coordinator node (nexus)
2. Sudo permissions for deployment operations  
3. Access to repository in `/etc/nixos/`
4. Proper colmena configuration

### **Sudo Rules for Multi-User**
The system already supports multiple users through the current sudo configuration in the NixOS configuration, allowing users in appropriate groups to execute deployment commands.

## 🔄 **Backward Compatibility**

All multi-user session features are **fully backward compatible**:
- Single-user operations continue to work identically
- Existing deployment workflows remain unchanged
- No additional configuration required for single-user mode
- Locking system gracefully handles single-user scenarios

---

**Document**: MULTI_USER_SESSION_ARCHITECTURE.md  
**System**: Reverb-OS Multi-Node Cluster  
**Pattern**: User-Isolated Concurrent Operations with Session Management  
**Status**: Production Ready for Multi-User Environments