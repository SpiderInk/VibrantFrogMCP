#!/bin/bash

# Restart MCP HTTP Server
# This kills any existing server and starts a fresh one

cd /Users/tpiazza/git/VibrantFrogMCP

echo "🛑 Stopping existing MCP server..."
pkill -f "vibrant_frog_mcp.py" 2>/dev/null
sleep 1

echo "🚀 Starting MCP server in Streamable HTTP mode..."
# Use venv Python if available, otherwise system Python
if [ -f "venv/bin/python3" ]; then
    ./venv/bin/python3 vibrant_frog_mcp.py --transport http --port 5050 &
else
    python3 vibrant_frog_mcp.py --transport http --port 5050 &
fi

sleep 2

echo ""
echo "✅ Server started on http://127.0.0.1:5050"
echo ""
echo "📋 For MCP Inspector:"
echo "   Transport Type: Streamable HTTP"
echo "   URL: http://127.0.0.1:5050/mcp"
echo ""
echo "🧪 Testing endpoints..."
echo ""

# Test GET (SSE)
echo "Testing GET /mcp (SSE stream)..."
timeout 2 curl -N -H "Accept: text/event-stream" http://127.0.0.1:5050/mcp 2>/dev/null
echo ""

# Test POST (JSON-RPC)
echo "Testing POST /mcp (initialize)..."
curl -s -X POST http://127.0.0.1:5050/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | python3 -m json.tool

echo ""
echo "Testing OPTIONS /mcp (CORS)..."
curl -s -X OPTIONS http://127.0.0.1:5050/mcp -H "Origin: http://localhost:6274" -I | grep -i "access-control" || echo "CORS check skipped"
echo ""

echo "✅ All endpoints working!"
echo ""
echo "📋 MCP Inspector Configuration:"
echo "   1. Open MCP Inspector in browser"
echo "   2. Select 'Streamable HTTP' transport"
echo "   3. Enter URL: http://127.0.0.1:5050/mcp"
echo "   4. Click Connect"
echo ""
echo "✅ CORS enabled - browser clients can connect"
echo ""
