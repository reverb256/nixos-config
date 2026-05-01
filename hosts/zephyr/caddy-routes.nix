{cluster}: let
  tls = "tls /etc/ssl/cluster-ca/leaf.crt /etc/ssl/cluster-ca/leaf.key";
  proxyHeader = ''
    header_up Host {host}
    header_up X-Real-IP {remote_host}
    header_up X-Forwarded-For {remote_host}
    header_up X-Forwarded-Host {host}
    header_up X-Forwarded-Proto {scheme}
  '';

  mkRoute = hosts: backend: ''
    ${hosts} {
      ${tls}
      encode zstd gzip
      reverse_proxy ${backend} {
        ${proxyHeader}
      }
    }
  '';
in
  # AI services -> use NodePort (working) and direct pod IPs via Flannel
  # ClusterIP is unreachable from host (kube-proxy runs in container, not host-level)
  # ai.lan -> llama-server-3090 (host port 1237)
  mkRoute "ai.lan" "http://127.0.0.1:1237" +
  # ai-inference.lan -> AI Gateway (NodePort 30880)
  mkRoute "ai-inference.lan" "http://127.0.0.1:30880" +
  # openwebui.lan -> OpenWebUI (NodePort 32080)
  mkRoute "openwebui.lan" "http://127.0.0.1:32080" +
  # brain.lan -> Knowledge Fabric API (via Flannel pod IP)
  mkRoute "brain.lan" "http://10.244.1.7:3000" +
  # privacy-filter.lan -> Privacy Filter (via Flannel pod IP)
  mkRoute "privacy-filter.lan" "http://10.244.1.23:8080" +
  # Search (SearXNG NodePort 32081)
  mkRoute "searxng.lan, search.lan" "http://127.0.0.1:32081" +
  # Haven (oauth2-proxy NodePort 32100)
  mkRoute "haven.lan" "http://127.0.0.1:32100" +
  # Monitoring (Grafana NodePort 32102)
  mkRoute "grafana.lan" "http://127.0.0.1:32102" +
  # Orchestration (MC NodePort 32101, kagent NodePort 32103)
  mkRoute "mission-control.lan" "http://127.0.0.1:32101" +
  mkRoute "kagent.lan" "http://127.0.0.1:32103" +
  # SSO
  mkRoute "auth.lan" "127.0.0.1:8000"
