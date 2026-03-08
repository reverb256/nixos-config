# Docker Skill Consolidation Specification

**Target Name**: `docker:complete`
**Sources to Merge**:
- `docker-best-practices`
- `docker-patterns`
- `docker-compose-orchestration`

**Created**: 2026-03-07
**Status**: Specification ready for implementation

---

## Skill Manifest

```yaml
name: docker:complete
description: Complete Docker and Docker Compose expertise including best practices, patterns, security, performance, and local orchestration.

triggers:
  - User asks about Docker
  - User needs Dockerfile help
  - User wants docker-compose setup
  - "Optimize this Dockerfile"
  - "Docker compose for..."
  - "Container security..."
```

---

## Consolidated Content Structure

### 1. Docker Best Practices

#### 1.1 Dockerfile Patterns

**Multi-stage Build** (smaller images, better security):
```dockerfile
# Build stage
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
RUN npm run build

# Production stage
FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
EXPOSE 3000
CMD ["node", "dist/index.js"]
```

**Layer Caching** (faster rebuilds):
```dockerfile
# Bad: Changes invalidate all subsequent layers
COPY . .
RUN npm install

# Good: Dependencies cached unless package.json changes
COPY package*.json ./
RUN npm install
COPY . .
```

**Non-root User** (security):
```dockerfile
RUN addgroup -g 1001 -S appuser && \
    adduser -S -u 1001 -G appuser appuser
USER appuser
```

#### 1.2 Security Best Practices

| Practice | Why | How |
|----------|-----|-----|
| **Use specific tags** | Predictable builds | `FROM node:20-alpine` not `FROM node:latest` |
| **Scan images** | Find vulnerabilities | `docker scan myimage:tag` |
| **Minimize layers** | Smaller images | Combine RUN commands |
| **Don't leak secrets** | Prevent exposure | Use build args/secrets, not ENV |
| **Run as non-root** | Least privilege | Add USER directive |
| **Scan in pipeline** | Shift left | Integrate trivy/grype |

**Secret Management**:
```dockerfile
# Bad - secrets in image
ENV API_KEY=secret123

# Good - use build secrets
RUN --mount=type=secret,id=api_key \
    API_KEY=$(cat /run/secrets/api_key) && \
    curl -H "Authorization: Bearer $API_KEY" ...

# Or use Docker Compose secrets
services:
  app:
    secrets:
      - api_key
secrets:
  api_key:
    file: ./secrets/api_key.txt
```

#### 1.3 Performance Optimization

**Image Size Reduction**:
```dockerfile
# Start with alpine/base images
FROM python:3.12-slim  # better than full, bigger than alpine

# Use .dockerignore
cat > .dockerignore <<EOF
.git
node_modules
*.log
.env
tests/
README.md
EOF

# Clean up in same layer
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git curl && \
    rm -rf /var/lib/apt/lists/*
```

**BuildKit Features**:
```dockerfile
# Use cache mounts
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

# Use bind mounts
RUN --mount=type=bind,target=. \
    go build -o app .

# Use SSH for private repos
RUN --mount=type=ssh \
    git clone git@github.com:private/repo.git
```

### 2. Docker Patterns

#### 2.1 Common Patterns

**Base Image Pattern**:
```dockerfile
# images/base/Dockerfile
FROM node:20-alpine
RUN apk add --no-cache dumb-init
WORKDIR /app
COPY --ch=node:node entrypoint.sh /
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/entrypoint.sh"]
```

**Development Pattern**:
```dockerfile
# images/dev/Dockerfile
FROM myapp:base
RUN npm install -g nodemon
ENV NODE_ENV=development
CMD ["nodemon", "src/index.js"]
```

**One-off Container Pattern**:
```bash
# Run migrations
docker run --rm \
  --network mynetwork \
  myapp:latest \
  npm run migrate

# Database backup
docker run --rm \
  -v db-backup:/backup \
  --volumes-from db-container \
  alpine tar czf /backup/db.tar.gz /var/lib/mysql
```

#### 2.2 Volume Patterns

**Named Volume**:
```yaml
volumes:
  data:
  # Persist data, managed by Docker
```

**Bind Mount**:
```yaml
volumes:
  - ./src:/app/src
  # Local development, live reload
```

**Tmpfs**:
```yaml
volumes:
  - /tmp
  # Fast, non-persistent (caches, temp files)
```

### 3. Docker Compose Orchestration

#### 3.1 Complete Compose File Structure

```yaml
version: "3.9"

services:
  # Application
  app:
    build:
      context: .
      dockerfile: Dockerfile
      target: production
    image: myapp:${TAG:-latest}
    container_name: myapp
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    environment:
      NODE_ENV: production
      DATABASE_URL: postgresql://user:pass@db:5432/mydb
      REDIS_URL: redis://redis:6379
    env_file:
      - .env.production
    ports:
      - "3000:3000"
    volumes:
      - ./logs:/app/logs
      - app-uploads:/app/uploads
    networks:
      - frontend
      - backend
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 512M
        reservations:
          cpus: "0.25"
          memory: 256M
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # Database
  db:
    image: postgres:15-alpine
    container_name: myapp-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
      POSTGRES_DB: mydb
    volumes:
      - db-data:/var/lib/postgresql/data
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql
    networks:
      - backend
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U user"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Cache
  redis:
    image: redis:7-alpine
    container_name: myapp-redis
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - redis-data:/data
    networks:
      - backend
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s

  # Reverse Proxy
  nginx:
    image: nginx:alpine
    container_name: myapp-nginx
    restart: unless-stopped
    depends_on:
      - app
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
      - nginx-cache:/var/cache/nginx
    networks:
      - frontend

  # Worker
  worker:
    build:
      context: .
      target: production
    image: myapp:${TAG:-latest}
    restart: unless-stopped
    command: npm run worker
    depends_on:
      - db
      - redis
    environment:
      NODE_ENV: production
      DATABASE_URL: postgresql://user:pass@db:5432/mydb
      REDIS_URL: redis://redis:6379
    networks:
      - backend
    deploy:
      replicas: 2

volumes:
  db-data:
    driver: local
  redis-data:
    driver: local
  app-uploads:
    driver: local
  nginx-cache:
    driver: local

networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
    internal: true
```

#### 3.2 Compose Patterns

**Development Override**:
```yaml
# docker-compose.dev.yml
services:
  app:
    volumes:
      - .:/app
      - /app/node_modules
    environment:
      - NODE_ENV=development
    command: npm run dev
```

```bash
# Use with base file
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up
```

**Multi-Environment**:
```bash
# docker-compose.{env}.yml
docker-compose -f docker-compose.yml -f docker-compose.staging.yml up
docker-compose -f docker-compose.yml -f docker-compose.production.yml up
```

**Health Check Dependencies**:
```yaml
services:
  app:
    depends_on:
      db:
        condition: service_healthy  # Wait for health check
      redis:
        condition: service_started  # Just wait for start
```

---

## When to Use This Skill

Trigger this skill when:

1. **Creating Dockerfiles**
   - "Write a Dockerfile for..."
   - "Optimize this Dockerfile"
   - "Multi-stage build for..."

2. **Docker Compose Setup**
   - "Docker compose for my stack"
   - "Connect containers..."
   - "Development environment..."

3. **Security/Performance**
   - "Secure this container"
   - "Reduce image size"
   - "Scan for vulnerabilities"

4. **Troubleshooting**
   - "Container won't start"
   - "Networking issues"
   - "Volume problems"

---

## Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| Image too large | Unnecessary layers/files | Multi-stage build, .dockerignore |
| Slow rebuilds | Poor cache utilization | Order Dockerfile by change frequency |
| Permission errors | Running as root | Add non-root user |
| Orphaned containers | Missing `--rm` flag | Use `--rm` for one-off containers |
| Networking fails | Wrong network mode | Explicitly define networks |
| Data loss | No volumes | Add volume mounts |

---

## Quality Checklist

Before committing Docker changes:

- [ ] Specific image tag used (no `latest`)
- [ ] Multi-stage build for production
- [ ] Non-root user defined
- [ ] `.dockerignore` present and optimized
- [ ] Secrets not in image/ENV
- [ ] Health checks defined
- [ ] Resource limits set
- [ ] Logs configured (max-size, max-file)
- [ ] Restart policy appropriate
- [ ] Volume data persisted

---

## Commands Reference

```bash
# Building
docker build -t myapp:1.0 .
docker build --build-arg ARG=value -t myapp .
docker-compose build

# Running
docker run -d --name mycontainer -p 8080:80 myapp
docker-compose up -d
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up

# Inspecting
docker logs mycontainer
docker logs -f mycontainer  # follow
docker exec -it mycontainer sh
docker inspect mycontainer

# Cleanup
docker system prune -a  # Remove all unused data
docker volume prune      # Remove unused volumes
docker image prune -a    # Remove unused images

# Networking
docker network create mynetwork
docker network inspect mynetwork
docker network connect mynetwork mycontainer
```

---

## Integration Notes

When implementing this consolidated skill:

1. **Combine overlapping content**: security and patterns both discuss layering
2. **Preserve all compose examples** from docker-compose-orchestration
3. **Keep security scanning sections** from docker-best-practices
4. **Maintain pattern catalog** from docker-patterns
5. **Cross-reference**: security applies to all patterns

---

## References

- Dockerfile Best Practices: https://docs.docker.com/develop/develop-images/dockerfile_best-practices/
- Docker Compose Reference: https://docs.docker.com/compose/compose-file/
- Docker Security: https://docs.docker.com/engine/security/
- BuildKit: https://docs.docker.com/build/buildkit/
