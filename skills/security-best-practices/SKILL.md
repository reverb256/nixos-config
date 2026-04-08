---
name: security-best-practices
description: Comprehensive security for web applications and REST APIs based on OWASP Top 10. Use when securing APIs, preventing common vulnerabilities, auditing code, or implementing security policies. Covers HTTPS, CORS, XSS, SQL Injection, CSRF, rate limiting, authentication, authorization, data protection, cryptographic failures, security headers, secrets management, and complete security audit guidelines.
version: 2.0.0
---

# Security Best Practices & OWASP Audit

Complete security guidance for web applications and REST APIs, combining best practices implementation with comprehensive audit guidelines based on OWASP Top 10.

## When to Use This Skill

- **New Project**: Implement security from the start
- **Security Audit**: Audit codebase for vulnerabilities
- **API Security**: Harden publicly accessible APIs
- **Production Review**: Check before deploying to production
- **Compliance**: Meet GDPR, PCI-DSS, SOC2 requirements
- **Vulnerability Scan**: Find and fix security issues
- **Authentication Review**: Audit auth/authz implementations
- **Data Protection**: Review PII handling and encryption

## Quick Start: Security Checklist

### Critical (Fix Immediately)
- [ ] HTTPS enforced in production
- [ ] All user input validated
- [ ] Parameterized queries (SQL injection prevention)
- [ ] Authentication on all protected routes
- [ ] Authorization checks (no IDOR vulnerabilities)
- [ ] Secrets in environment variables, not hardcoded
- [ ] Passwords hashed with bcrypt/argon2

### High Priority
- [ ] Security headers set (CSP, HSTS, X-Frame-Options, etc.)
- [ ] CSRF protection enabled
- [ ] Rate limiting implemented
- [ ] CORS properly configured
- [ ] Session security (Secure, HttpOnly, SameSite cookies)
- [ ] Strong password requirements (12+ chars, complexity)

### Medium Priority
- [ ] Logging and monitoring for security events
- [ ] Dependency audits (npm audit, regular updates)
- [ ] Error handling doesn't leak sensitive info
- [ ] File upload validation
- [ ] Redirect URL validation

---

## Part 1: Security Best Practices Implementation

### 1. Enforce HTTPS and Security Headers

```typescript
import express from 'express';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';

const app = express();

// Helmet: automatically set security headers
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'", "'unsafe-inline'", "https://trusted-cdn.com"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      imgSrc: ["'self'", "data:", "https:"],
      connectSrc: ["'self'", "https://api.example.com"],
      fontSrc: ["'self'", "https:", "data:"],
      objectSrc: ["'none'"],
      mediaSrc: ["'self'"],
      frameSrc: ["'none'"],
    },
  },
  hsts: {
    maxAge: 31536000,
    includeSubDomains: true,
    preload: true
  },
  frameguard: { action: 'deny' },
  noSniff: true,
  xssFilter: true
}));

// Enforce HTTPS in production
app.use((req, res, next) => {
  if (process.env.NODE_ENV === 'production' && !req.secure) {
    return res.redirect(301, `https://${req.headers.host}${req.url}`);
  }
  next();
});

// Rate limiting (DDoS prevention)
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // max 100 requests per IP
  message: 'Too many requests from this IP, please try again later.',
  standardHeaders: true,
  legacyHeaders: false,
});

app.use('/api/', limiter);

// Stricter for auth endpoints
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  skipSuccessfulRequests: true
});

app.use('/api/auth/login', authLimiter);
```

### 2. Input Validation (SQL Injection, XSS Prevention)

```typescript
import Joi from 'joi';
import DOMPurify from 'isomorphic-dompurify';

const userSchema = Joi.object({
  email: Joi.string().email().required(),
  password: Joi  // use .min(12) + complexity pattern
    .string()
    /^(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]/
  ).required(),
  name: Joi.string().min(2).max(50).required()
});

app.post('/api/users', async (req, res) => {
  // 1. Validate input
  const { error, value } = userSchema.validate(req.body);
  if (error) {
    return res.status(400).json({ error: error.details[0].message });
  }

  // 2. Prevent SQL Injection: Parameterized Queries
  // ❌ Bad
  // db.query(\`SELECT * FROM users WHERE email = '\${email}'\`);

  // ✅ Good
  const user = await db.query('SELECT * FROM users WHERE email = ?', [value.email]);

  // 3. Prevent XSS: Output Encoding
  const sanitized = DOMPurify.sanitize(userInput);

  res.json({ user: sanitized });
});
```

### 3. CSRF Protection

```typescript
import csrf from 'csurf';
import cookieParser from 'cookie-parser';

app.use(cookieParser({
  secure: process.env.NODE_ENV === 'production',
  httpOnly: true,
  sameSite: 'strict'
}));

const csrfProtection = csrf({ cookie: true });

// Provide CSRF token
app.get('/api/csrf-token', csrfProtection, (req, res) => {
  res.json({ csrfToken: req.csrfToken() });
});

// Validate CSRF on state-changing requests
app.post('/api/*', csrfProtection, (req, res, next) => {
  next();
});
```

### 4. Secrets Management

```bash
# .env (NEVER commit to git)
DATABASE_URL=postgresql://localhost:5432/mydb
JWT_ACCESS_SECRET=your-super-secret-access-token-key-min-32-chars
JWT_REFRESH_SECRET=your-super-secret-refresh-token-key-min-32-chars
STRIPE_SECRET_KEY=sk_live_xxx
```

```yaml
# Kubernetes Secrets
apiVersion: v1
kind: Secret
metadata:
  name: myapp-secrets
type: Opaque
stringData:
  database-url: postgresql://postgres:5432/mydb
  jwt-secret: your-jwt-secret
```

### 5. Secure Authentication

```typescript
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';

// Password hashing (bcrypt with salt rounds 12)
const hashedPassword = await bcrypt.hash(password, 12);
const isValid = await bcrypt.compare(password, hashedPassword);

// JWT with short-lived access token and long-lived refresh token
const accessToken = jwt.sign({ userId }, process.env.JWT_ACCESS_SECRET, {
  expiresIn: '15m'
});

const refreshToken = jwt.sign({ userId }, process.env.JWT_REFRESH_SECRET, {
  expiresIn: '7d'
});
```

---

## Part 2: OWASP Security Audit Guidelines

### Audit Workflow

1. **Identify application type** - Web app, REST API, SPA, SSR
2. **Scan by priority** - CRITICAL → HIGH → MEDIUM → LOW
3. **Review code** - Check each category systematically
4. **Report findings** - Document severity, location, impact, fix
5. **Verify remediation** - Re-scan after fixes

### OWASP Top 10 Rules (2023)

#### A01: Broken Access Control (CRITICAL)

**Check for:**
- Missing authorization checks
- IDOR (Insecure Direct Object References)
- Privilege escalation
- CORS misconfiguration

**Bad Example:**
```typescript
// No ownership check - anyone can access any user's data
async function getUser(req: Request): Promise<Response> {
  const userId = req.params.id;
  const user = await db.user.findUnique({ where: { id: userId } });
  return new Response(JSON.stringify(user));
}
```

**Good Example:**
```typescript
// Verify user owns the resource or is admin
async function getUser(req: Request): Promise<Response> {
  const session = await getSession(req);
  const userId = req.params.id;

  if (session.userId !== userId && !session.isAdmin) {
    return new Response("Forbidden", { status: 403 });
  }

  const user = await db.user.findUnique({ where: { id: userId } });
  return new Response(JSON.stringify(user));
}
```

#### A02: Cryptographic Failures (CRITICAL)

**Check for:**
- Weak encryption algorithms (MD5, SHA1)
- Plaintext password storage
- Insecure random number generation
- Hardcoded encryption keys

**Bad Example:**
```typescript
// MD5 is broken for passwords
const hash = crypto.createHash('md5').update(password).digest('hex');
```

**Good Example:**
```typescript
// Use bcrypt with sufficient work factor
const hash = await bcrypt.hash(password, 12);
```

#### A03: Injection (CRITICAL)

**Check for:**
- SQL injection
- NoSQL injection
- Command injection
- XSS (Cross-Site Scripting)
- LDAP injection
- Template injection

**Bad Example:**
```typescript
// SQL injection vulnerability
const query = \`SELECT * FROM users WHERE email = '\${email}'\`;
```

**Good Example:**
```typescript
// Parameterized query
const user = await db.user.findUnique({ where: { email } });
```

#### A04: Insecure Design (HIGH)

**Check for:**
- Security by obscurity
- Missing threat modeling
- Insecure defaults
- Missing security requirements

#### A05: Security Misconfiguration (HIGH)

**Check for:**
- Default credentials
- Debug mode enabled
- Verbose error messages
- Missing security headers
- Unnecessary services enabled

**Bad Example:**
```typescript
// Exposing stack traces
catch (error) {
  return new Response(error.stack, { status: 500 });
}
```

**Good Example:**
```typescript
// Generic error message
catch (error) {
  console.error(error); // Log server-side only
  return new Response("Internal server error", { status: 500 });
}
```

#### A06: Vulnerable and Outdated Components (MEDIUM-HIGH)

**Check for:**
- Outdated dependencies
- Known CVEs
- Unsupported frameworks

```bash
# Regular audits
npm audit
npm audit fix
```

#### A07: Identification and Authentication Failures (HIGH)

**Check for:**
- Weak password policies
- Missing account lockout
- Session fixation
- Credential stuffing vulnerabilities

#### A08: Software and Data Integrity Failures (HIGH)

**Check for:**
- Unsigned data/packages
- Insecure deserialization
- CI/CD pipeline vulnerabilities

#### A09: Security Logging and Monitoring Failures (MEDIUM)

**Check for:**
- Insufficient logging
- Sensitive data in logs
- Missing security event tracking
- No alerting on suspicious activity

**Good Example:**
```typescript
// Log security events
logger.info('login_attempt', {
  email,
  ip: req.ip,
  success: true,
  timestamp: new Date().toISOString()
});
```

#### A10: Server-Side Request Forgery (SSRF) (MEDIUM-HIGH)

**Check for:**
- Unvalidated URLs
- Internal network access
- Cloud metadata access

**Bad Example:**
```typescript
// Fetching user-provided URL without validation
const url = await req.json().then(d => d.url);
const response = await fetch(url);
```

**Good Example:**
```typescript
// Validate against allowlist
const ALLOWED_DOMAINS = ['api.example.com', 'cdn.example.com'];
const url = new URL(await req.json().then(d => d.url));

if (!ALLOWED_DOMAINS.includes(url.hostname)) {
  return new Response("Invalid URL", { status: 400 });
}

const response = await fetch(url);
```

### Additional Critical Rules

#### File Upload Security

**Check for:**
- No file type validation
- No size limits
- Executable file uploads
- Path traversal

**Good Example:**
```typescript
const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
const ALLOWED_EXTS = ['.jpg', '.jpeg', '.png', '.webp'];
const MAX_SIZE = 5 * 1024 * 1024; // 5MB

if (file.size > MAX_SIZE) {
  return new Response("File too large", { status: 400 });
}

if (!ALLOWED_TYPES.includes(file.type)) {
  return new Response("Invalid file type", { status: 400 });
}
```

#### CSRF Protection

**Check for:**
- Missing CSRF tokens
- Missing SameSite cookies
- Missing referrer checking

#### Security Headers

**Required Headers:**
- Content-Security-Policy
- X-Frame-Options: DENY
- X-Content-Type-Options: nosniff
- Strict-Transport-Security
- X-XSS-Protection

```typescript
headers.set('Content-Security-Policy', "default-src 'self'");
headers.set('X-Frame-Options', 'DENY');
headers.set('X-Content-Type-Options', 'nosniff');
headers.set('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
```

---

## Severity Classification

### CRITICAL (Fix Immediately)

- SQL/XSS/Command injection vulnerabilities
- Missing authentication on sensitive endpoints
- Hardcoded secrets/credentials
- Plaintext password storage
- IDOR vulnerabilities
- Broken access control allowing privilege escalation

### HIGH (Fix Within 1 Week)

- Missing CSRF protection
- Weak password requirements
- Missing security headers
- Overly permissive CORS
- Insecure session management
- SSRF vulnerabilities

### MEDIUM (Fix Within 1 Month)

- Missing rate limiting
- Incomplete logging
- Verbose error messages in production
- Outdated dependencies (no known critical CVEs)
- Missing input validation on non-critical fields

### LOW (Improve When Possible)

- Optional security headers missing
- Suboptimal crypto parameters
- Minor configuration improvements

---

## Required Rules (MUST)

1. **HTTPS Only**: HTTPS required in production with HSTS
2. **Separate Secrets**: Use environment variables or secret stores
3. **Input Validation**: Validate all user input
4. **Parameterized Queries**: Prevent SQL injection
5. **Rate Limiting**: DDoS prevention
6. **Security Headers**: CSP, HSTS, X-Frame-Options, etc.
7. **Strong Authentication**: MFA, strong password requirements
8. **Authorization**: Check permissions on all protected routes
9. **Secure Cookies**: Secure, HttpOnly, SameSite flags
10. **Error Handling**: Don't leak sensitive info

---

## Prohibited Items (MUST NOT)

1. **No eval()**: Code injection risk
2. **No direct innerHTML**: XSS risk (use DOMPurify if needed)
3. **No committing secrets**: Never commit .env files or hardcoded secrets
4. **No MD5/SHA1 for passwords**: Use bcrypt/argon2
5. **No query string concatenation**: SQL injection risk
6. **No debug mode in production**: Disable debug logging

---

## Security Testing

```bash
# Dependency audit
npm audit
npm audit fix

# Run security tests
npm run test:security

# Scan for secrets
git-secrets scan

# Check for common vulnerabilities
npm install -g snyk
snyk test
```

---

## References

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [OWASP ASVS](https://owasp.org/www-project-application-security-verification-standard/)
- [Helmet.js](https://helmetjs.github.io/)
- [CSP Evaluator](https://csp-evaluator.withgoogle.com/)
- [Security Headers](https://securityheaders.com/)

---

## Related Skills

- `k8s-security` - Kubernetes security policies
- `monitoring-observability` - Security monitoring
- `devops-automation` - Security in CI/CD pipelines
- `owasp-security-check` - (DEPRECATED - merged into this skill)
