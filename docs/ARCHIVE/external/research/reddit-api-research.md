# Reddit API (OAuth2) Research for CLI Social Media Skill

## 1. OAuth2 Flow for Script-Type Apps (Password Grant)

### App Registration
1. Go to https://www.reddit.com/prefs/apps
2. Click "are you a developer? create an app..."
3. Fill in:
   - **name**: your app name
   - **App type**: select **script** (runs on hardware you control, can keep a secret, only accesses developer account)
   - **description**: optional
   - **about url**: optional
   - **redirect uri**: http://localhost:8080 (required but unused for script apps)
4. Click "create app"
5. Note the **client_id** (under the app name) and **client_secret** (labeled "secret")

### Password Grant Flow (curl)

Step 1 - Acquire access token (POST to www.reddit.com):
```
curl -X POST -d 'grant_type=password&username=YOUR_USERNAME&password=YOUR_PASSWORD' \
  --user 'CLIENT_ID:CLIENT_SECRET' \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  https://www.reddit.com/api/v1/access_token
```

Response:
```json
{
    "access_token": "J1qK1c18UUGJFAzz9xnH56584l4",
    "expires_in": 3600,
    "scope": "*",
    "token_type": "bearer"
}
```

Step 2 - Use the token (GET/POST to oauth.reddit.com):
```
curl -H "Authorization: bearer ACCESS_TOKEN" \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  https://oauth.reddit.com/api/v1/me
```

IMPORTANT: Token requests go to www.reddit.com, API requests go to oauth.reddit.com.

### With 2FA enabled
Append the OTP to the password: password=YOUR_PASSWORD:OTP_CODE

### Token Refresh
Tokens expire after 3600 seconds (1 hour). For script apps, just re-authenticate with the password grant.

## 2. API Endpoints with curl Examples

All API calls use base URL: https://oauth.reddit.com
All require header: Authorization: bearer ACCESS_TOKEN
All require unique User-Agent: User-Agent: platform:app_id:version (by /u/username)

### A. Get Identity (who am I)
```
curl -H "Authorization: bearer $TOKEN" \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  https://oauth.reddit.com/api/v1/me
```

### B. Read Subreddit (get hot posts)
```
# Hot posts
curl -H "Authorization: bearer $TOKEN" \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  https://oauth.reddit.com/r/python/hot?limit=25

# New posts
curl -H "Authorization: bearer $TOKEN" \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  https://oauth.reddit.com/r/python/new?limit=25

# Top posts (time: hour, day, week, month, year, all)
curl -H "Authorization: bearer $TOKEN" \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  "https://oauth.reddit.com/r/python/top?t=day&limit=25"
```

### C. Get Comments for a Post
```
curl -H "Authorization: bearer $TOKEN" \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  "https://oauth.reddit.com/r/python/comments/ARTICLE_ID?limit=25"
```

### D. Submit a Post (link or self)
```
# Submit a link post
curl -X POST -H "Authorization: bearer $TOKEN" \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  -d 'sr=python&kind=link&title=My%20Title&url=https://example.com&api_type=json' \
  https://oauth.reddit.com/api/submit

# Submit a self (text) post
curl -X POST -H "Authorization: bearer $TOKEN" \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  -d 'sr=python&kind=self&title=My%20Title&text=My%20post%20body&api_type=json' \
  https://oauth.reddit.com/api/submit
```

### E. Comment on a Post or Comment
```
# Comment on a post (parent is the post fullname, e.g., t3_abc123)
curl -X POST -H "Authorization: bearer $TOKEN" \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  -d 'parent=t3_abc123&text=My%20comment%20text&api_type=json' \
  https://oauth.reddit.com/api/comment

# Reply to a comment (parent is comment fullname, e.g., t1_abc123)
curl -X POST -H "Authorization: bearer $TOKEN" \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  -d 'parent=t1_abc123&text=My%20reply%20text&api_type=json' \
  https://oauth.reddit.com/api/comment
```

### F. Search
```
# Search all of Reddit
curl -H "Authorization: bearer $TOKEN" \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  "https://oauth.reddit.com/search?q=python+async&sort=relevance&t=all&limit=25"

# Search within a subreddit
curl -H "Authorization: bearer $TOKEN" \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  "https://oauth.reddit.com/r/python/search?q=asyncio&sort=new&t=week&limit=25&restrict_sr=on"
```

### G. Get Inbox / Notifications
```
# Get unread messages
curl -H "Authorization: bearer $TOKEN" \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  https://oauth.reddit.com/message/unread?limit=25

# Get all inbox messages
curl -H "Authorization: bearer $TOKEN" \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  https://oauth.reddit.com/message/inbox?limit=25

# Get comment replies
curl -H "Authorization: bearer $TOKEN" \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  https://oauth.reddit.com/message/comments?limit=25

# Mark messages as read
curl -X POST -H "Authorization: bearer $TOKEN" \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  -d 'id=t4_abc123' \
  https://oauth.reddit.com/api/read_message
```

### H. Vote (Upvote/Downvote/Unvote)
```
# Upvote (dir=1), Downvote (dir=-1), Unvote (dir=0)
# fullname is the thing ID, e.g., t3_abc123 (post) or t1_abc123 (comment)
curl -X POST -H "Authorization: bearer $TOKEN" \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  -d 'id=t3_abc123&dir=1' \
  https://oauth.reddit.com/api/vote
```

### I. Subscribe/Unsubscribe to Subreddit
```
# Subscribe (action=sub), Unsubscribe (action=unsub)
curl -X POST -H "Authorization: bearer $TOKEN" \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  -d 'sr_name=python&action=sub' \
  https://oauth.reddit.com/api/subscribe
```

### J. Get Subreddit Info
```
curl -H "Authorization: bearer $TOKEN" \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  https://oauth.reddit.com/r/python/about
```

### K. Get User Subscriptions
```
curl -H "Authorization: bearer $TOKEN" \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  https://oauth.reddit.com/subreddits/mine/subscriber?limit=100
```

### L. Send Private Message
```
curl -X POST -H "Authorization: bearer $TOKEN" \
  -H "User-Agent: cli-agent:v1.0 (by /u/YOUR_USERNAME)" \
  -d 'to=/u/TARGET_USERNAME&subject=Hello&message=Body%20text&api_type=json' \
  https://oauth.reddit.com/api/compose
```

## 3. Rate Limits

### Official Rate Limits (OAuth2)
- **OAuth2 authenticated**: 100 requests per minute (per OAuth client_id)
- **Unauthenticated**: 60 requests per minute (per IP)

### Response Headers to Monitor
- X-Ratelimit-Used: Approximate number of requests used in this period
- X-Ratelimit-Remaining: Approximate number of requests left
- X-Ratelimit-Reset: Approximate seconds to end of period

### PRAW Handling
- Automatically respects rate limit headers
- Sleeps between requests as needed
- Additional unknown rate limits for write operations (commenting, posting, etc.)
- ratelimit_seconds config (default: 5s) controls max auto-wait

### User-Agent Requirement
- MUST be unique and descriptive
- Format: platform:app_id:version (by /u/reddit_username)
- Generic User-Agents are severely rate-limited

### Free Tier at $0
- Script-type apps are FREE
- No paid tier needed for personal script use
- 100 req/min is generous for single-user CLI
- Reddit 2023 API changes targeted commercial/high-volume usage, not personal scripts

## 4. Existing CLI Tools

### rtv (Reddit Terminal Viewer) - ARCHIVED
- GitHub: https://github.com/michael-lazar/rtv
- Stars: 4.6k
- Status: ARCHIVED (Feb 20, 2023)
- Was the gold standard for terminal Reddit browsing
- No longer maintained

### tuir - ALSO DEFUNCT
- Fork/continuation of rtv
- No longer actively maintained

### ttrv (Tilde Terminal Reddit Viewer)
- GitHub: https://github.com/llorllale/ttrv
- Fork of rtv, very low stars
- Not actively maintained

### PRAW (Python Reddit API Wrapper) - RECOMMENDED
- GitHub: https://github.com/praw-dev/praw
- Stars: 4.1k
- Status: ACTIVELY MAINTAINED (latest commit 2 months ago, v7.7.1)
- pip install praw
- BEST option for building a CLI skill
- Handles OAuth2, rate limiting, all endpoints automatically
- Has script-type password flow built in

### RECOMMENDATION
Use PRAW. No actively maintained TUI (terminal UI) Reddit browser exists. Build CLI skill using PRAW as backend.

## 5. Quick Start PRAW Setup

```python
# pip install praw
import praw

reddit = praw.Reddit(
    client_id="YOUR_CLIENT_ID",
    client_secret="YOUR_CLIENT_SECRET",
    password="YOUR_PASSWORD",
    user_agent="linux:cli-social-agent:v1.0 (by /u/YOUR_USERNAME)",
    username="YOUR_USERNAME",
)

# Verify
print(reddit.user.me())

# Read subreddit
for post in reddit.subreddit("python").hot(limit=10):
    print(f"{post.title} ({post.score})")

# Submit post
reddit.subreddit("test").submit(title="Test", selftext="Hello from CLI")

# Comment
submission = reddit.submission(id="POST_ID")
submission.reply("My comment text")

# Search
for post in reddit.subreddit("all").search("python asyncio", sort="new", time_filter="week"):
    print(post.title)

# Inbox
for msg in reddit.inbox.unread(limit=25):
    print(f"From: {msg.author} - {msg.body[:80]}")

# Upvote
submission.upvote()

# Send PM
reddit.redditor("USERNAME").message("Subject", "Body text")
```

### praw.ini file (recommended)
Place at ~/.config/praw.ini or ~/.praw.ini:
```ini
[DEFAULT]
client_id=YOUR_CLIENT_ID
client_secret=YOUR_CLIENT_SECRET
password=YOUR_PASSWORD
username=YOUR_USERNAME
user_agent=linux:cli-social-agent:v1.0 (by /u/YOUR_USERNAME)
```

Then: reddit = praw.Reddit()

## Summary

| Aspect | Details |
|--------|---------|
| Auth Flow | Password Grant (script app) |
| Token URL | POST https://www.reddit.com/api/v1/access_token |
| API Base | https://oauth.reddit.com |
| Token Lifetime | 3600 seconds (1 hour) |
| Rate Limit | 100 req/min (OAuth2) |
| Rate Limit Headers | X-Ratelimit-Used, X-Ratelimit-Remaining, X-Ratelimit-Reset |
| Cost | FREE for personal script apps |
| Best Library | PRAW (pip install praw) |
| App Registration | https://www.reddit.com/prefs/apps |
| User-Agent Format | platform:app_id:version (by /u/username) |
