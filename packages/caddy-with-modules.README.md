# Caddy with Custom Modules

Custom build of Caddy web server v2.8.0 with 5 additional modules for security, rate limiting, caching, compression, and IP filtering.

## Modules Included

### 1. caddy-security
Advanced security features including:
- JWT authentication
- Basic authentication
- IP whitelisting/blacklisting
- URL-based access control
- OpenID Connect support

**Repository:** https://github.com/greenpau/caddy-security

**Example Configuration:**
```caddy
example.com {
    route /admin* {
        basicauth {
            bob $2a$14$... # bcrypt hash
        }
        respond "Admin Area" 200
    }
}
```

### 2. caddy-rate-limit
Rate limiting with multiple strategies:
- Sliding window log
- Token bucket
- Leaky bucket
- Configurable limits per IP, per route, or globally

**Repository:** https://github.com/mholt/caddy-ratelimit

**Example Configuration:**
```caddy
example.com {
    rate_limit {
        zone dynamic_limits {
            key { remote_ip }
            events 100
            window 1m
        }
    }
}
```

### 3. caddy-cache
Response caching with:
- Configurable TTL
- Multiple cache backends (memory, file, Redis)
- Cache status headers
- Cache key customization

**Repository:** https://github.com/caddyserver/cache-handler

**Example Configuration:**
```caddy
example.com {
    cache {
        ttl 3600
        key_scheme { hash { hide query } }
    }
}
```

### 4. caddy-zip
On-the-fly compression:
- Gzip compression
- Brotli compression
- Zstandard compression (zstd)
- Configurable compression levels

**Repository:** https://github.com/caddyserver/caddy-zip

**Example Configuration:**
```caddy
example.com {
    zip {
        level 6
        formats gzip brotli zstd
    }
}
```

### 5. caddy-ipfilter
IP filtering with:
- Allow/deny lists
- CIDR notation support
- Country-based filtering
- IP range matching

**Repository:** https://github.com/mholt/caddy-ipfilter

**Example Configuration:**
```caddy
example.com {
    ipfilter {
        rule block {
            ip 192.168.1.0/24
        }
    }
}
```

## Building

### From Flake
```bash
nix-build .#packages.x86_64-linux.caddy-with-modules
```

### Get Vendor Hash
First build will fail with:
```
error: hash mismatch in fixed-output derivation
```

Copy the correct hash from error message and update `vendorHash` in `default.nix`.

### Verify Build
```bash
./result/bin/caddy-with-modules version
```

Expected output:
```
v2.8.0
```

## Usage

### Systemd Service
Replace standard `caddy` with `caddy-with-modules` in your NixOS configuration:

```nix
services.caddy = {
  enable = true;
  package = pkgs.caddy-with-modules; # Use custom build
};
```

### Manual Testing
```bash
# Start Caddy with custom Caddyfile
./result/bin/caddy-with-modules run --config /path/to/Caddyfile

# Validate configuration
./result/bin/caddy-with-modules validate --config /path/to/Caddyfile

# Check version and loaded modules
./result/bin/caddy-with-modules version --verbose
```

## Configuration Examples

### Complete Example with All Modules
```caddy
example.com {
    # Security: Basic authentication
    basicauth {
        admin $2a$14$... # bcrypt hash
    }

    # Rate limiting: 100 requests per minute per IP
    rate_limit {
        zone api_limits {
            key { remote_ip }
            events 100
            window 1m
        }
    }

    # Cache: Cache responses for 1 hour
    cache {
        ttl 3600
    }

    # Compression: Enable gzip, brotli, and zstd
    zip {
        level 6
        formats gzip brotli zstd
    }

    # IP filtering: Block specific ranges
    ipfilter {
        rule block {
            ip 10.0.0.0/8
        }
    }

    # Reverse proxy to backend
    reverse_proxy localhost:8080
}
```

### API Gateway Configuration
```caddy
api.example.com {
    # Rate limit API endpoints
    rate_limit {
        zone api {
            key { remote_ip }
            events 1000
            window 1h
        }
    }

    # Cache GET requests
    cache {
        ttl 300
        key_scheme {
          hash { hide query }
        }
    }

    # Compress responses
    zip {
        level 9
        formats brotli zstd
    }

    reverse_proxy localhost:3000
}
```

## Module-Specific Configuration

### caddy-security JWT Authentication
```caddy
secure.example.com {
    route /api/* {
        jwt {
            auth_url https://auth.example.com/login
        }
        reverse_proxy localhost:8080
    }
}
```

### caddy-rate-limit Strategies
```caddy
example.com {
    rate_limit {
        # Sliding window (default)
        zone sliding_window {
            key { remote_ip }
            events 100
            window 1m
        }

        # Token bucket
        zone token_bucket {
            key { remote_ip }
            events 10
            window 10s
        }
    }
}
```

### caddy-cache Backends
```caddy
example.com {
    cache {
        # Memory cache (default)
        ttl 3600

        # File cache
        # backend {
        #     name file
        #     path /var/cache/caddy
        # }

        # Redis cache
        # backend {
        #     name redis
        #     addr localhost:6379
        # }
    }
}
```

### caddy-zip Compression Levels
```caddy
example.com {
    zip {
        # Gzip: 1-9 (default 6)
        # Brotli: 0-11 (default 6)
        # Zstd: 1-22 (default 6)
        level 6
        formats gzip brotli zstd
    }
}
```

### caddy-ipfilter Advanced
```caddy
example.com {
    ipfilter {
        # Block specific IPs
        rule block {
            ip 192.168.1.100
            ip 10.0.0.0/8
        }

        # Allow only specific IPs
        rule allow {
            ip 203.0.113.0/24
            country US CA
        }

        # Block by country
        rule block_country {
            country CN RU
        }
    }
}
```

## Troubleshooting

### Build Failures
**Issue:** "hash mismatch in fixed-output derivation"

**Solution:** Update `vendorHash` in `default.nix` with the correct hash from the error message.

**Issue:** "module not found" errors

**Solution:** Ensure build tags are correctly specified in `tags` list in `default.nix`.

### Runtime Issues
**Issue:** Module directives not recognized

**Solution:** Verify binary name is `caddy-with-modules`, not `caddy`. Check version with `--verbose` flag.

**Issue:** Rate limiting not working

**Solution:** Ensure `rate_limit` directive is placed before `reverse_proxy`. Check zone configuration.

**Issue:** Cache not storing responses

**Solution:** Verify cache backend is configured. Check file permissions for file-based cache.

## Performance Considerations

### Rate Limiting
- Sliding window: Most accurate, higher memory usage
- Token bucket: Lower memory usage, may allow bursts
- Leaky bucket: Steady rate, predictable behavior

### Caching
- Memory cache: Fastest, limited by RAM
- File cache: Persistent, slower than memory
- Redis cache: Distributed, best for multi-server setups

### Compression
- Gzip: Fast compression, good ratio
- Brotli: Better ratio, slower compression
- Zstd: Best ratio, fastest decompression

## Security Best Practices

1. **Use rate limiting** on all public endpoints to prevent abuse
2. **Enable authentication** for sensitive routes using caddy-security
3. **Configure IP filtering** to block known malicious ranges
4. **Set appropriate cache TTLs** to prevent stale data
5. **Use HTTPS** with automatic certificates (Caddy default)
6. **Monitor logs** for rate limit violations and blocked IPs

## Monitoring

Caddy metrics are exposed in JSON format:
```bash
curl http://localhost:2019/metrics
```

Metrics include:
- Request counts
- Response times
- Rate limit violations
- Cache hit/miss ratios
- Compression ratios

## Resources

- **Caddy Documentation:** https://caddyserver.com/docs/
- **Caddyfile Concepts:** https://caddyserver.com/docs/caddyfile/concepts
- **Module Documentation:** See individual module repos above
- **Community Forum:** https://caddy.community/

## Version Information

- **Caddy:** v2.8.0
- **Go:** 1.22
- **Build:** Reproducible via `buildGoModule`
- **License:** Apache 2.0

## Contributing

To add or modify modules:
1. Update `tags` list in `pkgs/caddy-with-modules/default.nix`
2. Update `vendorHash` (will fail on first build)
3. Rebuild and test: `nix-build .#packages.x86_64-linux.caddy-with-modules`
4. Update this README with new module documentation

## License

This package follows the same license as Caddy: Apache 2.0
