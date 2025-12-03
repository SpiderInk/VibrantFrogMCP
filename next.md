

1. Preserve the chat when I leave the tab and come back
   1. make a conversation history tab
   2. be able to make a new conversation
   3. be able to continue a previous conversation
2. Be able to add/remove MCP servers
   1. be able to create/edit a prompt to explain how to use an MCP server or its tools
   2. be able to turn on and off MCP servers and individual tools
3. BE able to start indexing and manage the ChromaDB
   1. build our browse_chromadb_web.py into this app
   2. build index faces into the app
4. be able to switch the model we interact with
5. drop the simple chat
6. change the "Search" into direct tool calling of any MCP tool


Before I was interrupted, you were asking about MCP server configuration issues:

Enable each MCP server to have its own address - You wanted the ability to configure different addresses for different MCP servers (not hardcoded to localhost:3000).

Fix the endpoint issue - There was a problem with how endpoints were being constructed or accessed for MCP servers.

Support multiple MCP servers with different configurations - Each MCP server should be able to have its own:

Host/address
Port
Transport type (HTTP, SSE, stdio, etc.)
MCP Server Registry improvements - The MCPServerRegistry.swift needed updates to support per-server configuration.

Connection flexibility - Allow connecting to different MCP servers at different addresses, not just the hardcoded localhost:3000.

However, I should note that the conversation transcript I have access to starts from when you asked me to continue from a previous session. The actual detailed requests about MCP server addresses and endpoint fixes appear to have been in the previous conversation that ran out of context.

Could you clarify what specific changes you wanted regarding:

MCP server addresses (what format/structure)?
The endpoint issue (what was broken)?
How you want to configure multiple MCP servers?
This will help me understand exactly what needs to be implemented.



the user can only interact with ONE mcp server in any particular chat thread
the System prompt in AIChatView.swift must become a template
IN that template there MUST be a dynamic section that fills in the tools that are available.
for example we used to have this section: You have these tools available: - search_photos(query: string, n_results: int) - Search for photos - create_album_from_search(name: string, query: string) - Create album from search - list_albums() - List all albums we need that to come back as a dynamic list of the tools available for the MCP server being used in the current conversation thread


