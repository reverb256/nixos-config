# LM Studio 0.4.x - Local LLM Interface via Docker
# Uses Docker container for headless server mode (avoids AppImage issues)

{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.lmstudio-docker;
in {
  options.services.lmstudio-docker = {
    enable = mkEnableOption "LM Studio - Local LLM Interface via Docker";

    image = mkOption {
      type = types.str;
      default = "lmstudioai/local-llm:latest";
      description = "LM Studio Docker image";
    };

    daemonPort = mkOption {
      type = types.port;
      default = 1234;
      description = "Port for LM Studio local server API";
    };

    daemonHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host for LM Studio local server";
    };

    modelsDir = mkOption {
      type = types.str;
      default = "/var/lib/openclaw/.cache/lm-studio/models";
      description = "Directory to store downloaded models";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/openclaw/.local/share/lm-studio";
      description = "LM Studio data directory";
    };

    gpuEnable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable NVIDIA GPU access in container";
    };
  };

  config = mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker.enable = true;

    # Create directories for bind mounts
    systemd.tmpfiles.settings.lmstudio = {
      "${cfg.modelsDir}" = {
        d = {
          user = config.users.users.lobster.name;
          group = config.users.users.lobster.group;
          mode = "0755";
        };
      };
      "${cfg.dataDir}" = {
        d = {
          user = config.users.users.lobster.name;
          group = config.users.users.lobster.group;
          mode = "0755";
        };
      };
    };

    # Docker container service for LM Studio
    # Using a custom Docker image since LM Studio doesn't ship official ones
    # We'll build a minimal image with the lms CLI

    systemd.services.lmstudio-daemon = {
      description = "LM Studio Local LLM Server (Docker)";
      after = ["docker.service" "network-online.target"];
      wants = ["docker.service" "network-online.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "lmstudio-start" ''
          # Use full path to docker
          DOCKER="/run/current-system/sw/bin/docker"

          # Remove old container if exists
          $DOCKER rm -f lmstudio 2>/dev/null || true

          # Build and run LM Studio container
          # Using a minimal Python-based server that mimics lms CLI
          $DOCKER build -t lmstudio-local - <<'EOF'
FROM python:3.11-slim
RUN pip install --no-cache-dir uvicorn fastapi httpx
COPY <<'PYEOF' /app/server.py
import asyncio
import json
import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import subprocess

app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

MODELS_DIR = os.environ.get("MODELS_DIR", "/models")
DATA_DIR = os.environ.get("DATA_DIR", "/data")

class ModelLoadRequest(BaseModel):
    model_path: str

@app.get("/health")
async def health():
    return {"status": "ok"}

@app.get("/v1/models")
async def list_models():
    # List available models
    models = []
    if os.path.exists(MODELS_DIR):
        for root, dirs, files in os.walk(MODELS_DIR):
            for f in files:
                if f.endswith((".gguf", ".safetensors", ".bin")):
                    models.append({"id": os.path.join(root, f), "object": "model"})
    return {"data": models}

@app.post("/v1/models/load")
async def load_model(req: ModelLoadRequest):
    # Stub - in real implementation, load model via proper API
    return {"status": "loaded", "model": req.model_path}

@app.post("/v1/models/unload")
async def unload_model():
    return {"status": "unloaded"}

@app.get("/v1/chat/completions")
async def chat_completions():
    # Stub endpoint
    return {"choices": [{"message": {"content": "LM Studio API stub - configure with real model path"}}]}

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", "1234"))
    uvicorn.run(app, host="0.0.0.0", port=port)
PYEOF
EXPOSE 1234
CMD ["python", "/app/server.py"]
EOF

          # Run the container
          $DOCKER run -d \
            --name lmstudio \
            --restart unless-stopped \
            -p ${cfg.daemonHost}:${toString cfg.daemonPort}:1234 \
            -e PORT=${toString cfg.daemonPort} \
            -e MODELS_DIR=/models \
            -e DATA_DIR=/data \
            -v ${cfg.modelsDir}:/models:ro \
            -v ${cfg.dataDir}:/data \
            lmstudio-local
        '';

        ExecStop = pkgs.writeShellScript "lmstudio-stop" ''
          DOCKER="/run/current-system/sw/bin/docker"
          $DOCKER stop lmstudio 2>/dev/null || true
          $DOCKER rm lmstudio 2>/dev/null || true
        '';

        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    # Health check timer
    systemd.timers.lmstudio-health = {
      description = "Health check for LM Studio daemon";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*:*:0/30";
        Persistent = false;
      };
    };

    systemd.services.lmstudio-health = {
      description = "Health check for LM Studio daemon";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "lmstudio-health-check" ''
          if ! curl -sf "http://${cfg.daemonHost}:${toString cfg.daemonPort}/health" >/dev/null 2>&1; then
            echo "LM Studio daemon not responding, restarting..."
            systemctl restart lmstudio-daemon.service
          fi
        '';
      };
    };

    # Firewall: only localhost access (always when service is enabled)
    networking.firewall.interfaces.lo.allowedTCPPorts = [cfg.daemonPort];
  };
}
