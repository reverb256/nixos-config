#!/usr/bin/env python3
"""Generate CycloneDX 1.6 SBOM for NixOS hosts."""

import json
import subprocess
import sys
import uuid
import re
from datetime import datetime, timezone
from pathlib import Path

HOST_ROLES = {
    "zephyr": "control-plane,gaming,AI",
    "nexus": "storage,GPU-computing",
    "forge": "GPU-computing,mining",
    "sentry": "monitoring,logging",
}

def run(cmd, remote=None):
    if remote:
        cmd = ["ssh", remote] + cmd
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.stdout.strip()


def run_nix_profile(remote=None):
    """Run nix profile list."""
    import os
    env = {**os.environ, "NO_COLOR": "1", "TERM": "dumb"}
    if remote:
        r = subprocess.run(
            ["ssh", remote, "NO_COLOR=1 TERM=dumb nix profile list"],
            capture_output=True, text=True,
        )
    else:
        r = subprocess.run(
            ["nix", "profile", "list"],
            capture_output=True, text=True, env=env,
        )
    return r.stdout.strip()

def parse_nix_store_path(path):
    """Extract (name, version) from /nix/store/hash-name-version"""
    basename = Path(path).name
    # Skip derivations and source paths
    if basename.endswith(".drv") or ".check" in basename or ".doc" in basename:
        return None
    if basename.endswith("-src") or basename.endswith("-source"):
        return None
    # Strip the nix store hash prefix (base32 string)
    m = re.match(r"^[a-z0-9]+-(.+)$", basename)
    if not m:
        return None
    rest = m.group(1)
    # Parse name-version where version starts with a digit
    m2 = re.match(r"^(.+?)-(\d[^-]*(?:-.+)?)$", rest)
    if m2:
        return (m2.group(1), m2.group(2))
    return None

def get_nix_closure(remote=None):
    """Get all store paths in system closure."""
    out = run(["nix-store", "-q", "--requisites", "/run/current-system"], remote)
    components = []
    seen = set()
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        parsed = parse_nix_store_path(line)
        if parsed and parsed not in seen:
            seen.add(parsed)
            components.append({
                "bom-ref": f"urn:uuid:{uuid.uuid4()}",
                "type": "library",
                "name": parsed[0],
                "version": parsed[1],
                "scope": "required",
            })
    return components

ANSI_RE = re.compile(r'\x1b\[[0-9;]*m')

def strip_ansi(s):
    return ANSI_RE.sub('', s)

def get_nix_profile(remote=None):
    """Get nix profile packages."""
    out = run_nix_profile(remote)
    components = []
    name = None
    for line in out.splitlines():
        clean = strip_ansi(line)
        if clean.startswith("Name:"):
            name = clean.split("Name:")[1].strip()
        elif clean.startswith("Store paths:") and name:
            path = clean.split("Store paths:")[1].strip()
            parsed = parse_nix_store_path(path)
            if parsed:
                components.append({
                    "bom-ref": f"urn:uuid:{uuid.uuid4()}",
                    "type": "application",
                    "name": parsed[0],
                    "version": parsed[1],
                    "scope": "required",
                    "properties": [{"name": "nix:source", "value": "nix-profile"}],
                })
            name = None
    return components

def get_flatpak(remote=None):
    """Get installed flatpaks."""
    out = run(["flatpak", "list", "--columns=name,version,ref"], remote)
    components = []
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) < 3 or parts[0] == "Name":
            continue
        name, version, ref = parts[0], parts[1] or "unknown", parts[2]
        comp = {
            "bom-ref": f"urn:uuid:{uuid.uuid4()}",
            "type": "application",
            "name": name,
            "version": version,
            "scope": "required",
        }
        if ref:
            comp["purl"] = f"pkg:flatpak/{ref}"
        components.append(comp)
    return components

def get_npm_global(remote=None):
    """Get npm global packages with versions."""
    npm_path = Path.home() / ".npm-global" / "lib" / "node_modules"
    if remote:
        ls_out = run(["ls", str(npm_path)], remote)
        packages = [p for p in ls_out.splitlines() if p]
    else:
        packages = [p.name for p in npm_path.iterdir() if p.is_dir()] if npm_path.exists() else []

    components = []
    for pkg in packages:
        version = "unknown"
        try:
            if remote:
                v = run(["node", "-e", f"console.log(require('{pkg}/package.json').version)"], remote)
            else:
                v = run(["node", "-e", f"console.log(require('{pkg}/package.json').version)"])
            if v:
                version = v
        except Exception:
            pass
        components.append({
            "bom-ref": f"urn:uuid:{uuid.uuid4()}",
            "type": "application",
            "name": pkg,
            "version": version,
            "purl": f"pkg:npm/{pkg}@{version}",
            "scope": "required",
            "properties": [{"name": "npm:source", "value": "global"}],
        })
    return components

def get_local_bin(remote=None):
    """Get curl-installed binaries in ~/.local/bin."""
    bin_path = Path.home() / ".local" / "bin"
    if remote:
        ls_out = run(["ls", str(bin_path)], remote)
        bins = [b for b in ls_out.splitlines() if b]
    else:
        bins = [b.name for b in bin_path.iterdir() if b.is_file()] if bin_path.exists() else []

    components = []
    for b in bins:
        if b.endswith((".sh", ".py")):
            continue
        components.append({
            "bom-ref": f"urn:uuid:{uuid.uuid4()}",
            "type": "application",
            "name": b,
            "version": "unversioned",
            "scope": "required",
            "properties": [{"name": "install:method", "value": "curl/manual"}],
        })
    return components

def parse_container_image(ref_str):
    """Parse 'registry/namespace/name:tag|size' into (name, version, purl)."""
    parts = ref_str.strip().split("|")
    ref = parts[0]
    size = parts[1] if len(parts) > 1 else "unknown"
    # Skip dangling images
    if ref.startswith("<none>"):
        return None
    # Split tag from image ref
    if ":" in ref:
        # Handle ports in registry (e.g., localhost:5000/name:tag)
        last_colon = ref.rfind(":")
        image = ref[:last_colon]
        tag = ref[last_colon + 1:]
    else:
        image = ref
        tag = "latest"
    name = image.replace("/", "--")
    purl = f"pkg:docker/{image}@{tag}"
    return (name, tag, purl, size)


def get_container_images(runtime, remote=None):
    """Get container images from docker or podman."""
    fmt = "{{.Repository}}:{{.Tag}}|{{.Size}}"
    if remote:
        # Wrap in single quotes to protect from fish shell
        cmd = [runtime, "images", "--format", f"'{fmt}'"]
    elif runtime == "docker":
        cmd = ["sudo", runtime, "images", "--format", fmt]
    else:
        cmd = [runtime, "images", "--format", fmt]
    out = run(cmd, remote)
    # Strip any leading/trailing single quotes from fish
    out = out.strip("'")
    if not out:
        return []
    components = []
    for line in out.splitlines():
        parsed = parse_container_image(line)
        if not parsed:
            continue
        name, tag, purl, size = parsed
        components.append({
            "bom-ref": f"urn:uuid:{uuid.uuid4()}",
            "type": "container",
            "name": name,
            "version": tag,
            "purl": purl,
            "scope": "required",
            "properties": [
                {"name": "container:runtime", "value": runtime},
                {"name": "container:size", "value": size},
            ],
        })
    return components


def get_k3s_images(remote=None):
    """Get K3s container images via crictl."""
    if remote:
        cmd = ["crictl", "--runtime-endpoint", "unix:///run/k3s/containerd/containerd.sock", "images"]
    else:
        cmd = ["sudo", "crictl", "--runtime-endpoint", "unix:///run/k3s/containerd/containerd.sock", "images"]
    out = run(cmd, remote)
    if not out:
        return []
    components = []
    seen = set()
    for line in out.splitlines():
        parts = line.split()
        if len(parts) < 3 or parts[0] == "IMAGE":
            continue
        image = parts[0]
        tag = parts[1]
        key = f"{image}:{tag}"
        if key in seen:
            continue
        seen.add(key)
        purl = f"pkg:docker/{image}@{tag}"
        components.append({
            "bom-ref": f"urn:uuid:{uuid.uuid4()}",
            "type": "container",
            "name": image.replace("/", "--"),
            "version": tag,
            "purl": purl,
            "scope": "required",
            "properties": [{"name": "container:runtime", "value": "k3s"}],
        })
    return components


def generate_sbom(hostname, remote=None, output_dir=Path("/etc/nixos/sbom")):
    print("  [1/8] NixOS system closure...")
    closure = get_nix_closure(remote)
    print(f"        {len(closure)} packages")

    print("  [2/8] Nix profile...")
    profile = get_nix_profile(remote)
    print(f"        {len(profile)} packages")

    print("  [3/8] Flatpak...")
    flatpak = get_flatpak(remote)
    print(f"        {len(flatpak)} packages")

    print("  [4/8] npm global...")
    npm = get_npm_global(remote)
    print(f"        {len(npm)} packages")

    print("  [5/8] curl-installed (local bin)...")
    localbin = get_local_bin(remote)
    print(f"        {len(localbin)} binaries")

    print("  [6/8] Docker images...")
    docker = get_container_images("docker", remote)
    print(f"        {len(docker)} images")

    print("  [7/8] Podman images...")
    podman = get_container_images("podman", remote)
    print(f"        {len(podman)} images")

    print("  [8/8] K3s images...")
    k3s = get_k3s_images(remote)
    print(f"        {len(k3s)} images")

    all_components = closure + profile + flatpak + npm + localbin + docker + podman + k3s

    # Deduplicate by (name, version, type)
    seen = set()
    deduped = []
    for c in all_components:
        key = (c["name"], c["version"], c["type"])
        if key not in seen:
            seen.add(key)
            deduped.append(c)

    nix_version = run(["nix", "--version"], remote).splitlines()[0]
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    bom_uuid = str(uuid.uuid4())

    bom = {
        "$schema": "http://cyclonedx.org/schema/bom-1.6.schema.json",
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "serialNumber": f"urn:uuid:{bom_uuid}",
        "version": 1,
        "metadata": {
            "timestamp": ts,
            "component": {
                "bom-ref": f"urn:uuid:{bom_uuid}",
                "type": "platform",
                "name": hostname,
                "properties": [
                    {"name": "cluster:role", "value": HOST_ROLES.get(hostname, "unknown")},
                    {"name": "nix:version", "value": nix_version},
                    {"name": "total:components", "value": str(len(deduped))},
                ],
            },
        },
        "components": deduped,
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    out_path = output_dir / f"{hostname}-sbom.json"
    with open(out_path, "w") as f:
        json.dump(bom, f, indent=2)

    print(f"✅ {hostname}: {len(deduped)} unique components → {out_path}")
    return len(deduped)

if __name__ == "__main__":
    hostname = sys.argv[1] if len(sys.argv) > 1 else "zephyr"
    remote = sys.argv[2] if len(sys.argv) > 2 else None
    output_dir = Path(sys.argv[3]) if len(sys.argv) > 3 else Path("/etc/nixos/sbom")
    generate_sbom(hostname, remote, output_dir)
