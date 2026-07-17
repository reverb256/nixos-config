---
name: container-native
description: Unified container management for Docker and Podman on NixOS. Use when user asks to: run containers, build images, manage pods, docker-compose, podman pods, or container orchestration.
---

# Container-Native

Unified container management supporting both Docker and Podman on NixOS, with podman-compose for Docker Compose compatibility.

## When to Use This Skill

Use this skill when the user:
- Asks to "run container", "build image", "docker run"
- Wants to use "docker-compose", "podman-compose"
- Needs to manage pods, containers, volumes, networks
- Asks about containerization, containers, pods
- Wants to deploy containerized services on NixOS

## Container Runtime Status

| Host | Docker | Podman | Notes |
|------|--------|--------|-------|
| **zephyr** | ✅ | ✅ | Primary container host |
| **nexus** | ❌ | ✅ | Podman only (gaming) |
| **forge** | ❌ | ✅ | Podman only (mining/AI) |
| **sentry** | ❌ | ✅ | Podman only (AMD GPU) |

## Quick Start

### Check Container Runtime
```bash
# Check if Docker is available
docker --version
docker ps

# Check if Podman is available
podman --version
podman ps

# Check if podman-compose is available
podman-compose --version
```

### Basic Container Operations
```bash
# Run a container (works with both)
docker run -d nginx:latest
podman run -d nginx:latest

# List containers
docker ps
podman ps

# View logs
docker logs <container>
podman logs <container>

# Stop container
docker stop <container>
podman stop <container>
```

## Docker vs Podman Commands

| Operation | Docker | Podman |
|-----------|--------|--------|
| Run container | `docker run` | `podman run` |
| Build image | `docker build` | `podman build` |
| Compose | `docker-compose` | `podman-compose` |
| Prune | `docker system prune` | `podman system prune` |
| Networks | `docker network` | `podman network` |
| Volumes | `docker volume` | `podman volume` |

Most commands are drop-in compatible!

## Docker Compose with Podman

Use `podman-compose` for Docker Compose compatibility:

```bash
# Works just like docker-compose!
podman-compose up -d
podman-compose down
podman-compose logs -f
podman-compose ps
```

### Example docker-compose.yml
```yaml
version: "3.8"
services:
  web:
    image: nginx:alpine
    ports:
      - "8080:80"
    volumes:
      - ./html:/usr/share/nginx/html

  api:
    image: node:alpine
    working_dir: /app
    volumes:
      - ./api:/app
    command: npm start
```

Run with:
```bash
podman-compose up -d
```

## Podman-Specific Features

### Pods (Group Containers)
```bash
# Create a pod
podman pod create --name mypod -p 8080:80

# Add container to pod
podman run -d --pod mypod nginx:alpine

# List pods
podman pod ls

# Inspect pod
podman pod inspect mypod

# Stop pod (stops all containers in pod)
podman pod stop mypod
```

### Rootless Containers
```bash
# Podman runs rootless by default (safer!)
# No sudo needed:
podman ps
podman run -d nginx:alpine

# Check rootless status
podman info | grep rootless
```

### Podman as Docker Replacement
```bash
# Add alias for convenience
alias docker=podman

# Now use docker commands with podman!
docker ps  # Actually runs podman ps
```

## Building Images

### Dockerfile Build
```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
CMD ["python", "app.py"]
```

```bash
# Build with Docker
docker build -t myapp:latest .

# Build with Podman
podman build -t myapp:latest .

# Build with build args
podman build --build-arg VERSION=1.0 -t myapp:1.0 .
```

### NixOS for Container Images
```bash
# Build NixOS-based container image
nix-build '<nixpkgs/nixos>' -A config.system.build.tarball

# Load into podman
podman load < result/tarball.tar
```

## Volumes and Data

### Create Volume
```bash
# Docker
docker volume create mydata
docker run -v mydata:/data nginx:alpine

# Podman
podman volume create mydata
podman run -v mydata:/data nginx:alpine
```

### Bind Mounts
```bash
# Mount local directory
docker run -v $(pwd)/data:/data nginx:alpine
podman run -v $(pwd)/data:/data nginx:alpine

# Read-only mount
docker run -v $(pwd)/data:/data:ro nginx:alpine
```

## Networking

### List Networks
```bash
docker network ls
podman network ls
```

### Create Network
```bash
# Bridge network
docker network create mynet
podman network create mynet

# Connect container to network
docker network connect mynet mycontainer
podman network connect mynet mycontainer
```

### Host Ports
```bash
# Expose ports
docker run -p 8080:80 nginx:alpine
podman run -p 8080:80 nginx:alpine

# Expose all published ports
docker run -P nginx:alpine
podman run -P nginx:alpine
```

## Systemd Integration

Podman integrates with systemd for service management:

### Generate Systemd Service
```bash
# Generate systemd unit for a container
podman generate systemd --name mycontainer > /etc/systemd/system/container-mycontainer.service

# Enable and start
systemctl enable container-mycontainer.service
systemctl start container-mycontainer.service
```

### Pod with Systemd
```bash
# Create a pod
podman pod create --name webapp -p 8080:80

# Generate systemd service for the pod
podman generate systemd --name webapp --files --restart-policy=always

# Copy to systemd directory
cp container-webapp.service /etc/systemd/system/
cp container-*webapp*.service /etc/systemd/system/

# Enable
systemctl enable --now container-webapp.service
```

## NixOS Configuration

### Enable Podman
```nix
# In host configuration.nix
virtualisation.podman = {
  enable = true;
  dockerCompat = true;  # Provide docker alias
  dockerSocket = true;   # Provide /var/run/docker.sock
};

# Enable podman-compose
environment.systemPackages = with pkgs; [
  podman-compose
];
```

### Enable Docker
```nix
# In host configuration.nix
virtualisation.docker = {
  enable = true;
  enableOnBoot = true;
  autoPrune = {
    enable = true;
    dates = "weekly";
  };
};

# Add docker-compose
environment.systemPackages = with pkgs; [
  docker-compose
];
```

### Rootless Podman
```nix
# For rootless Podman, add user to subuids/subgids
users.users.j_kro = {
  subUidRanges = [ { startUid = 100000; count = 65536; } ];
  subGidRanges = [ { startGid = 100000; count = 65536; } ];
};

# Enable podman
virtualisation.podman = {
  enable = true;
};
```

## Common Workflows

### Development Environment
```bash
# Create development container
podman run -it --rm \
  -v $(pwd):/app \
  -w /app \
  node:alpine \
  sh

# Inside container
npm install
npm run dev
```

### Database Container
```bash
# Run PostgreSQL
podman run -d \
  --name db \
  -e POSTGRES_PASSWORD=secret \
  -v pgdata:/var/lib/postgresql/data \
  -p 5432:5432 \
  postgres:16

# Connect to database
podman exec -it db psql -U postgres
```

### Web Stack
```yaml
# docker-compose.yml
version: "3.8"
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_DB: appdb
      POSTGRES_USER: appuser
      POSTGRES_PASSWORD: secret
    volumes:
      - pgdata:/var/lib/postgresql/data

  redis:
    image: redis:alpine
    volumes:
      - redisdata:/data

  app:
    build: .
    ports:
      - "8080:8080"
    depends_on:
      - db
      - redis

volumes:
  pgdata:
  redisdata:
```

Run with:
```bash
podman-compose up -d
```

## Troubleshooting

### Container Won't Start
```bash
# Check logs
podman logs <container>

# Check container status
podman ps -a

# Inspect container
podman inspect <container>
```

### Port Already in Use
```bash
# Check what's using the port
sudo lsof -i :8080

# Or
sudo netstat -tulpn | grep 8080
```

### Permission Issues
```bash
# For rootless Podman, check subuids/subgids
cat /etc/subuid
cat /etc/subgid

# Re-login to apply changes
```

### Image Build Fails
```bash
# Enable buildKit for better builds
export DOCKER_BUILDKIT=1

# Or with Podman
export BUILDAH_LAYERS=true
```

## Cleanup

### Remove Unused Resources
```bash
# Remove stopped containers
docker container prune
podman container prune

# Remove unused images
docker image prune -a
podman image prune -a

# Remove unused volumes
docker volume prune
podman volume prune

# Remove everything unused
docker system prune -a --volumes
podman system prune -a --volumes
```

## Quick Reference

| Task | Docker | Podman |
|------|--------|--------|
| Run container | `docker run -d nginx` | `podman run -d nginx` |
| List containers | `docker ps` | `podman ps` |
| View logs | `docker logs <id>` | `podman logs <id>` |
| Stop | `docker stop <id>` | `podman stop <id>` |
| Build | `docker build -t img .` | `podman build -t img .` |
| Compose | `docker-compose up -d` | `podman-compose up -d` |
| Prune | `docker system prune` | `podman system prune` |

## Related Skills
- **kubernetes-architect**: For Kubernetes orchestration
- **docker-best-practices**: For Docker best practices (installed)
- **nix-rebuild**: For applying container runtime configuration
