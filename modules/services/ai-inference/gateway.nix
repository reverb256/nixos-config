# AI Inference Gateway - API Gateway with FastAPI
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.ai-inference;
  inherit (lib) mkIf mkOrder literalExpression;

  # Gateway application
  gatewayApp = pkgs.writeTextFile {
    name = "ai-inference-gateway";
    text = ''
                  #!/usr/bin/env python3
                  """
                  AI Inference Gateway
                  Routes requests to LM Studio with authentication and metrics
                  """
                  import os
                  sys.path.insert(0, "${cfg.package}/${cfg.package.sitePackages}")

                  from fastapi import FastAPI, Request, Response, HTTPException, Header
                  from fastapi.responses import StreamingResponse, JSONResponse
                  import httpx
                  from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
                  from typing import Optional, List
                  import time
                  import json
                  from functools import lru_cache

      # Configuration
            BACKEND_URL = os.getenv("BACKEND_URL", "${cfg.backend.url}")
            BACKEND_TYPE = os.getenv("BACKEND_TYPE", "${cfg.backend.type}")
            ZAI_API_KEY = os.getenv("ZAI_API_KEY", "")
            ZAI_BASE_URL = os.getenv("ZAI_BASE_URL", "https://api.z.ai/v1")
            GATEWAY_HOST = os.getenv("GATEWAY_HOST", "${cfg.gateway.host}")
            AUTH_MODE = os.getenv("AUTH_MODE", "${cfg.auth.mode}")
            FALLBACK_CHAIN = os.getenv("FALLBACK_CHAIN", "vllm,lm-studio,zai").split(",")

            # Backend clients
            backend_client = httpx.AsyncClient(
                base_url=BACKEND_URL,
                timeout=300.0
            )
            
            # ZAI client (for privacy proxy)
            zai_client = httpx.AsyncClient(
                base_url=ZAI_BASE_URL,
                timeout=3600.0,
                headers={"Authorization": f"Bearer {ZAI_API_KEY}"} if ZAI_API_KEY else {}
            )
            
            # MCP server registry
            mcp_servers = {}
            mcp_tools = {}
                  request_duration = Histogram(
                      'ai_inference_request_duration_seconds',
                      'Request duration',
                      ['model', 'auth_mode']
                  )
                  tokens_generated = Counter(
                      'ai_inference_tokens_generated_total',
                      'Total tokens generated',
                      ['model']
                  )
                  active_requests = Gauge(
                      'ai_inference_active_requests',
                      'Active inference requests'
                  )

                  app = FastAPI(
                      title="AI Inference Gateway",
                      description="Routes requests to LM Studio with authentication and metrics",
                      version="1.0.0"
                  )

                  # Backend client
                  backend_client = httpx.AsyncClient(
                      base_url=BACKEND_URL,
                      timeout=300.0
                  )

                  @app.on_event("startup")
                  async def startup():
                      """Verify backend connection on startup"""
                      try:
                          resp = await backend_client.get("/v1/models")
                          if resp.status_code == 200:
                              models = resp.json().get("data", [])
                              print(f"✓ Connected to backend: {len(models)} models available")
                              for m in models:
                                  print(f"  - {m['id']}")
                          else:
                              print(f"⚠ Backend returned status {resp.status_code}")
                      except Exception as e:
                          print(f"✗ Failed to connect to backend: {e}")

                  @app.on_event("shutdown")
                  async def shutdown():
                      await backend_client.aclose()

                  @app.get("/health")
                  async def health():
                      """Health check endpoint"""
                      try:
                          resp = await backend_client.get("/v1/models", timeout=5.0)
                          backend_healthy = resp.status_code == 200
                          return JSONResponse({
                              "status": "healthy" if backend_healthy else "degraded",
                              "backend": BACKEND_URL,
                              "auth_mode": AUTH_MODE,
                              "backend_healthy": backend_healthy
                          })
                      except Exception as e:
                          return JSONResponse({
                              "status": "unhealthy",
                              "backend": BACKEND_URL,
                              "auth_mode": AUTH_MODE,
                              "error": str(e)
                          }, status_code=503)

                  @app.get("/metrics")
                  async def metrics():
                      """Prometheus metrics endpoint"""
                      return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

                  @app.get("/v1/models")
                  async def list_models():
                      """Proxy model list from backend"""
                      resp = await backend_client.get("/v1/models")
                      return JSONResponse(resp.json(), status_code=resp.status_code)

                  async def verify_auth(request: Request) -> Optional[dict]:
                      """Verify authentication based on mode"""
                      if AUTH_MODE == "none":
                          return {"tier": "personal", "allowed": True}

                      client_ip = request.client.host
                      headers = request.headers

                      # Tailscale auth: check if request comes from Tailscale IP
                      if AUTH_MODE == "tailscale":
                          # Tailscale IPs start with 100.x.x.x or fd7a:115c:a1e0::
                          is_tailscale = (
                              client_ip.startswith("100.") or
                              client_ip.startswith("fd7a:") or
                              client_ip == "127.0.0.1" or
                              client_ip == "::1"
                          )
                          if is_tailscale:
                              return {"tier": "trusted", "allowed": True}
                          raise HTTPException(status_code=403, detail="Access restricted to Tailscale network")

                      # API key auth
                      if AUTH_MODE == "api-key":
                          auth_header = headers.get("Authorization", "")
                          if not auth_header.startswith("Bearer "):
                              raise HTTPException(status_code=401, detail="Missing API key")
                          # API key validation would go here
                          # For now, accept any non-empty bearer token
                          return {"tier": "api", "allowed": True}

                      # Web3 auth (future)
                      if AUTH_MODE == "web3":
                          raise HTTPException(status_code=501, detail="Web3 authentication not implemented")

                      return {"tier": "unknown", "allowed": False}

                  @app.post("/v1/chat/completions")
                  async def chat_completions(request: Request):
                      """OpenAI-compatible chat completions endpoint"""
                      active_requests.inc()
                      start_time = time.time()

                      try:
                          # Verify authentication
                          auth_result = await verify_auth(request)
                          if not auth_result.get("allowed"):
                              request_counter.labels(
                                  model="unknown",
                                  status="unauthorized",
                                  auth_mode=AUTH_MODE
                              ).inc()
                              raise HTTPException(status_code=403, detail="Authentication failed")

                          # Get request body - pass through model as specified by client
                          body = await request.json()
                          model = body.get("model", "default")
                          stream = body.get("stream", False)

                          # Route to backend
                          if stream:
                              # Streaming response
                              async def generate():
                                  try:
                                      async with backend_client.stream(
                                          "POST",
                                          "/v1/chat/completions",
                                          json=body,
                                          headers={"Content-Type": "application/json"}
                                      ) as backend_resp:
                                          async for chunk in backend_resp.aiter_bytes():
                                              yield chunk
                                  except Exception as e:
                                      print(f"Stream error: {e}")

                              return StreamingResponse(
                                  generate(),
                                  media_type="text/event-stream"
                              )
                          else:
                              # Non-streaming response
                              backend_resp = await backend_client.post(
                                  "/v1/chat/completions",
                                  json=body,
                                  headers={"Content-Type": "application/json"}
                              )

                              result = backend_resp.json()

                              # Extract metrics
                              if backend_resp.status_code == 200:
                                  usage = result.get("usage", {})
                                  if usage:
                                      tokens_generated.labels(model=model).inc(
                                          usage.get("completion_tokens", 0)
                                      )

                              duration = time.time() - start_time
                              request_duration.labels(model=model, auth_mode=auth_result["tier"]).observe(duration)
                              request_counter.labels(
                                  model=model,
                                  status="success" if backend_resp.status_code == 200 else "error",
                                  auth_mode=AUTH_MODE
                              ).inc()

                              return JSONResponse(result, status_code=backend_resp.status_code)

                      except HTTPException:
                          raise
                      except Exception as e:
                          request_counter.labels(
                              model="unknown",
                              status="error",
                              auth_mode=AUTH_MODE
                          ).inc()
                          return JSONResponse(
                              {"error": str(e)},
                              status_code=500
                          )
                      finally:
                          active_requests.dec()

                  @app.post("/v1/completions")
                  async def completions(request: Request):
                      """OpenAI-compatible completions endpoint"""
                      active_requests.inc()

                      try:
                          await verify_auth(request)
                          body = await request.json()

                          backend_resp = await backend_client.post(
                              "/v1/completions",
                              json=body,
                              headers={"Content-Type": "application/json"}
                          )

                          return JSONResponse(backend_resp.json(), status_code=backend_resp.status_code)

                      except HTTPException:
                          raise
                      except Exception as e:
                          return JSONResponse({"error": str(e)}, status_code=500)
                      finally:
                          active_requests.dec()

                  @app.post("/v1/embeddings")
                  async def embeddings(request: Request):
                      """OpenAI-compatible embeddings endpoint"""
                      active_requests.inc()

                      try:
                          await verify_auth(request)
                          body = await request.json()

                          backend_resp = await backend_client.post(
                              "/v1/embeddings",
                              json=body,
                              headers={"Content-Type": "application/json"}
                          )

                          return JSONResponse(backend_resp.json(), status_code=backend_resp.status_code)

                      except HTTPException:
                          raise
                      except Exception as e:
                          return JSONResponse({"error": str(e)}, status_code=500)
                      finally:
                          active_requests.dec()

                  # ZAI Privacy Proxy - routes to ZAI API with auth
                  @app.post("/zai/v1/chat/completions")
                  async def zai_chat_completions(request: Request):
                      """Proxy to ZAI API - keeps API key on server, not client"""
                      active_requests.inc()
                      start_time = time.time()
                      
                      try:
                          body = await request.json()
                          model = body.get("model", "unknown")
                          
                          # Forward to ZAI with stored API key
                          async with zai_client.stream(
                              "POST",
                              "/v1/chat/completions",
                              json=body
                          ) as resp:
                              async def generate():
                                  async for chunk in resp.aiter_bytes():
                                      yield chunk
                              
                              return StreamingResponse(
                                  generate(),
                                  media_type="text/event-stream"
                              )
                              
                      except HTTPException:
                          raise
                      except Exception as e:
                          return JSONResponse({"error": str(e)}, status_code=500)
                      finally:
                          active_requests.dec()

                  # MCP Broker - Tool discovery and routing
            @app.post("/mcp/register")
            async def mcp_register(request: Request):
                """Register MCP server with tools"""
                try:
                    data = await request.json()
                    server_id = data.get("id")
                    tools = data.get("tools", [])
                    
                    if not server_id:
                        raise HTTPException(status_code=400, detail="Missing server_id")
                    
                    mcp_servers[server_id] = {
                        "tools": tools,
                        "registered_at": time.time()
                    }
                    
                    for tool in tools:
                        tool_name = tool.get("name")
                        if tool_name:
                            mcp_tools[tool_name] = {
                                "server": server_id,
                                "tool": tool
                            }
                    
                    return {"status": "registered", "server_id": server_id, "tools": len(tools)}
                except Exception as e:
                    return JSONResponse({"error": str(e)}, status_code=500)

            @app.get("/mcp/tools")
            async def mcp_list_tools():
                """List all registered MCP tools"""
                return {
                    "total": len(mcp_tools),
                    "tools": list(mcp_tools.keys()),
                    "servers": list(mcp_servers.keys())
                }

            @app.post("/mcp/call")
            async def mcp_call_tool(request: Request):
                """Call an MCP tool through the broker"""
                try:
                    data = await request.json()
                    tool_name = data.get("tool")
                    arguments = data.get("arguments", {})
                    
                    if not tool_name:
                        raise HTTPException(status_code=400, detail="Missing tool name")
                    
                    if tool_name not in mcp_tools:
                        raise HTTPException(status_code=404, detail=f"Tool {tool_name} not found")
                    
                    server_id = mcp_tools[tool_name]["server"]
                    server = mcp_servers.get(server_id)
                    
                    if not server:
                        raise HTTPException(status_code=503, detail=f"Server {server_id} not found")
                    
                    # In production, this would route to the actual MCP server
                    # For now, return a mock response
                    return {
                        "tool": tool_name,
                        "server": server_id,
                        "arguments": arguments,
                        "result": "Tool execution would be routed to MCP server"
                    }
                except HTTPException:
                    raise
                except Exception as e:
                    return JSONResponse({"error": str(e)}, status_code=500)

            # Graceful degradation - try fallback backends
            async def route_with_fallback(request: Request, body: dict):
                """Route request with graceful degradation across backends"""
                errors = []
                
                # Try primary backend first
                try:
                    if BACKEND_TYPE == "zai":
                        async with zai_client.stream(
                            "POST",
                            "/v1/chat/completions",
                            json=body
                        ) as resp:
                            if resp.status_code == 200:
                                return StreamingResponse(
                                    resp.aiter_bytes(),
                                    media_type="text/event-stream"
                                )
                    else:
                        async with backend_client.stream(
                            "POST",
                            "/v1/chat/completions",
                            json=body
                        ) as resp:
                            if resp.status_code == 200:
                                return StreamingResponse(
                                    resp.aiter_bytes(),
                                    media_type="text/event-stream"
                                )
                except Exception as e:
                    errors.append(f"{BACKEND_TYPE}: {str(e)}")
                
                # Try fallback backends
                for fallback in FALLBACK_CHAIN:
                    if fallback == BACKEND_TYPE:
                        continue
                    
                    try:
                        if fallback == "zai":
                            async with zai_client.stream(
                                "POST",
                                "/v1/chat/completions",
                                json=body
                            ) as resp:
                                if resp.status_code == 200:
                                    print(f"✓ Fallback to {fallback} successful")
                                    return StreamingResponse(
                                        resp.aiter_bytes(),
                                        media_type="text/event-stream"
                                    )
                        elif fallback == "lm-studio":
                            async with backend_client.stream(
                                "POST",
                                "/v1/chat/completions",
                                json=body
                            ) as resp:
                                if resp.status_code == 200:
                                    print(f"✓ Fallback to {fallback} successful")
                                    return StreamingResponse(
                                        resp.aiter_bytes(),
                                        media_type="text/event-stream"
                                    )
                    except Exception as e:
                        errors.append(f"{fallback}: {str(e)}")
                        continue
                
                # All backends failed
                raise HTTPException(
                    status_code=503,
                    detail={
                        "error": "All backends unavailable",
                        "attempts": errors
                    }
                )

            if __name__ == "__main__":
                      import uvicorn
                      uvicorn.run(
                          app,
                          host=GATEWAY_HOST,
                          port=int(os.getenv("PORT", "8080")),
                          workers=${toString cfg.gateway.workers}
                      )
    '';
    executable = true;
  };

in
{
  config = mkIf (cfg.enable && cfg.gateway.enable) {
    # Systemd service for the gateway
    systemd.services.ai-inference-gateway = {
      description = "AI Inference API Gateway";
      after = [
        "network.target"
        "network-online.target"
        "lm-studio.service"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        BACKEND_URL = cfg.backend.url;
        GATEWAY_HOST = cfg.gateway.host;
        PORT = toString cfg.gateway.port;
        AUTH_MODE = cfg.auth.mode;
        PYTHONUNBUFFERED = "1";
      };

      serviceConfig = {
        ExecStart =
          "${cfg.package}/bin/uvicorn ${gatewayApp}:app "
          + "--host ${cfg.gateway.host} "
          + "--port ${toString cfg.gateway.port} "
          + "--workers ${toString cfg.gateway.workers} "
          + "--log-level info";

        ExecReload = "/bin/kill -HUP $MAINPID";

        Restart = "on-failure";
        RestartSec = "10s";

        # Security
        User = "ai-inference";
        Group = "ai-inference";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/tmp" ];

        # Resource limits
        MemoryLimit = "2G";
        CPUWeight = 100;
        IOWeight = 100;

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "ai-gateway";
      };
    };

    # User for the service
    users.users.ai-inference = {
      isSystemUser = true;
      group = "ai-inference";
      description = "AI Inference Gateway";
    };
    users.groups.ai-inference = { };
  };
}
