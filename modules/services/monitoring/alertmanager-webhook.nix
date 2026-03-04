# Alertmanager Webhook Notification Receiver
# Receives alerts from Alertmanager and forwards to multiple channels
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.alertmanager-webhook;
  inherit (lib) mkEnableOption mkOption types mkIf mkIfs;

  pythonEnv = pkgs.python3.withPackages (ps: [ ps.httpx ps.pyyaml ]);
in
{
  options.services.alertmanager-webhook = {
    enable = mkEnableOption "Alertmanager webhook notification receiver";

    port = mkOption {
      type = types.port;
      default = 9095;
      description = "Port for webhook server (default notifications)";
    };

    criticalPort = mkOption {
      type = types.port;
      default = 9094;
      description = "Port for critical alert webhook";
    };

    # Notification channels with secret support
    slackWebhookUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Slack webhook URL (or use slackWebhookUrlFile)";
    };

    slackWebhookUrlFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing Slack webhook URL";
    };

    discordWebhookUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Discord webhook URL (or use discordWebhookUrlFile)";
    };

    discordWebhookUrlFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing Discord webhook URL";
    };

    email = {
      enable = mkEnableOption "Email notifications";

      smtpHost = mkOption {
        type = types.str;
        default = "smtp.gmail.com";
        description = "SMTP server host";
      };

      smtpPort = mkOption {
        type = types.port;
        default = 587;
        description = "SMTP server port";
      };

      from = mkOption {
        type = types.str;
        description = "Email from address";
      };

      to = mkOption {
        type = types.str;
        description = "Email to address";
      };

      username = mkOption {
        type = types.str;
        description = "SMTP username";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing SMTP password";
      };
    };
  };

  config = mkIf cfg.enable {
    systemd.services.alertmanager-webhook = {
      description = "Alertmanager webhook notification receiver";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        User = "alertmanager-webhook";
        Group = "alertmanager-webhook";
        RuntimeDirectory = "alertmanager-webhook";
        ExecStart = pkgs.writers.writeBash "alertmanager-webhook" ''
          set -euo pipefail

          PORT=${toString cfg.port}
          CRITICAL_PORT=${toString cfg.criticalPort}
          HOSTNAME="$$(${pkgs.hostname}/bin/hostname)"

          # Read webhook URLs from secrets if available
          SLACK_WEBHOOK="$$(cat ${lib.optionalString (cfg.slackWebhookUrlFile != null) cfg.slackWebhookUrlFile} 2>/dev/null || echo '')"
          DISCORD_WEBHOOK="$$(cat ${lib.optionalString (cfg.discordWebhookUrlFile != null) cfg.discordWebhookUrlFile} 2>/dev/null || echo '')"
          EMAIL_PASSWORD="$$(cat ${lib.optionalString (cfg.email.enable && cfg.email.passwordFile != null) cfg.email.passwordFile} 2>/dev/null || echo '')"

          ${pkgs.python3}/bin/python3 ${pkgs.writeText "webhook-server.py" ''
            import httpx
            import json
            import os
            import asyncio
            from aiohttp import web
            from datetime import datetime

            PORT = int(os.getenv("PORT", "9095"))
            HOSTNAME = os.getenv("HOSTNAME", "unknown")

            # Notification configuration
            SLACK_WEBHOOK = os.getenv("SLACK_WEBHOOK", "")
            DISCORD_WEBHOOK = os.getenv("DISCORD_WEBHOOK", "")

            EMAIL_ENABLED = os.getenv("EMAIL_ENABLED", "false").lower() == "true"
            EMAIL_SMTP_HOST = os.getenv("EMAIL_SMTP_HOST", "smtp.gmail.com")
            EMAIL_SMTP_PORT = int(os.getenv("EMAIL_SMTP_PORT", "587"))
            EMAIL_FROM = os.getenv("EMAIL_FROM", "")
            EMAIL_TO = os.getenv("EMAIL_TO", "")
            EMAIL_USERNAME = os.getenv("EMAIL_USERNAME", "")
            EMAIL_PASSWORD = os.getenv("EMAIL_PASSWORD", "")

            async def send_slack(alert):
                if not SLACK_WEBHOOK:
                    return False
                color = "#FF0000" if alert["status"] == "firing" else "#00FF00"
                blocks = [
                    {
                        "type": "header",
                        "text": {
                            "type": "plain_text",
                            "text": f":rotating_light: Alert - {alert['labels'].get('severity', 'info').upper()}",
                        }
                    },
                    {
                        "type": "section",
                        "fields": [
                            {
                                "type": "mrkdwn",
                                "title": "Alert",
                                "value": f"*{alert['labels'].get('alertname', 'Unknown')}*"
                            },
                            {
                                "type": "mrkdwn",
                                "title": "Severity",
                                "value": alert["labels"].get("severity", "info")
                            },
                            {
                                "type": "mrkdwn",
                                "title": "Host",
                                "value": alert["labels"].get("host", alert["labels"].get("instance", "unknown"))
                            },
                            {
                                "type": "mrkdwn",
                                "title": "Status",
                                "value": alert["status"].upper()
                            }
                        ]
                    },
                    {
                        "type": "section",
                        "text": {
                            "type": "mrkdwn",
                            "text": alert["annotations"].get("description", alert["annotations"].get("summary", "No description"))
                        }
                    }
                ]
                try:
                    async with httpx.AsyncClient() as client:
                        await client.post(SLACK_WEBHOOK, json=blocks, timeout=10)
                    return True
                except Exception as e:
                    print(f"Slack error: {e}")
                    return False

            async def send_discord(alert):
                if not DISCORD_WEBHOOK:
                    return False
                color = 0xFF0000 if alert["status"] == "firing" else 0x00FF00
                embed = {
                    "title": f":rotating_light: Alert - {alert['labels'].get('severity', 'info').upper()}",
                    "description": alert["annotations"].get("description", alert["annotations"].get("summary", "No description")),
                    "color": color,
                    "fields": [
                        {
                            "name": "Alert",
                            "value": alert["labels"].get("alertname", "Unknown"),
                            "inline": True
                        },
                        {
                            "name": "Severity",
                            "value": alert["labels"].get("severity", "info"),
                            "inline": True
                        },
                        {
                            "name": "Host",
                            "value": alert["labels"].get("host", alert["labels"].get("instance", "unknown")),
                            "inline": True
                        },
                        {
                            "name": "Status",
                            "value": alert["status"].upper(),
                            "inline": True
                        }
                    ],
                    "timestamp": alert["startsAt"],
                    "footer": {"text": HOSTNAME}
                }
                try:
                    async with httpx.AsyncClient() as client:
                        await client.post(DISCORD_WEBHOOK, json=embeds=[embed], timeout=10)
                    return True
                except Exception as e:
                    print(f"Discord error: {e}")
                    return False

            async def send_email(alert):
                if not EMAIL_ENABLED or not EMAIL_FROM or not EMAIL_TO:
                    return False
                import smtplib
                from email.message import EmailMessage
                from email.utils import formataddr

                status_icon = "🚨" if alert["status"] == "firing" else "✅"
                subject = f"{status_icon} [{alert['labels'].get('severity', 'info').upper()}] {alert['labels'].get('alertname', 'Unknown')}"

                body = f"""
                Alert Details:
                --------------
                Alert: {alert['labels'].get('alertname', 'Unknown')}
                Severity: {alert['labels'].get('severity', 'info')}
                Status: {alert['status'].upper()}
                Host: {alert['labels'].get('host', alert['labels'].get('instance', 'unknown'))}

                Description:
                {alert['annotations'].get('description', alert['annotations'].get('summary', 'No description'))}

                Started: {alert['startsAt']}
                """
                msg = EmailMessage()
                msg["From"] = formataddr(("Reverb-OS Alerts", EMAIL_FROM))
                msg["To"] = EMAIL_TO
                msg["Subject"] = subject
                msg.set_content(body)

                try:
                    with smtplib.SMTP(EMAIL_SMTP_HOST, EMAIL_SMTP_PORT) as server:
                        server.starttls()
                        server.login(EMAIL_USERNAME, EMAIL_PASSWORD)
                        server.send_message(msg)
                    return True
                except Exception as e:
                    print(f"Email error: {e}")
                    return False

            async def handle_alert(request):
                try:
                    data = await request.json()
                    alerts = data.get("alerts", [])
                    print(f"Received {len(alerts)} alert(s)")

                    for alert in alerts:
                        severity = alert["labels"].get("severity", "info")

                        # Send to all configured channels
                        tasks = []
                        if severity in ["critical", "warning", "info"]:
                            tasks.append(send_slack(alert))
                            tasks.append(send_discord(alert))
                        if EMAIL_ENABLED:
                            tasks.append(send_email(alert))

                        # Wait for all notifications
                        results = await asyncio.gather(*tasks, return_exceptions=True)
                        success_count = sum(1 for r in results if r is True)
                        print(f"Sent {success_count}/{len(tasks)} notifications")

                except Exception as e:
                    print(f"Error handling alert: {e}")
                return web.Response(text="OK", status=200)

            async def handle_health(request):
                return web.Response(text="OK", status=200)

            app = web.Application()
            app.add_routes([
                web.post("/api/v1/alerts", handle_alert),
                web.get("/health", handle_health),
            ])

            if __name__ == "__main__":
                print(f"Starting webhook server on port {PORT}")
                print(f"Slack: {'enabled' if SLACK_WEBHOOK else 'disabled'}")
                print(f"Discord: {'enabled' if DISCORD_WEBHOOK else 'disabled'}")
                print(f"Email: {'enabled' if EMAIL_ENABLED else 'disabled'}")
                web.run_app(app, host="127.0.0.1", port=PORT)
          ''} --replace | ${pythonEnv}/bin/python3
        '';

        Restart = "on-failure";
        RestartSec = "10s";
        StandardOutput = "journal";
        StandardError = "journal";

        Environment = [
          "PORT=${toString cfg.port}"
          "HOSTNAME=${config.networking.hostName}"
          ${lib.optionalString (cfg.slackWebhookUrlFile != null) "SLACK_WEBHOOK=$(cat ${cfg.slackWebhookUrlFile})"}
          ${lib.optionalString (cfg.discordWebhookUrlFile != null) "DISCORD_WEBHOOK=$(cat ${cfg.discordWebhookUrlFile})"}
          ${lib.optionalString cfg.email.enable "EMAIL_ENABLED=true"}
          ${lib.optionalString cfg.email.enable "EMAIL_SMTP_HOST=${cfg.email.smtpHost}"}
          ${lib.optionalString cfg.email.enable "EMAIL_SMTP_PORT=${toString cfg.email.smtpPort}"}
          ${lib.optionalString cfg.email.enable "EMAIL_FROM=${cfg.email.from}"}
          ${lib.optionalString cfg.email.enable "EMAIL_TO=${cfg.email.to}"}
          ${lib.optionalString cfg.email.enable "EMAIL_USERNAME=${cfg.email.username}"}
          ${lib.optionalString (cfg.email.enable && cfg.email.passwordFile != null) "EMAIL_PASSWORD=$(cat ${cfg.email.passwordFile})"}
        ];

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        CapabilityBoundingSet = [ "" ];
      };
    };

    # Critical webhook server (for critical alerts only)
    systemd.services.alertmanager-webhook-critical = {
      description = "Alertmanager critical alert webhook receiver";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        User = "alertmanager-webhook";
        Group = "alertmanager-webhook";
        RuntimeDirectory = "alertmanager-webhook";
        ExecStart = pkgs.writers.writeBash "alertmanager-webhook-critical" ''
          set -euo pipefail

          CRITICAL_PORT=${toString cfg.criticalPort}
          HOSTNAME="$$(${pkgs.hostname}/bin/hostname)"

          # Read webhook URLs from secrets if available
          SLACK_WEBHOOK="$$(cat ${lib.optionalString (cfg.slackWebhookUrlFile != null) cfg.slackWebhookUrlFile} 2>/dev/null || echo '')"
          DISCORD_WEBHOOK="$$(cat ${lib.optionalString (cfg.discordWebhookUrlFile != null) cfg.discordWebhookUrlFile} 2>/dev/null || echo '')"
          EMAIL_PASSWORD="$$(cat ${lib.optionalString (cfg.email.enable && cfg.email.passwordFile != null) cfg.email.passwordFile} 2>/dev/null || echo '')"

          ${pkgs.python3}/bin/python3 ${pkgs.writeText "webhook-server-critical.py" ''
            import httpx
            import json
            import os
            from aiohttp import web
            from datetime import datetime

            PORT = int(os.getenv("PORT", "9094"))
            HOSTNAME = os.getenv("HOSTNAME", "unknown")

            # Notification configuration (same as default)
            SLACK_WEBHOOK = os.getenv("SLACK_WEBHOOK", "")
            DISCORD_WEBHOOK = os.getenv("DISCORD_WEBHOOK", "")

            EMAIL_ENABLED = os.getenv("EMAIL_ENABLED", "false").lower() == "true"
            EMAIL_SMTP_HOST = os.getenv("EMAIL_SMTP_HOST", "smtp.gmail.com")
            EMAIL_SMTP_PORT = int(os.getenv("EMAIL_SMTP_PORT", "587"))
            EMAIL_FROM = os.getenv("EMAIL_FROM", "")
            EMAIL_TO = os.getenv("EMAIL_TO", "")
            EMAIL_USERNAME = os.getenv("EMAIL_USERNAME", "")
            EMAIL_PASSWORD = os.getenv("EMAIL_PASSWORD", "")

            # Same send functions as default webhook
            async def send_slack(alert):
                if not SLACK_WEBHOOK:
                    return False
                color = "#FF0000"
                blocks = [
                    {
                        "type": "header",
                        "text": {
                            "type": "plain_text",
                            "text": f":rotating_light: CRITICAL ALERT",
                        }
                    },
                    {
                        "type": "section",
                        "fields": [
                            {
                                "type": "mrkdwn",
                                "title": "Alert",
                                "value": f"*{alert['labels'].get('alertname', 'Unknown')}*"
                            },
                            {
                                "type": "mrkdwn",
                                "title": "Host",
                                "value": alert["labels"].get("host", alert["labels"].get("instance", "unknown"))
                            },
                            {
                                "type": "mrkdwn",
                                "title": "Description",
                                "value": alert["annotations"].get("description", "No description")
                            }
                        ]
                    }
                ]
                try:
                    async with httpx.AsyncClient() as client:
                        await client.post(SLACK_WEBHOOK, json=blocks, timeout=10)
                    return True
                except Exception as e:
                    print(f"Slack error: {e}")
                    return False

            async def send_discord(alert):
                if not DISCORD_WEBHOOK:
                    return False
                color = 0xFF0000
                embed = {
                    "title": ":rotating_light: CRITICAL ALERT",
                    "description": alert["annotations"].get("description", "No description"),
                    "color": color,
                    "fields": [
                        {
                            "name": "Alert",
                            "value": alert["labels"].get("alertname", "Unknown"),
                            "inline": True
                        },
                        {
                            "name": "Host",
                            "value": alert["labels"].get("host", alert["labels"].get("instance", "unknown")),
                            "inline": True
                        }
                    ],
                    "footer": {"text": f"{HOSTNAME} - CRITICAL"}
                }
                try:
                    async with httpx.AsyncClient() as client:
                        await client.post(DISCORD_WEBHOOK, json=embeds=[embed], timeout=10)
                    return True
                except Exception as e:
                    print(f"Discord error: {e}")
                    return False

            async def send_email(alert):
                if not EMAIL_ENABLED or not EMAIL_FROM or not EMAIL_TO:
                    return False
                import smtplib
                from email.message import EmailMessage
                from email.utils import formataddr

                subject = f"🚨 CRITICAL: {alert['labels'].get('alertname', 'Unknown')}"

                body = f"""
                CRITICAL ALERT
                --------------
                Alert: {alert['labels'].get('alertname', 'Unknown')}
                Host: {alert['labels'].get('host', alert['labels'].get('instance', 'unknown'))}

                Description:
                {alert['annotations'].get('description', 'No description')}

                Started: {alert['startsAt']}
                """
                msg = EmailMessage()
                msg["From"] = formataddr(("Reverb-OS CRITICAL Alerts", EMAIL_FROM))
                msg["To"] = EMAIL_TO
                msg["Subject"] = subject
                msg.set_content(body)

                try:
                    with smtplib.SMTP(EMAIL_SMTP_HOST, EMAIL_SMTP_PORT) as server:
                        server.starttls()
                        server.login(EMAIL_USERNAME, EMAIL_PASSWORD)
                        server.send_message(msg)
                    return True
                except Exception as e:
                    print(f"Email error: {e}")
                    return False

            async def handle_alert(request):
                try:
                    data = await request.json()
                    alerts = data.get("alerts", [])
                    print(f"Received {len(alerts)} critical alert(s)")

                    for alert in alerts:
                        tasks = []
                        if SLACK_WEBHOOK:
                            tasks.append(send_slack(alert))
                        if DISCORD_WEBHOOK:
                            tasks.append(send_discord(alert))
                        if EMAIL_ENABLED:
                            tasks.append(send_email(alert))

                        results = await asyncio.gather(*tasks, return_exceptions=True)
                        success_count = sum(1 for r in results if r is True)
                        print(f"Sent {success_count}/{len(tasks)} critical notifications")

                except Exception as e:
                    print(f"Error handling alert: {e}")
                return web.Response(text="OK", status=200)

            async def handle_health(request):
                return web.Response(text="OK", status=200)

            app = web.Application()
            app.add_routes([
                web.post("/api/v1/alerts", handle_alert),
                web.get("/health", handle_health),
            ])

            if __name__ == "__main__":
                print(f"Starting critical webhook server on port {PORT}")
                web.run_app(app, host="127.0.0.1", port=PORT)
          ''} --replace | ${pythonEnv}/bin/python3
        '';

        Restart = "on-failure";
        RestartSec = "10s";
        StandardOutput = "journal";
        StandardError = "journal";

        Environment = [
          "PORT=${toString cfg.criticalPort}"
          "HOSTNAME=${config.networking.hostName}"
          ${lib.optionalString (cfg.slackWebhookUrlFile != null) "SLACK_WEBHOOK=$(cat ${cfg.slackWebhookUrlFile})"}
          ${lib.optionalString (cfg.discordWebhookUrlFile != null) "DISCORD_WEBHOOK=$(cat ${cfg.discordWebhookUrlFile})"}
          ${lib.optionalString cfg.email.enable "EMAIL_ENABLED=true"}
          ${lib.optionalString cfg.email.enable "EMAIL_SMTP_HOST=${cfg.email.smtpHost}"}
          ${lib.optionalString cfg.email.enable "EMAIL_SMTP_PORT=${toString cfg.email.smtpPort}"}
          ${lib.optionalString cfg.email.enable "EMAIL_FROM=${cfg.email.from}"}
          ${lib.optionalString cfg.email.enable "EMAIL_TO=${cfg.email.to}"}
          ${lib.optionalString cfg.email.enable "EMAIL_USERNAME=${cfg.email.username}"}
          ${lib.optionalString (cfg.email.enable && cfg.email.passwordFile != null) "EMAIL_PASSWORD=$(cat ${cfg.email.passwordFile})"}
        ];

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        CapabilityBoundingSet = [ "" ];
      };
    };

    users.users.alertmanager-webhook = {
      isSystemUser = true;
      group = "alertmanager-webhook";
      description = "Alertmanager webhook notification receiver";
    };
    users.groups.alertmanager-webhook = { };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
      cfg.port
      cfg.criticalPort
    ];
  };
}
