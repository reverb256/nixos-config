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
  # AI services
  mkRoute "ai.lan" "llama-server-zephyr-3060ti.ai-inference.svc.cluster.local:1236"
  + mkRoute "ai-inference.lan" "ai-inference-gateway.ai-inference.svc.cluster.local:8080"
  + mkRoute "openwebui.lan" "open-webui.ai-inference.svc.cluster.local:8080"
  + mkRoute "brain.lan" "knowledge-fabric-api.ai-inference.svc.cluster.local:3000"
  + mkRoute "privacy-filter.lan" "privacy-filter.ai-inference.svc.cluster.local:8080"
  # Search
  + mkRoute "searxng.lan, search.lan" "searxng.search.svc.cluster.local:8080"
  # Haven (personal wiki)
  + mkRoute "haven.lan" "haven.haven.svc.cluster.local:3000"
  # Monitoring
  + mkRoute "grafana.lan" "grafana.ai-inference.svc.cluster.local:3000"
  # Orchestration
  + mkRoute "mission-control.lan" "mission-control.orchestration.svc.cluster.local:3000"
  + mkRoute "kagent.lan" "kagent-ui.kagent.svc.cluster.local:8080"
  # SSO
  + mkRoute "auth.lan" "127.0.0.1:8000"
