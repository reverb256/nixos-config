# Container Image Vulnerability Scanning

## Tool: Trivy

Trivy scans container images for known vulnerabilities (CVEs).

## Usage

### Scan an image

```bash
# Scan local image
trivy image nginx:latest

# Scan with severity filter
trivy image --severity HIGH,CRITICAL nginx:latest

# Scan and output JSON
trivy image --format json --output report.json nginx:latest
```

### Scan running containers

```bash
# Scan all running containers
trivy image --skip-db-update $(docker ps -q)

# Scan specific container
trivy image $(docker inspect --format='{{.Config.Image}}' <container-name>)
```

### CI/CD Integration

Add to CI pipeline:

```yaml
- name: Scan image
  run: |
    trivy image --severity HIGH,CRITICAL --exit-code 1 myapp:\${{ github.sha }}
```

## Scanning Schedule

To enable automatic weekly scanning, uncomment the trivy-scan service and timer in the container-scanning.nix module and customize the image to scan.

## Remediation

When vulnerabilities are found:
1. Update base image to latest version
2. Rebuild application image
3. Rescan to verify fixes

## References

- https://aquasecurity.github.io/trivy/
- https://owasp.org/Top10/A05_2021-Security_Misconfiguration/
