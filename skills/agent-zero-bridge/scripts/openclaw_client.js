#!/usr/bin/env node
/**
 * Openclaw Client - For Agent Zero to call Openclaw
 * 
 * Usage:
 *   node openclaw_client.js <message>
 *   node openclaw_client.js message <text>
 *   node openclaw_client.js notify <text>
 *   node openclaw_client.js tool <name> <json>
 * 
 * Environment:
 *   OPENCLAW_API_URL   - Gateway URL (default: http://127.0.0.1:18789)
 *   OPENCLAW_API_TOKEN - Gateway auth token (required)
 *   DOCKER_CONTAINER   - Set to "true" if running inside Docker
 */

const OpenclawClient = require('./lib/openclaw_api');
const { parseArgs } = require('./lib/cli');

const HELP = `
Openclaw Client (Agent Zero → Openclaw)

Usage:
  node openclaw_client.js <message>
  node openclaw_client.js message <text>    - Send message, get response
  node openclaw_client.js notify <text>     - Send notification
  node openclaw_client.js tool <name> <json> - Invoke a Openclaw tool

Environment:
  OPENCLAW_API_URL       - Gateway URL (default: http://127.0.0.1:18789)
  OPENCLAW_API_URL_DOCKER - URL when running in Docker (use host IP)
  OPENCLAW_API_TOKEN     - Gateway auth token (required)
  DOCKER_CONTAINER       - Set to "true" if running inside Docker

Examples:
  node openclaw_client.js "Task complete!"
  node openclaw_client.js notify "Progress: 50%"
  node openclaw_client.js tool sessions_list '{}'
`;

async function main() {
    const parsed = parseArgs(process.argv.slice(2));
    const commands = ['message', 'notify', 'tool', 'help'];
    
    // Default to message if command not recognized
    if (parsed.command && !commands.includes(parsed.command)) {
        parsed.args.unshift(parsed.command);
        parsed.command = 'message';
    }

    if (!parsed.command || parsed.command === 'help' || parsed.options.help) {
        console.log(HELP);
        return;
    }

    const client = new OpenclawClient();

    try {
        let result;
        const text = parsed.args.join(' ');

        switch (parsed.command) {
            case 'message':
                if (!text) {
                    console.error("Error: Provide a message");
                    process.exit(1);
                }
                result = await client.sendMessage(text, { 
                    prefix: '[FROM AGENT ZERO]',
                    timeout: parsed.options.timeout 
                });
                break;

            case 'notify':
                if (!text) {
                    console.error("Error: Provide a notification");
                    process.exit(1);
                }
                result = await client.notify(text);
                result = typeof result === 'string' ? result : JSON.stringify(result, null, 2);
                break;

            case 'tool':
                const toolName = parsed.args[0];
                if (!toolName) {
                    console.error("Error: Provide tool name");
                    process.exit(1);
                }
                const toolArgs = parsed.args[1] ? JSON.parse(parsed.args[1]) : {};
                result = await client.invokeTool(toolName, toolArgs);
                result = JSON.stringify(result, null, 2);
                break;

            default:
                console.error(`Unknown command: ${parsed.command}`);
                process.exit(1);
        }

        console.log(result);

    } catch (error) {
        console.error(`Error: ${error.message}`);
        process.exit(1);
    }
}

main();
