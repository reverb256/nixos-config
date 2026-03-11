# GPU Mining Proxy for CR29 (Tari/Kryptex)
# Simple stratum proxy with multi-pool failover
#
# This proxy provides:
# - Stratum protocol forwarding for GPU miners (lolMiner, Gminer, etc.)
# - Multi-pool failover (Kryptex US/EU regional servers)
# - Centralized wallet configuration
# - TLS support for secure pool connections

{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.gpu-proxy;

  # The GPU proxy Python package
  gpu-proxy-package = pkgs.python3Packages.buildPythonApplication rec {
    pname = "gpu-proxy";
    version = "1.0.0";
    format = "other";  # Using dontUnpack, so no standard format

    # Use writeTextFile to create the proxy script
    src = pkgs.writeTextFile {
      name = "${pname}-${version}";
      text = ''
        #!/usr/bin/env python3
        """
        GPU Mining Stratum Proxy for CR29 (Tari/Kryptex)

        A simple stratum proxy that:
        - Listens for GPU miner connections (lolMiner, Gminer, etc.)
        - Connects to Kryptex CR29 pools with failover
        - Forwards stratum messages between miners and pools
        - Handles TLS connections to pools

        Usage: gpu-proxy --config /etc/gpu-proxy/config.json
        """

        import asyncio
        import json
        import logging
        import ssl
        import argparse
        import sys
        import traceback
        from pathlib import Path
        from typing import Optional, List, Dict, Any
        from dataclasses import dataclass


        @dataclass
        class PoolConfig:
            name: str
            url: str
            wallet: str
            password: str
            priority: int
            tls: bool

            @classmethod
            def from_dict(cls, data: Dict[str, Any]) -> "PoolConfig":
                return cls(
                    name=data["name"],
                    url=data["url"],
                    wallet=data["wallet"],
                    password=data.get("password", "x"),
                    priority=data.get("priority", 1),
                    tls=data.get("tls", True),
                )


        @dataclass
        class WorkerConfig:
            id: str
            password: str

            @classmethod
            def from_dict(cls, data: Dict[str, Any]) -> "WorkerConfig":
                return cls(
                    id=data["id"],
                    password=data.get("password", "x"),
                )


        @dataclass
        class ProxyConfig:
            listen_port: int
            api_port: int
            log_level: str
            pools: List[PoolConfig]
            workers: List[WorkerConfig]

            @classmethod
            def from_file(cls, path: str) -> "ProxyConfig":
                with open(path) as f:
                    data = json.load(f)

                pools = [PoolConfig.from_dict(p) for p in data.get("pools", [])]
                workers = [WorkerConfig.from_dict(w) for w in data.get("workers", [])]
                settings = data.get("settings", {})

                return cls(
                    listen_port=settings.get("listen_port", 3334),
                    api_port=settings.get("api_port", 8083),
                    log_level=settings.get("log_level", "INFO"),
                    pools=pools,
                    workers=workers,
                )


        def parse_pool_url(url: str) -> tuple[str, int, bool]:
            """Parse stratum URL into host, port, tls flag."""
            # Remove protocol prefix
            if "://" in url:
                url = url.split("://", 1)[1]

            # Split host and port
            if ":" in url:
                host, port_str = url.rsplit(":", 1)
                port = int(port_str)
            else:
                host = url
                port = 3333  # Default stratum port

            return host, port


        class StratumConnection:
            """Base class for stratum connections."""

            def __init__(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
                self.reader = reader
                self.writer = writer
                self.message_id = 0

            async def send_line(self, line: str):
                """Send a line (with newline)."""
                logging.debug(f"Sending: {line.strip()}")
                self.writer.write((line + "\\n").encode())
                await self.writer.drain()

            async def send_json(self, data: dict):
                """Send a JSON-RPC message."""
                if "id" not in data:
                    data["id"] = self.message_id
                    self.message_id += 1
                line = json.dumps(data, separators=(",", ":"))
                logging.info(f"Sending JSON: {line}")
                await self.send_line(line)

            async def recv_line(self) -> Optional[str]:
                """Receive a line."""
                try:
                    line = await self.reader.readline()
                    if not line:
                        logging.warning("Received empty line from pool")
                        return None
                    line = line.decode().strip()
                    logging.info(f"Received line: {line}")
                    return line
                except Exception as e:
                    logging.error(f"Error receiving: {e}")
                    return None

            async def recv_json(self) -> Optional[dict]:
                """Receive a JSON-RPC message."""
                line = await self.recv_line()
                if not line:
                    return None
                try:
                    data = json.loads(line)
                    logging.info(f"Received JSON: {data}")
                    return data
                except json.JSONDecodeError as e:
                    logging.error(f"Invalid JSON: {line} - {e}")
                    return None

            async def close(self):
                """Close the connection."""
                try:
                    self.writer.close()
                    await self.writer.wait_closed()
                except Exception:
                    pass


        class PoolConnection(StratumConnection):
            """Connection to an upstream mining pool."""

            def __init__(self, pool: PoolConfig, config: ProxyConfig):
                self.pool = pool
                self.config = config
                self.host: Optional[str] = None
                self.port: Optional[int] = None
                self.reader: Optional[asyncio.StreamReader] = None
                self.writer: Optional[asyncio.StreamWriter] = None
                self.connected = False
                self.difficulty: Optional[float] = None
                self.job: Optional[dict] = None
                self.subscribers: List = []  # Miner connections
                self.initialized = False  # Track if subscribe/authorize sent

            async def connect(self) -> bool:
                """Connect to the pool."""
                self.host, self.port = parse_pool_url(self.pool.url)

                logging.info(f"Connecting to pool {self.pool.name} at {self.host}:{self.port}")

                try:
                    if self.pool.tls:
                        ssl_context = ssl.create_default_context()
                        ssl_context.check_hostname = False
                        ssl_context.verify_mode = ssl.CERT_NONE
                        self.reader, self.writer = await asyncio.wait_for(
                            asyncio.open_connection(self.host, self.port, ssl=ssl_context),
                            timeout=30
                        )
                    else:
                        self.reader, self.writer = await asyncio.wait_for(
                            asyncio.open_connection(self.host, self.port),
                            timeout=30
                        )

                    super().__init__(self.reader, self.writer)
                    self.connected = True
                    logging.info(f"Connected to pool {self.pool.name}")
                    return True

                except Exception as e:
                    logging.error(f"Failed to connect to pool {self.pool.name}: {e}")
                    self.connected = False
                    return False

            async def subscribe(self):
                """Send mining.subscribe to the pool."""
                logging.info("Sending mining.subscribe to pool")
                await self.send_json({
                    "id": 1,
                    "method": "mining.subscribe",
                    "params": ["gpu-proxy/1.0", None]
                })

            async def authorize(self, worker: Optional[str] = None):
                """Send mining.authorize to the pool.

                Args:
                    worker: Optional worker ID to append to wallet (e.g., "krxXVNVMM7.forge-gpu")
                """
                # If worker provided, append to base wallet
                wallet = self.pool.wallet
                if worker:
                    # Extract base wallet (remove .worker if present)
                    base_wallet = wallet.split('.')[0]
                    wallet = f"{base_wallet}.{worker}"

                logging.info(f"Sending mining.authorize to pool with wallet={wallet}")
                await self.send_json({
                    "id": 2,
                    "method": "mining.authorize",
                    "params": [wallet, self.pool.password]
                })

            async def configure(self):
                """Send mining.configure to the pool (if supported)."""
                # Some pools don't support configure, ignore errors
                await self.send_json({
                    "id": 3,
                    "method": "mining.configure",
                    "params": [[]]
                })

            async def submit(self, worker: str, job_id: str, nonce: str, result: str):
                """Submit a share to the pool.

                Args:
                    worker: Full worker name including wallet (e.g., "krxXVNVMM7.forge-gpu")
        """
                await self.send_json({
                    "id": 4,
                    "method": "mining.submit",
                    "params": [worker, job_id, nonce, result]
                })

            def add_subscriber(self, miner):
                """Add a miner connection to receive job updates."""
                if miner not in self.subscribers:
                    self.subscribers.append(miner)

            def remove_subscriber(self, miner):
                """Remove a miner connection."""
                if miner in self.subscribers:
                    self.subscribers.remove(miner)

            async def broadcast(self, message: dict):
                """Broadcast a message to all subscribed miners."""
                for miner in list(self.subscribers):
                    try:
                        await miner.send_from_pool(message)
                    except Exception as e:
                        logging.error(f"Error broadcasting to miner: {e}")
                        self.remove_subscriber(miner)

            async def close(self):
                """Close the pool connection."""
                for miner in list(self.subscribers):
                    self.remove_subscriber(miner)
                if self.writer:
                    await super().close()
                self.connected = False


        class MinerConnection(StratumConnection):
            """Connection from a GPU miner."""

            def __init__(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter,
                        pool: PoolConnection, config: ProxyConfig, addr: tuple):
                super().__init__(reader, writer)
                self.pool = pool
                self.config = config
                self.addr = addr
                self.worker_id: Optional[str] = None
                self.authorized = False

            async def send_from_pool(self, message: dict):
                """Send a message from the pool to this miner."""
                # Rewrite any subscription IDs if needed
                await self.send_json(message)

            async def handle_subscribe(self, request: dict):
                """Handle mining.subscribe from miner."""
                # Return subscription info (standard stratum response)
                # Subscriptions: [ extranonce1, extranonce2_size ]
                await self.send_json({
                    "id": request.get("id"),
                    "result": [
                        [["mining.set_difficulty", "1"], ["mining.notify", "2"]],
                        "deadbeef",  # extranonce1 (placeholder)
                        4  # extranonce2_size
                    ],
                    "error": None
                })
                logging.info(f"Miner subscribed from {self.addr}")

            async def handle_authorize(self, request: dict):
                """Handle mining.authorize from miner."""
                params = request.get("params")
                if not params:
                    await self.send_error(request.get("id"), -1, "No params")
                    return

                # Handle both list format (standard) and dict format (lolMiner "login")
                if isinstance(params, dict):
                    # lolMiner "login" format: {"login": "worker", "pass": "x", "agent": "..."}
                    worker_name = params.get("login", "worker")
                    password = params.get("pass", "x")
                elif isinstance(params, list):
                    # Standard stratum format: ["worker", "pass"]
                    if len(params) < 1:
                        await self.send_error(request.get("id"), -1, "Missing worker name")
                        return
                    worker_name = params[0]
                    password = params[1] if len(params) > 1 else "x"
                else:
                    logging.warning(f"Params has unexpected type: {type(params)}")
                    await self.send_error(request.get("id"), -1, "Invalid params format")
                    return

                # Check if worker is allowed (if whitelist configured)
                if self.config.workers:
                    allowed = False
                    for w in self.config.workers:
                        if w.id == worker_name and w.password == password:
                                allowed = True
                                break
                    if not allowed:
                        await self.send_error(request.get("id"), -1, "Worker not authorized")
                        logging.warning(f"Unauthorized worker: {worker_name}")
                        return

                # Subscribe this miner to pool updates
                self.worker_id = worker_name
                self.authorized = True
                self.pool.add_subscriber(self)

                await self.send_json({
                    "id": request.get("id"),
                    "result": True,
                    "error": None
                })

                logging.info(f"Miner authorized: {worker_name} from {self.addr}")

                # Send current job if available
                if self.pool.job:
                    await self.send_json({
                        "id": None,
                        "method": "mining.notify",
                        "params": self.pool.job["params"]
                    })

            async def handle_submit(self, request: dict):
                """Handle mining.submit from miner."""
                if not self.authorized:
                    await self.send_error(request.get("id"), -1, "Not authorized")
                    return

                params = request.get("params", [])
                if len(params) < 3:
                    await self.send_error(request.get("id"), -1, "Invalid submit params")
                    return

                worker = params[0]
                job_id = params[1]
                nonce = params[2]
                result = params[3] if len(params) > 3 else ""

                # Construct full wallet.worker name for submission
                # Extract base wallet from pool wallet (handles both "krxXVNVMM7" and "krxXVNVMM7.forge")
                base_wallet = self.pool.wallet.split('.')[0]
                original_worker = self.worker_id or worker
                full_worker = f"{base_wallet}.{original_worker}"

                logging.info(f"Submitting share for worker={full_worker}")
                await self.pool.submit(full_worker, job_id, nonce, result)

            async def handle_keepalive(self, request: dict):
                """Handle mining.keepalive (if supported)."""
                await self.send_json({
                    "id": request.get("id"),
                    "result": True,
                    "error": None
                })

            async def send_error(self, msg_id: Optional[int], code: int, message: str):
                """Send an error response."""
                await self.send_json({
                    "id": msg_id,
                    "result": None,
                    "error": [code, message, None]
                })

            async def handle_message(self, message: dict):
                """Handle a message from the miner."""
                method = message.get("method")

                # Log the message for debugging
                if method not in ["mining.notify", "mining.set_difficulty"]:
                    logging.debug(f"Miner message: {message}")

                if method == "mining.subscribe":
                    await self.handle_subscribe(message)
                elif method == "mining.authorize":
                    await self.handle_authorize(message)
                elif method == "login":
                    # lolMiner uses "login" as an alias for "mining.authorize"
                    await self.handle_authorize(message)
                elif method == "mining.submit":
                    await self.handle_submit(message)
                elif method == "mining.keepalive":
                    await self.handle_keepalive(message)
                elif method == "mining.configure":
                    # Ignore configure from miner
                    await self.send_json({
                        "id": message.get("id"),
                        "result": None,
                        "error": None
                    })
                elif method == "mining.suggest_difficulty":
                    # Ignore difficulty suggestions
                    await self.send_json({
                        "id": message.get("id"),
                        "result": None,
                        "error": None
                    })
                else:
                    logging.warning(f"Unknown method from miner: {method}")

            async def close(self):
                """Close the miner connection."""
                if self.pool:
                    self.pool.remove_subscriber(self)
                await super().close()


        class GPUStratumProxy:
            """Main proxy server."""

            def __init__(self, config: ProxyConfig):
                self.config = config
                self.pools: List[PoolConnection] = []
                self.current_pool: Optional[PoolConnection] = None
                self.pool_index = 0
                self.server: Optional[asyncio.Server] = None
                self.running = False
                self.pool_task: Optional[asyncio.Task] = None  # Keep reference to prevent GC

            def sort_pools(self):
                """Sort pools by priority."""
                self.pools.sort(key=lambda p: p.pool.priority)

            async def connect_to_pool(self, pool: PoolConnection) -> bool:
                """Connect to a pool (initialization happens in message loop)."""
                if await pool.connect():
                    pool.initialized = False  # Will be initialized in message loop
                    return True
                return False

            async def connect_to_best_pool(self) -> bool:
                """Try to connect to pools in priority order."""
                for pool in self.pools:
                    if await self.connect_to_pool(pool):
                        self.current_pool = pool
                        logging.info(f"Using pool: {pool.pool.name}")
                        return True
                return False

            async def failover_pool(self):
                """Failover to next available pool."""
                logging.warning("Initiating pool failover...")

                old_pool = self.current_pool
                await old_pool.close() if old_pool else None

                # Try starting from next pool
                for _ in range(len(self.pools)):
                    self.pool_index = (self.pool_index + 1) % len(self.pools)
                    pool = self.pools[self.pool_index]

                    if await self.connect_to_pool(pool):
                        self.current_pool = pool
                        logging.info(f"Failed over to pool: {pool.pool.name}")
                        return

                logging.error("No pools available!")

            async def pool_message_loop(self, pool: PoolConnection):
                """Handle messages from the pool."""
                logging.info(f"Pool message loop started for {pool.pool.name}")

                # Initialize pool connection (subscribe, authorize) now that loop is running
                if not pool.initialized:
                    try:
                        logging.info("Initializing pool connection...")
                        await pool.subscribe()
                        await pool.configure()
                        # Authorize with base wallet only (per-worker auth happens during submit)
                        await pool.authorize(worker=None)
                        pool.initialized = True
                        logging.info("Pool connection initialized")
                    except Exception as e:
                        logging.error(f"Error initializing pool: {e}")
                        await self.failover_pool()
                        return

                try:
                    while pool.connected and self.running:
                        message = await pool.recv_json()
                        if not message:
                            logging.warning(f"Pool {pool.pool.name} disconnected")
                            break

                        method = message.get("method")
                        result = message.get("result")
                        msg_id = message.get("id")

                        # Log all pool responses for debugging
                        if msg_id is not None:
                            logging.info(f"Pool response: id={msg_id}, result={result}, method={method}")

                        if method == "mining.notify":
                            # New job - cache and broadcast
                            pool.job = message
                            await pool.broadcast(message)
                            logging.info(f"New job from {pool.pool.name}")

                        elif method == "mining.set_difficulty":
                            # New difficulty
                            pool.difficulty = message.get("params", [1])[0]
                            await pool.broadcast(message)
                            logging.info(f"Difficulty set to {pool.difficulty}")

                        elif msg_id in [1, 2, 3]:
                            # Response to subscribe/authorize/configure
                            if msg_id == 1:
                                logging.info(f"Pool {pool.pool.name} subscription confirmed")
                            elif msg_id == 2:
                                if result is True:
                                    logging.info(f"Pool {pool.pool.name} authorization successful")
                                else:
                                    logging.error(f"Pool {pool.pool.name} authorization failed: result={result}")

                        elif msg_id == 4:
                            # Response to share submission
                            if result is True:
                                logging.info("Share accepted")
                            else:
                                error = message.get("error", [])
                                logging.warning(f"Share rejected: {error}")

                        # Log any unhandled pool messages
                        if msg_id not in [1, 2, 3, 4] and method not in ["mining.notify", "mining.set_difficulty"]:
                            logging.debug(f"Unhandled pool message: {message}")

                except Exception as e:
                    logging.error(f"Pool message loop error: {e}")
                    logging.error(f"Traceback: {traceback.format_exc()}")
                finally:
                    logging.info(f"Pool message loop ended for {pool.pool.name}")

                # Pool disconnected, try failover
                if self.running:
                    await self.failover_pool()

            async def handle_miner(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
                """Handle a new miner connection."""
                addr = writer.get_extra_info("peername")
                logging.info(f"New miner connection from {addr}")

                if not self.current_pool or not self.current_pool.connected:
                    logging.warning("No pool connected, rejecting miner")
                    writer.close()
                    return

                miner = MinerConnection(reader, writer, self.current_pool, self.config, addr)

                try:
                    while self.running:
                        message = await miner.recv_json()
                        if not message:
                            break
                        await miner.handle_message(message)
                except Exception as e:
                    logging.error(f"Error handling miner: {e}")
                    logging.error(f"Traceback: {traceback.format_exc()}")
                finally:
                    logging.info(f"Miner disconnected from {addr}")
                    await miner.close()

            async def start(self):
                """Start the proxy server."""
                self.running = True

                # Initialize pool connections
                for pool_config in self.config.pools:
                    pool = PoolConnection(pool_config, self.config)
                    self.pools.append(pool)

                self.sort_pools()

                # Connect to best pool
                if not await self.connect_to_best_pool():
                    logging.error("Failed to connect to any pool!")
                    return

                # Start pool message listener (store in self to prevent garbage collection)
                self.pool_task = asyncio.create_task(self.pool_message_loop(self.current_pool))
                logging.info("Pool message loop task created")

                # Start miner listener
                self.server = await asyncio.start_server(
                    self.handle_miner,
                    "0.0.0.0",
                    self.config.listen_port
                )

                logging.info(f"GPU Stratum Proxy listening on port {self.config.listen_port}")
                logging.info(f"API listening on port {self.config.api_port}")

                async with self.server:
                    await self.server.serve_forever()

            async def stop(self):
                """Stop the proxy server."""
                self.running = False

                if self.server:
                    self.server.close()
                    await self.server.wait_closed()

                for pool in self.pools:
                    await pool.close()


        def main():
            parser = argparse.ArgumentParser(description="GPU Mining Stratum Proxy")
            parser.add_argument("--config", required=True, help="Path to config file")
            args = parser.parse_args()

            # Load configuration
            config = ProxyConfig.from_file(args.config)

            # Setup logging
            log_level = getattr(logging, config.log_level.upper(), logging.INFO)
            logging.basicConfig(
                level=log_level,
                    format="%(asctime)s [%(levelname)s] %(message)s",
                    datefmt="%Y-%m-%d %H:%M:%S"
            )

            logging.info("GPU Stratum Proxy starting...")
            logging.info(f"Pools configured: {len(config.pools)}")
            for pool in config.pools:
                logging.info(f"  - {pool.name}: {pool.url}")

            # Run proxy
            proxy = GPUStratumProxy(config)

            try:
                asyncio.run(proxy.start())
            except KeyboardInterrupt:
                logging.info("Shutting down...")
                asyncio.run(proxy.stop())


        if __name__ == "__main__":
            main()
      '';
    };

    propagatedBuildInputs = with pkgs.python3Packages; [
    ];

    dontUnpack = true;
    doCheck = false;

    meta = with lib; {
      description = "GPU mining stratum proxy for CR29 (Tari/Kryptex)";
      license = licenses.mit;
      platforms = platforms.unix;
    };

    postInstall = ''
      mkdir -p $out/bin
      cp $src $out/bin/gpu-proxy
      chmod +x $out/bin/gpu-proxy
    '';
  };

in {
  options.services.gpu-proxy = {
    enable = lib.mkEnableOption "GPU mining stratum proxy for CR29 (Tari/Kryptex)";

    user = lib.mkOption {
      type = lib.types.str;
      default = "gpu-proxy";
      description = "User account to run gpu-proxy";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "gpu-proxy";
      description = "Group account to run gpu-proxy";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/gpu-proxy";
      description = "Data directory for gpu-proxy";
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 3334;
      description = "Stratum port to listen on for GPU miners";
    };

    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 8083;
      description = "API port for monitoring";
    };

    pools = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Pool name (for logging)";
          };
          url = lib.mkOption {
            type = lib.types.str;
            description = "Pool stratum URL (e.g., stratum+tcp://xtm-c29-us.kryptex.network:8040)";
          };
          wallet = lib.mkOption {
            type = lib.types.str;
            description = "Wallet address for pool";
          };
          password = lib.mkOption {
            type = lib.types.str;
            default = "x";
            description = "Pool password";
          };
          priority = lib.mkOption {
            type = lib.types.int;
            default = 1;
            description = "Pool priority (1 = highest)";
          };
          tls = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Use TLS for pool connection";
          };
        };
      });
      description = "List of mining pools with failover configuration";
    };

    workers = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          id = lib.mkOption {
            type = lib.types.str;
            description = "Worker ID (e.g., forge-gpu)";
          };
          password = lib.mkOption {
            type = lib.types.str;
            default = "x";
            description = "Worker password";
          };
        };
      });
      default = [];
      description = "List of allowed worker configurations (empty = allow all)";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall ports for gpu-proxy";
    };

    logLevel = lib.mkOption {
      type = lib.types.str;
      default = "INFO";
      description = "Log level (DEBUG, INFO, WARNING, ERROR)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create user and group
    users.users.${cfg.user} = {
      group = cfg.group;
      isSystemUser = true;
      description = "GPU mining proxy service user";
    };

    users.groups.${cfg.group} = {};

    # Create data directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
    ];

    # Generate config from pools and workers
    environment.etc."gpu-proxy/config.json".text = builtins.toJSON {
      pools = cfg.pools;
      workers = cfg.workers;
      settings = {
        listen_port = cfg.listenPort;
        api_port = cfg.apiPort;
        log_level = cfg.logLevel;
      };
    };

    # Firewall
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.listenPort cfg.apiPort ];
    };

    # Systemd service
    systemd.services.gpu-proxy = {
      description = "GPU Mining Stratum Proxy for CR29 (Tari/Kryptex)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;

        ExecStart = "${gpu-proxy-package}/bin/gpu-proxy --config /etc/gpu-proxy/config.json";

        Restart = "on-failure";
        RestartSec = "10s";

        # Hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir ];

        # Resource limits
        MemoryLimit = "512M";
        CPUQuota = "200%";

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "gpu-proxy";
      };
    };
  };
}
