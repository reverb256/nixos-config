# Hermes Agent Container Definition
# Podman container for Kubernetes deployment
{ pkgs, ... }:
let
  pythonEnv = pkgs.python311;
  hermesPackage = import ./package.nix { inherit pkgs; };
in
{
  hermes-agent-container = pkgs.podman.buildImage {
    name = "hermes-agent";
    tag = "latest";
    config = {
      Cmd = [ "hermes" ];
      Env = [
        # Python path
        "PATH=${pythonEnv}/bin:/bin"
        # AI Gateway (will be overridden per environment)
        "HERMES_AI_GATEWAY_URL=http://ai-gateway:8080/v1"
        "OPENAI_API_KEY=not-needed"
        "OPENAI_BASE_URL=http://ai-gateway:8080/v1"
        # Hermes configuration
        "HERMES_HOME=/data/hermes"
        "HERMES_CONFIG=/config/hermes"
        # MCP Integration
        "HERMES_ENABLE_MCP=true"
        "HERMES_MCP_CONFIG=/config/mcp-servers.yaml"
        # Logging
        "HERMES_LOG_LEVEL=INFO"
        "PYTHONUNBUFFERED=1"
      ];
      WorkingDir = "/workspace";
      Volumes = [
        # Hermes data directory
        "/data/hermes"
        # Shared skills (read-only)
        "/skills:ro"
        # Configuration
        "/config/hermes:ro"
      ];
      ExposedPorts = [
        # Not used in K8s (services instead), but documented for reference
        "8080/tcp"
      ];
      Labels = {
        "org.hermes-agent.version" = "0.1.0";
        "org.hermes-agent.description" = "Self-improving AI agent";
      };
    };
  };

  # Kubernetes manifests (for future deployment)
  kubernetesManifests = {
    deployment = ''
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hermes-agent
  namespace: ai-inference
  labels:
    app: hermes-agent
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hermes-agent
  template:
    metadata:
      labels:
        app: hermes-agent
    spec:
      containers:
      - name: hermes-agent
        image: ghcr.io/jkro/hermes-agent:latest
        env:
        - name: HERMES_AI_GATEWAY_URL
          value: "http://ai-gateway.ai-inference.svc.cluster.local:8080/v1"
        - name: OPENAI_API_KEY
          value: "not-needed"
        - name: OPENAI_BASE_URL
          value: "http://ai-gateway.ai-inference.svc.cluster.local:8080/v1"
        - name: HERMES_ENABLE_MCP
          value: "true"
        - name: HERMES_MCP_CONFIG
          value: "/config/mcp-servers.yaml"
        volumeMounts:
        - name: data
          mountPath: /data/hermes
        - name: skills
          mountPath: /skills
          readOnly: true
        - name: config
          mountPath: /config
          readOnly: true
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: hermes-data
      - name: skills
        configMap:
          name: hermes-skills
      - name: config
        configMap:
          name: hermes-config
      nodeSelector:
        # Run on nodes with GPU (for potential future use)
        gpu: "true"
''';
  };
}
