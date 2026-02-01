# Agent Zero Bridge - Openclaw Skill

Bidirectional communication bridge between [Openclaw](https://github.com/openclaw/openclaw) and [Agent Zero](https://github.com/frdel/agent-zero).

## What It Does

```
┌─────────────┐                    ┌─────────────┐
│  Openclaw   │◄──────────────────►│ Agent Zero  │
│  (Claude)   │                    │   (A0)      │
└─────────────┘                    └─────────────┘
```

- **Openclaw → Agent Zero**: Delegate complex coding/research tasks
- **Agent Zero → Openclaw**: Report progress, ask questions, notify completion
- **Task Breakdown**: Break complex tasks into tracked, checkable steps

## Installation

### Option 1: Let Openclaw Install It

Just tell Openclaw:
> "Install the Agent Zero bridge skill"

Or if you have this repo cloned:
> "Install the Agent Zero bridge skill from ~/path/to/this/folder"

### Option 2: Manual Installation

```bash
# Clone or download this repo
git clone https://github.com/DOWingard/Openclaw-Agent0-Bridge.git

# Copy to Openclaw skills directory
cp -r Openclaw-Agent0-Bridge ~/.openclaw/skills/agent-zero-bridge

# Configure
cd ~/.openclaw/skills/agent-zero-bridge
cp .env.example .env
# Edit .env with your API keys (see SKILL.md for details)
```

## Quick Start

After installation, tell Openclaw:
- "Ask Agent Zero to build a REST API"
- "Delegate this coding task to A0"
- "Have Agent Zero review this code"

Or use the CLI directly:
```bash
node ~/.openclaw/skills/agent-zero-bridge/scripts/a0_client.js "Your task here"
```

## File Structure

```
agent-zero-bridge/
├── SKILL.md          # Openclaw skill definition + setup guide
├── .env.example      # Configuration template
├── .gitignore
├── LICENSE           # MIT
├── README.md         # This file
└── scripts/
    ├── a0_client.js        # CLI: Openclaw → Agent Zero
    ├── openclaw_client.js  # CLI: Agent Zero → Openclaw
    ├── task_breakdown.js   # Task breakdown workflow
    └── lib/
        ├── config.js       # Configuration loader
        ├── a0_api.js       # Agent Zero API client
        ├── openclaw_api.js # Openclaw API client
        └── cli.js          # CLI argument parser
```

## Configuration

See `SKILL.md` for detailed setup instructions, including:
- How to get your Agent Zero API token
- Openclaw Gateway configuration
- Docker deployment for bidirectional communication

## Requirements

- Node.js 18+ (for built-in fetch)
- Agent Zero running (Docker recommended)
- Openclaw Gateway with HTTP endpoints enabled

## License

MIT
