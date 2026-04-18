# Bluesky/ATProto XRPC API Research Report
## For $0 Budget, Fully Self-Hosted Social Media Agent

Date: 2026-04-17

---

## 1. API ENDPOINTS (All via XRPC pattern: /xrpc/{NSID})

Base URL for bsky.social: https://bsky.social
All write operations go to the user's PDS. All endpoints use JSON.

### 1a. LOGIN / CREATE SESSION
**POST** `/xrpc/com.atproto.server.createSession`

Request body:
```json
{
  "identifier": "your-handle.bsky.social",
  "password": "xxxx-xxxx-xxxx-xxxx"
}
```

Response (200):
```json
{
  "accessJwt": "eyJ...",      // Bearer token for auth (JWT, expires ~2hr)
  "refreshJwt": "eyJ...",     // Used to refresh session
  "handle": "your-handle.bsky.social",
  "did": "did:plc:xxxxxxxxxxxx"
}
```

### 1b. REFRESH SESSION
**POST** `/xrpc/com.atproto.server.refreshSession`
- Auth: Bearer {refreshJwt}

### 1c. CREATE POST
**POST** `/xrpc/com.atproto.repo.createRecord`

```json
{
  "repo": "did:plc:your-did",
  "collection": "app.bsky.feed.post",
  "record": {
    "$type": "app.bsky.feed.post",
    "text": "Hello from the CLI!",
    "createdAt": "2024-01-15T12:00:00.000Z"
  }
}
```

Response: `{ "uri": "at://did:plc:.../app.bsky.feed.post/3k...", "cid": "bafyrei..." }`

### 1d. CREATE REPLY
**POST** `/xrpc/com.atproto.repo.createRecord`

```json
{
  "repo": "did:plc:your-did",
  "collection": "app.bsky.feed.post",
  "record": {
    "$type": "app.bsky.feed.post",
    "text": "Replying to your post!",
    "createdAt": "2024-01-15T12:00:00.000Z",
    "reply": {
      "root": {
        "uri": "at://did:plc:original-poster/app.bsky.feed.post/3k-original",
        "cid": "bafyrei-original-post-cid"
      },
      "parent": {
        "uri": "at://did:plc:original-poster/app.bsky.feed.post/3k-original",
        "cid": "bafyrei-original-post-cid"
      }
    }
  }
}
```
NOTE: For replies to a reply, root = the original post, parent = the post being replied to.

### 1e. LIKE A POST
**POST** `/xrpc/com.atproto.repo.createRecord`

```json
{
  "repo": "did:plc:your-did",
  "collection": "app.bsky.feed.like",
  "record": {
    "$type": "app.bsky.feed.like",
    "subject": {
      "uri": "at://did:plc:.../app.bsky.feed.post/3k...",
      "cid": "bafyrei..."
    },
    "createdAt": "2024-01-15T12:00:00.000Z"
  }
}
```

### 1f. REPOST
**POST** `/xrpc/com.atproto.repo.createRecord`

```json
{
  "repo": "did:plc:your-did",
  "collection": "app.bsky.feed.repost",
  "record": {
    "$type": "app.bsky.feed.repost",
    "subject": {
      "uri": "at://did:plc:.../app.bsky.feed.post/3k...",
      "cid": "bafyrei..."
    },
    "createdAt": "2024-01-15T12:00:00.000Z"
  }
}
```

### 1g. DELETE RECORD (unlike, unrepost, delete post)
**POST** `/xrpc/com.atproto.repo.deleteRecord`

```json
{
  "repo": "did:plc:your-did",
  "collection": "app.bsky.feed.like",
  "rkey": "3k-record-key-here"
}
```

### 1h. GET TIMELINE
**GET** `/xrpc/app.bsky.feed.getTimeline?limit=50&cursor=...`
- Auth: Bearer {accessJwt}
- limit: 1-100 (default 50)
- cursor: pagination token from previous response
- Response: `{ "cursor": "...", "feed": [{ "post": { ... } }] }`

### 1i. SEARCH POSTS
**GET** `/xrpc/app.bsky.feed.searchPosts?q=hello+world&sort=latest&limit=25&cursor=...`
- Auth: Bearer {accessJwt} (recommended) or unauthenticated
- q: required search query (Lucene-style syntax)
- sort: "top" or "latest" (default "latest")
- limit: 1-100 (default 25)

### 1j. GET NOTIFICATIONS
**GET** `/xrpc/app.bsky.notification.listNotifications?limit=50&cursor=...`
- Auth: Bearer {accessJwt}
- Optional: reasons filter (array of: "like", "repost", "follow", "mention", "reply", "quote", "starterpack-joined")

### 1k. UPDATE NOTIFICATIONS (mark as read)
**POST** `/xrpc/app.bsky.notification.updateSeen`
- Auth: Bearer {accessJwt}
- Body: `{ "seenAt": "2024-01-15T12:00:00.000Z" }`

### 1l. SEARCH ACTORS
**GET** `/xrpc/app.bsky.actor.searchActors?q=term&limit=25`

### 1m. GET POST THREAD
**GET** `/xrpc/app.bsky.feed.getPostThread?uri=at://did:plc:.../app.bsky.feed.post/3k...`

---

## 2. AUTHENTICATION FLOW

1. Create an "App Password" in Bluesky settings (Settings > Privacy and Security > App Passwords)
   - This gives you a password like `xxxx-xxxx-xxxx-xxxx`
   - App passwords are scoped (can't change account settings or delete account)

2. Login:
   ```
   POST https://bsky.social/xrpc/com.atproto.server.createSession
   Content-Type: application/json
   
   {"identifier": "handle.bsky.social", "password": "xxxx-xxxx-xxxx-xxxx"}
   ```

3. Receive JWT tokens:
   - `accessJwt`: Short-lived (~2 hours). Used as `Authorization: Bearer {accessJwt}`
   - `refreshJwt`: Longer-lived. Use to get new accessJwt

4. Refresh when expired:
   ```
   POST https://bsky.social/xrpc/com.atproto.server.refreshSession
   Authorization: Bearer {refreshJwt}
   ```

---

## 3. CONCRETE CURL EXAMPLES

### Login
```bash
curl -s -X POST https://bsky.social/xrpc/com.atproto.server.createSession \
  -H "Content-Type: application/json" \
  -d '{"identifier":"myhandle.bsky.social","password":"xxxx-xxxx-xxxx-xxxx"}' \
  | jq .
```

### Post
```bash
DID="did:plc:your-did"
TOKEN="your-accessJwt"
curl -s -X POST https://bsky.social/xrpc/com.atproto.repo.createRecord \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"repo\":\"$DID\",
    \"collection\":\"app.bsky.feed.post\",
    \"record\":{
      \"\$type\":\"app.bsky.feed.post\",
      \"text\":\"Hello from CLI at $(date -u +%Y-%m-%dT%H:%M:%SZ)\",
      \"createdAt\":\"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\"
    }
  }"
```

### Like
```bash
curl -s -X POST https://bsky.social/xrpc/com.atproto.repo.createRecord \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"repo\":\"$DID\",
    \"collection\":\"app.bsky.feed.like\",
    \"record\":{
      \"\$type\":\"app.bsky.feed.like\",
      \"subject\":{\"uri\":\"at://did:plc:xxx/app.bsky.feed.post/yyy\",\"cid\":\"bafyrei...\"},
      \"createdAt\":\"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\"
    }
  }"
```

### Repost
```bash
curl -s -X POST https://bsky.social/xrpc/com.atproto.repo.createRecord \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"repo\":\"$DID\",
    \"collection\":\"app.bsky.feed.repost\",
    \"record\":{
      \"\$type\":\"app.bsky.feed.repost\",
      \"subject\":{\"uri\":\"at://did:plc:xxx/app.bsky.feed.post/yyy\",\"cid\":\"bafyrei...\"},
      \"createdAt\":\"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\"
    }
  }"
```

### Reply (requires knowing root and parent URI/CID)
```bash
ROOT_URI="at://did:plc:xxx/app.bsky.feed.post/root-rkey"
ROOT_CID="bafyrei..."
PARENT_URI=$ROOT_URI
PARENT_CID=$ROOT_CID

curl -s -X POST https://bsky.social/xrpc/com.atproto.repo.createRecord \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"repo\":\"$DID\",
    \"collection\":\"app.bsky.feed.post\",
    \"record\":{
      \"\$type\":\"app.bsky.feed.post\",
      \"text\":\"Nice post!\",
      \"createdAt\":\"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",
      \"reply\":{
        \"root\":{\"uri\":\"$ROOT_URI\",\"cid\":\"$ROOT_CID\"},
        \"parent\":{\"uri\":\"$PARENT_URI\",\"cid\":\"$PARENT_CID\"}
      }
    }
  }"
```

### Get Timeline
```bash
curl -s "https://bsky.social/xrpc/app.bsky.feed.getTimeline?limit=20" \
  -H "Authorization: Bearer $TOKEN" | jq '.feed[0].post | {author: .author.handle, text: .record.text}'
```

### Search Posts
```bash
curl -s "https://bsky.social/xrpc/app.bsky.feed.searchPosts?q=hello+world&limit=10" \
  -H "Authorization: Bearer $TOKEN" | jq '.posts[] | {author: .author.handle, text: .record.text}'
```

### Get Notifications
```bash
curl -s "https://bsky.social/xrpc/app.bsky.notification.listNotifications?limit=20" \
  -H "Authorization: Bearer $TOKEN" | jq '.notifications[0] | {reason: .reason, author: .author.handle}'
```

### Delete a post/like/repost
```bash
RKEY="the-record-key-from-create-response"
curl -s -X POST https://bsky.social/xrpc/com.atproto.repo.deleteRecord \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"repo\":\"$DID\",\"collection\":\"app.bsky.feed.post\",\"rkey\":\"$RKEY\"}"
```

---

## 4. RATE LIMITS

### Content Write Operations (per account/DID)
- 5,000 points per hour / 35,000 points per day
- CREATE = 3 points, UPDATE = 2 points, DELETE = 1 point
- Effectively: ~1,666 creates/hour, ~11,666 creates/day
- Covers posts, likes, reposts, follows, etc.

### HTTP API Rate Limits (per PDS, by IP)
- Overall: 3,000 requests per 5 minutes
- createSession: 30 per 5 min per account, 300 per day
- createAccount: 100 per 5 min per IP

### Blob Uploads
- Max 50MB per blob

### Rate Limit Headers (returned in responses)
- `RateLimit-Limit`: Max requests in window
- `RateLimit-Remaining`: Remaining in current window  
- `RateLimit-Reset`: Unix timestamp when window resets
- `RateLimit-Policy`: Policy string (e.g., "100;w=300")

### Relay Limits (for self-hosted PDS)
- 50 events/second, 1,500/hour, 10,000/day
- 5 new accounts/second

VERDICT: Very generous for a single-user bot/agent. No paid tiers needed.

---

## 5. SELF-HOSTED PDS VIABILITY

**YES - Fully viable and officially supported.**

Repository: https://github.com/bluesky-social/pds (★2470)

### Requirements
- Any VPS with public IPv4, 1GB RAM, 1 CPU, 20GB SSD
- Public DNS name pointing to the server
- Ports 80/tcp and 443/tcp open
- Docker + Docker Compose (Caddy handles TLS automatically)

### Install (one-liner on Ubuntu/Debian)
```bash
sudo -S -p '' bash -c "$(curl -fsSL https://raw.githubusercontent.com/bluesky-social/pds/main/installer.sh)"
```

### Key facts
- Free and open source (MIT license / Apache 2.0)
- Self-hosted accounts can federate with the full Bluesky network
- Supports custom domain handles (e.g., @yourdomain.com)
- No invite codes needed for self-hosted PDS
- Can migrate accounts between PDS instances
- Full API compatibility - all XRPC endpoints work
- Rate limits are YOURS to configure on your own PDS

### Environment Variables
Key env vars for configuration:
- `PDS_HOSTNAME`: your domain
- `PDS_JWT_SECRET`: for signing tokens
- `PDS_ADMIN_PASSWORD`: admin access
- `PDS_DATA_DIR`: data storage path
- SMTP settings for email verification

### Limitations
- You need to handle your own backups
- Your PDS must stay online for your data to be accessible
- Relay sync can lag if your server goes down

---

## 6. EXISTING CLI TOOLS

### RECOMMENDED: mattn/bsky (Go, ★441)
**https://github.com/mattn/bsky**

The best option. Feature-complete Go CLI with MCP server mode.

Install:
```bash
go install github.com/mattn/bsky@latest
# Or download binary from GitHub releases
```

Commands:
```bash
bsky login handle.bsky.social xxxx-xxxx-xxxx-xxxx
bsky timeline                    # View timeline
bsky post "Hello World!"         # Create post
bsky post -image photo.jpg "Caption"  # Post with image
bsky vote at://did:plc:.../app.bsky.feed.post/rkey  # Like
bsky repost at://did:plc:.../app.bsky.feed.post/rkey # Repost
bsky search "query"              # Search posts
bsky notification                # View notifications
bsky thread at://...             # View thread
bsky follow handle.bsky.social   # Follow user
bsky delete at://...             # Delete post
bsky show-profile handle         # Show profile
bsky stream                      # Live timeline stream
bsky mcp                         # Start MCP server (for AI agents!)
```

MCP Server mode (for AI agent integration):
```json
// ~/.claude/settings.json or similar
{
  "mcpServers": {
    "bsky": {
      "command": "bsky",
      "args": ["mcp"]
    }
  }
}
```

MCP tools available: bluesky_timeline, bluesky_post, bluesky_search, bluesky_show_profile,
bluesky_search_actors, bluesky_thread, bluesky_notification, bluesky_like, bluesky_repost, bluesky_follow

### Alternative: bsky-sh-cli (Pure Shell, ★21)
**https://github.com/bills-appworks/bsky-sh-cli**

Pure shell script implementation. Good for environments without Go.
Requires: curl, jq, and standard Unix tools.

Install:
```bash
curl https://raw.githubusercontent.com/bills-appworks/bsky-sh-cli/main/download-install.sh -O
sh download-install.sh
```

Commands:
```bash
bsky login --handle myhandle --password xxxx
bsky timeline
bsky post --text "Hello"
bsky reply --index 1 --text "Reply text"
bsky like --index 1
bsky repost --index 1
bsky notification
bsky search --query "hello"
```

### Other Notable Tools
- `FormerLab/fortransky` (★46) - Terminal TUI client in Fortran
- `kristoff-it/simplex` (★41) - Cross-platform CLI for Twitter+Mastodon+Bluesky
- `cuducos/not-my-ex` (★17) - Cross-post to Mastodon+Bluesky

---

## 7. SUMMARY & RECOMMENDATIONS

For a $0 budget self-hosted social media agent:

1. **Use mattn/bsky** as the primary CLI tool. It's mature, has JSON output (`--json`), 
   and includes an MCP server mode perfect for AI agent integration.

2. **Alternatively use raw curl** for maximum control. All endpoints are simple 
   JSON POST/GET - no complex SDK needed.

3. **Self-host a PDS** if you want full data sovereignty. The official PDS Docker 
   image runs on a $5/month VPS (1GB RAM). Otherwise, bsky.social PDS is free.

4. **No paid API tiers exist.** The AT Protocol is fully open. Rate limits are 
   generous enough for any reasonable bot or agent use case.

5. **Key workflow:**
   - Login → store accessJwt + refreshJwt + did
   - Use Bearer token for all subsequent requests
   - Refresh token when expired
   - Create records via com.atproto.repo.createRecord
   - Read via app.bsky.feed.* and app.bsky.notification.* GET endpoints

