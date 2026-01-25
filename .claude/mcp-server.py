#!/usr/bin/env python3
"""
Simple MCP Server for Web Search and Tool Integration
Uses requests for HTTP calls and simple JSON-RPC communication
"""

import json
import http.server
import socketserver
import subprocess
import os
import sys
import threading
import time
from urllib.parse import urlparse, parse_qs
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# MCP Server configuration
MCP_PORT = 3000
MCP_HOST = "localhost"

class MCPHandler(http.server.BaseHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        # Initialize the handler with request data
        super().__init__(*args, **kwargs)

    def do_POST(self):
        """Handle MCP requests"""
        try:
            # Get content length and read request body
            content_length = int(self.headers.get('Content-Length', 0))
            request_body = self.rfile.read(content_length).decode('utf-8')
            request_data = json.loads(request_body)

            logger.info(f"Received MCP request: {request_data}")

            # Handle different MCP methods
            method = request_data.get('method', '')
            params = request_data.get('params', {})

            if method == 'tools/list':
                response = self.handle_tools_list()
            elif method == 'tools/call':
                response = self.handle_tool_call(params)
            elif method == 'capabilities':
                response = self.handle_capabilities()
            else:
                response = self.create_error_response(f"Unknown method: {method}")

            # Send response
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode('utf-8'))

        except Exception as e:
            logger.error(f"Error handling request: {e}")
            error_response = self.create_error_response(str(e))
            self.send_response(500)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(error_response).encode('utf-8'))

    def handle_tools_list(self):
        """Return list of available tools"""
        return {
            "id": "1",
            "result": {
                "tools": [
                    {
                        "name": "web-search",
                        "description": "Search the web for current information",
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                "query": {
                                    "type": "string",
                                    "description": "Search query"
                                }
                            },
                            "required": ["query"]
                        }
                    }
                ]
            }
        }

    def handle_tool_call(self, params):
        """Handle tool execution"""
        tool_name = params.get('name', '')
        tool_arguments = params.get('arguments', {})

        if tool_name == 'web-search':
            return self.execute_web_search(tool_arguments)
        else:
            return self.create_error_response(f"Unknown tool: {tool_name}")

    def execute_web_search(self, arguments):
        """Execute web search using curl and DuckDuckGo API"""
        query = arguments.get('query', '')
        if not query:
            return self.create_error_response("Query parameter is required")

        try:
            # Use DuckDuckGo Instant Answer API for web search
            # This is a simple implementation - in production you'd want to use a proper search API
            search_url = f"https://api.duckduckgo.com/?q={query}&format=json&no_html=1&skip_disambig=1"

            # Execute curl command to perform search
            result = subprocess.run([
                'curl', '-s', '-f', '-m', '10', search_url
            ], capture_output=True, text=True, check=True)

            search_data = json.loads(result.stdout)

            # Extract relevant information from search result
            response_text = ""
            if 'AbstractText' in search_data and search_data['AbstractText']:
                response_text = search_data['AbstractText']
            elif 'RelatedTopics' in search_data and search_data['RelatedTopics']:
                # Get first related topic
                first_topic = search_data['RelatedTopics'][0]
                if 'Text' in first_topic:
                    response_text = first_topic['Text']
                elif 'FirstURL' in first_topic:
                    response_text = f"Related: {first_topic['FirstURL']}"
            else:
                response_text = "No relevant information found"

            return {
                "id": "1",
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": response_text
                        }
                    ],
                    "metadata": {
                        "source": "DuckDuckGo",
                        "query": query
                    }
                }
            }

        except subprocess.CalledProcessError as e:
            logger.error(f"Search failed: {e}")
            return self.create_error_response(f"Search failed: {e.stderr}")
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON response: {e}")
            return self.create_error_response("Invalid search response")
        except Exception as e:
            logger.error(f"Unexpected error: {e}")
            return self.create_error_response(f"Unexpected error: {str(e)}")

    def handle_capabilities(self):
        """Return server capabilities"""
        return {
            "id": "1",
            "result": {
                "capabilities": {
                    "tools": True,
                    "web-search": True
                }
            }
        }

    def create_error_response(self, error_message):
        """Create standardized error response"""
        return {
            "id": "1",
            "error": {
                "code": -32600,
                "message": error_message
            }
        }

    def log_message(self, format, *args):
        """Override to use our logger"""
        logger.info(f"{self.address_string()} - {format % args}")

def start_mcp_server():
    """Start the MCP server"""
    try:
        with socketserver.TCPServer((MCP_HOST, MCP_PORT), MCPHandler) as httpd:
            logger.info(f"MCP Server started on {MCP_HOST}:{MCP_PORT}")
            logger.info("Available tools: web-search")
            httpd.serve_forever()
    except KeyboardInterrupt:
        logger.info("MCP Server stopped")
    except Exception as e:
        logger.error(f"Server error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    start_mcp_server()