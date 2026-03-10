# API Security Headers

## Implemented Headers

| Header | Value | Purpose |
|--------|-------|---------|
| X-Frame-Options | DENY | Prevents clickjacking |
| X-Content-Type-Options | nosniff | Prevents MIME sniffing |
| X-XSS-Protection | 1; mode=block | XSS filtering |
| Referrer-Policy | no-referrer | Privacy protection |
| Content-Security-Policy | default-src 'self' | XSS prevention |

## HSTS Status

Currently commented out. Enable after:
1. Confirming HTTPS works correctly
2. No mixed content issues
3. Testing with all clients

## Testing

```bash
# Verify headers are set
curl -I https://your-domain.com | grep -E "X-Frame-Options|X-Content-Type-Options|Content-Security-Policy"
```

## References

- https://owasp.org/www-project-secure-headers/
- https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers
