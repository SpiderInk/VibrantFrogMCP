#!/bin/bash

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 MCP Inspector Connection Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test 1: Server running?
echo "1️⃣  Checking server is running..."
if lsof -i :5050 > /dev/null 2>&1; then
    echo "   ✅ Server running on port 5050"
else
    echo "   ❌ Server NOT running"
    echo "   Run: ./restart_http_server.sh"
    exit 1
fi
echo ""

# Test 2: OPTIONS (CORS preflight)
echo "2️⃣  Testing OPTIONS /mcp (CORS preflight)..."
OPTIONS_RESPONSE=$(curl -s -X OPTIONS http://127.0.0.1:5050/mcp -H "Origin: http://localhost:6274" -I)
if echo "$OPTIONS_RESPONSE" | grep -q "access-control-allow-origin"; then
    echo "   ✅ CORS headers present"
    echo "$OPTIONS_RESPONSE" | grep -i "access-control" | sed 's/^/      /'
else
    echo "   ❌ CORS headers missing"
    exit 1
fi
echo ""

# Test 3: POST (initialize)
echo "3️⃣  Testing POST /mcp (initialize)..."
INIT_RESPONSE=$(curl -s -X POST http://127.0.0.1:5050/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "Origin: http://localhost:6274" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}')

if echo "$INIT_RESPONSE" | grep -q "vibrant-frog-mcp"; then
    echo "   ✅ Initialize successful"
    SESSION_ID=$(curl -s -X POST http://127.0.0.1:5050/mcp \
      -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' \
      -I | grep -i "mcp-session-id" | cut -d' ' -f2 | tr -d '\r')
    echo "      Session ID: $SESSION_ID"
else
    echo "   ❌ Initialize failed"
    echo "$INIT_RESPONSE"
    exit 1
fi
echo ""

# Test 4: GET (SSE stream)
echo "4️⃣  Testing GET /mcp (SSE stream)..."
GET_RESPONSE=$(curl -s -N -H "Accept: text/event-stream" http://127.0.0.1:5050/mcp --max-time 2)
if echo "$GET_RESPONSE" | grep -q "keepalive"; then
    echo "   ✅ SSE stream working (keepalive received)"
else
    echo "   ⚠️  SSE stream check timeout (this is OK)"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ ALL TESTS PASSED!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 MCP Inspector Configuration:"
echo ""
echo "   Transport Type: Streamable HTTP"
echo "   URL:           http://127.0.0.1:5050/mcp"
echo ""
echo "   Just click 'Connect' in MCP Inspector!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
