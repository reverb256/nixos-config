#!/bin/bash
# OpenClaw Skills Installation Script
# Comprehensive setup for Creative Director + NixOS infrastructure

echo "Installing OpenClaw Skills for Creative Director Workflow..."

# Project Management & Creative Tools
echo "📋 Installing project management skills..."
clawdhub install notion || echo "Notion skill not available"
clawdhub install calendar
clawdhub install figma
clawdhub install trello || echo "Trello skill not available"

# Communication & Email
echo "📧 Installing communication skills..."
clawdhub install himalaya  # Already installed
clawdhub install clippy    # Microsoft 365
clawdhub install meeting-prep

# Development & Infrastructure
echo "💻 Installing development skills..."
clawdhub install coding-agent      # Already installed
clawdhub install agent-zero-bridge # Already installed
clawdhub install relay-to-agent    # Already installed
clawdhub install github            # Already installed
clawdhub install tmux              # Already installed

# Commerce & Business
echo "💼 Installing business skills..."
clawdhub install agent-commerce-engine  # Already installed
clawdhub install blockchain-attestation # Already installed

# Media & Content
echo "🎨 Installing media skills..."
clawdhub install spotify-player    # Already installed
clawdhub install bird              # Already installed (X/Twitter)
clawdhub install camsnap           # Already installed
clawdhub install video-frames      # Already installed
clawdhub install summarize         # Already installed

# Social & Monitoring
echo "📱 Installing social skills..."
clawdhub install blogwatcher || echo "Blogwatcher not available"
clawdhub install weather           # Already installed

# Advanced Features
echo "🚀 Installing advanced skills..."
clawdhub install session-logs      # Already installed
clawdhub install skill-creator     # Already installed
clawdhub install bluebubbles       # Already installed

echo "✅ Skills installation complete!"
echo ""
echo "Next steps:"
echo "1. Configure API keys for external services (Notion, Figma, etc.)"
echo "2. Set up authentication for each skill"
echo "3. Test skill functionality"
echo "4. Create custom skills for specific workflows"
