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
  # ai.lan -> llama-server-zephyr-3060ti on port 1236 (NodePort via host)
  mkRoute "ai.lan" "http://10.1.1.110:1236" +
  # ai-inference.lan -> AI Gateway via NodePort (10.1.1.110:30880)
  mkRoute "ai-inference.lan" "http://10.1.1.110:30880" +
  # openwebui.lan -> OpenWebUI via NodePort (10.1.1.110:32080)
  mkRoute "openwebui.lan" "http://10.1.1.110:32080" +
  # brain.lan -> Knowledge Fabric API (via Flannel pod IP)
  mkRoute "brain.lan" "http://10.244.1.7:3000" +
  # privacy-filter.lan -> Privacy Filter (via Flannel pod IP)
  mkRoute "privacy-filter.lan" "http://10.244.1.23:8080" +
  # Search
  mkRoute "searxng.lan, search.lan" "http://10.1.1.110:32080" +
  # Haven (personal wiki)
  mkRoute "haven.lan" "http://10.1.1.110:32080" +
  # Monitoring
  mkRoute "grafana.lan" "http://10.1.1.110:32080" +
  # Orchestration
  mkRoute "mission-control.lan" "http://10.1.1.110:32080" +
  mkRoute "kagent.lan" "http://10.1.1.110:32080" +
  # SSO
  mkRoute "auth.lan" "127.0.0.1:8000"
