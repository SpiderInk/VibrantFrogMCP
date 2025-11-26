#!/usr/bin/env python3
"""
Test script to verify MCP Streamable HTTP transport works correctly
"""

import requests
import json
import time

SERVER_URL = "http://127.0.0.1:5050/mcp"

def test_initialize():
    """Test the initialize handshake"""
    print("Testing MCP initialize...")

    request_data = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {
                "roots": {"listChanged": True}
            },
            "clientInfo": {
                "name": "TestClient",
                "version": "1.0.0"
            }
        }
    }

    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream"
    }

    response = requests.post(SERVER_URL, json=request_data, headers=headers)

    print(f"Status: {response.status_code}")
    print(f"Headers: {dict(response.headers)}")

    if response.status_code == 200:
        result = response.json()
        print(f"Response: {json.dumps(result, indent=2)}")

        session_id = response.headers.get('Mcp-Session-Id')
        if session_id:
            print(f"✅ Session ID received: {session_id}")
            return session_id
        else:
            print("⚠️  No session ID in response")
            return None
    else:
        print(f"❌ Failed: {response.text}")
        return None

def test_list_tools(session_id=None):
    """Test listing available tools"""
    print("\nTesting tools/list...")

    request_data = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/list",
        "params": {}
    }

    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream"
    }

    if session_id:
        headers["Mcp-Session-Id"] = session_id

    response = requests.post(SERVER_URL, json=request_data, headers=headers)

    print(f"Status: {response.status_code}")

    if response.status_code == 200:
        result = response.json()
        tools = result.get('result', {}).get('tools', [])
        print(f"✅ Found {len(tools)} tools:")
        for tool in tools[:3]:  # Show first 3
            print(f"  - {tool['name']}: {tool['description']}")
        if len(tools) > 3:
            print(f"  ... and {len(tools) - 3} more")
        return True
    else:
        print(f"❌ Failed: {response.text}")
        return False

def test_search_photos(session_id=None):
    """Test calling search_photos tool"""
    print("\nTesting search_photos tool...")

    request_data = {
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
            "name": "search_photos",
            "arguments": {
                "query": "sunset",
                "n_results": 3
            }
        }
    }

    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream"
    }

    if session_id:
        headers["Mcp-Session-Id"] = session_id

    response = requests.post(SERVER_URL, json=request_data, headers=headers)

    print(f"Status: {response.status_code}")

    if response.status_code == 200:
        result = response.json()
        content = result.get('result', {}).get('content', [])
        print(f"✅ Tool executed successfully")
        for item in content:
            if item.get('type') == 'text':
                print(f"Result preview: {item.get('text', '')[:200]}...")
        return True
    else:
        print(f"❌ Failed: {response.text}")
        return False

if __name__ == "__main__":
    print("=" * 60)
    print("MCP Streamable HTTP Transport Test")
    print("=" * 60)
    print(f"Server: {SERVER_URL}")
    print(f"Make sure the server is running with:")
    print(f"  python vibrant_frog_mcp.py --transport http")
    print("=" * 60)

    # Wait a moment for user to start server if needed
    print("\nStarting tests in 2 seconds...")
    time.sleep(2)

    # Test 1: Initialize
    session_id = test_initialize()

    if session_id:
        # Test 2: List tools
        test_list_tools(session_id)

        # Test 3: Call a tool
        test_search_photos(session_id)

    print("\n" + "=" * 60)
    print("Tests complete!")
    print("=" * 60)
