#!/usr/bin/env python3
"""
Simple web UI for browsing ChromaDB photo index
"""
import chromadb
import os
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
from urllib.parse import parse_qs, urlparse

DB_PATH = os.path.expanduser("~/Library/Application Support/VibrantFrogMCP/photo_index")
chroma_client = chromadb.PersistentClient(path=DB_PATH)
collection = chroma_client.get_collection(name="photos")

class BrowserHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        
        if parsed.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            
            html = """
            <!DOCTYPE html>
            <html>
            <head>
                <title>Photo Index Browser</title>
                <style>
                    body { font-family: Arial, sans-serif; max-width: 1200px; margin: 50px auto; padding: 20px; }
                    .search { margin-bottom: 20px; }
                    input[type="text"] { width: 70%; padding: 10px; font-size: 16px; }
                    button { padding: 10px 20px; font-size: 16px; }
                    .photo { border: 1px solid #ddd; padding: 15px; margin: 10px 0; border-radius: 5px; }
                    .photo h3 { margin-top: 0; }
                    .meta { color: #666; font-size: 14px; }
                    .description { margin-top: 10px; font-style: italic; }
                    .stats { background: #f0f0f0; padding: 10px; border-radius: 5px; margin-bottom: 20px; }
                </style>
            </head>
            <body>
                <h1>📷 Photo Index Browser</h1>
                <div class="stats" id="stats">Loading...</div>
                
                <div class="search">
                    <input type="text" id="query" placeholder="Search photos..." />
                    <button onclick="search()">Search</button>
                    <button onclick="loadAll()">Show All</button>
                </div>
                
                <div id="results"></div>
                
                <script>
                    async function search() {
                        const query = document.getElementById('query').value;
                        const response = await fetch('/api/search?q=' + encodeURIComponent(query));
                        const data = await response.json();

                        // Check for error
                        if (data.error) {
                            document.getElementById('results').innerHTML =
                                `<div style="color: red; padding: 20px; background: #fee;">
                                    <strong>Search Error:</strong><br>
                                    ${data.message}<br><br>
                                    <strong>Technical details:</strong> ${data.error}<br><br>
                                    <em>Solution: Re-index your photos to rebuild the search index.</em>
                                </div>`;
                            return;
                        }

                        displayResults(data);
                    }
                    
                    async function loadAll() {
                        const response = await fetch('/api/all');
                        const data = await response.json();
                        displayResults(data);
                    }
                    
                    async function loadStats() {
                        const response = await fetch('/api/stats');
                        const data = await response.json();
                        document.getElementById('stats').innerHTML = 
                            `Total indexed photos: <strong>${data.count}</strong>`;
                    }
                    
                    function displayResults(data) {
                        const div = document.getElementById('results');
                        if (data.length === 0) {
                            div.innerHTML = '<p>No results found.</p>';
                            return;
                        }
                        
                        div.innerHTML = data.map((photo, i) => `
                            <div class="photo">
                                <h3>${i+1}. ${photo.filename}</h3>
                                <div class="meta">
                                    <strong>UUID:</strong> ${photo.uuid}<br>
                                    <strong>Path:</strong> ${photo.path || 'N/A'}<br>
                                    ${photo.path_edited ? `<strong>Edited Path:</strong> ${photo.path_edited}<br>` : ''}
                                    <strong>Date:</strong> ${photo.date || 'N/A'}<br>
                                    <strong>Location:</strong> ${photo.location || 'N/A'}<br>
                                    <strong>Dimensions:</strong> ${photo.width}x${photo.height} (${photo.orientation})<br>
                                    <strong>iCloud:</strong> ${photo.cloud_asset ? 'Yes ☁️' : 'No (local)'}<br>
                                    <strong>Albums:</strong> ${photo.albums || 'None'}<br>
                                    <strong>Keywords:</strong> ${photo.keywords || 'None'}<br>
                                    ${photo.relevance ? `<strong>Relevance:</strong> ${photo.relevance.toFixed(2)}<br>` : ''}
                                </div>
                                <div class="description">${photo.description}</div>
                            </div>
                        `).join('');
                    }
                    
                    // Load stats on page load
                    loadStats();
                    loadAll();
                    
                    // Allow Enter key to search
                    document.getElementById('query').addEventListener('keypress', (e) => {
                        if (e.key === 'Enter') search();
                    });
                </script>
            </body>
            </html>
            """
            self.wfile.write(html.encode())
            
        elif parsed.path == '/api/stats':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            count = collection.count()
            self.wfile.write(json.dumps({'count': count}).encode())
            
        elif parsed.path.startswith('/api/search'):
            query_params = parse_qs(parsed.query)
            query = query_params.get('q', [''])[0]

            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()

            try:
                results = collection.query(
                    query_texts=[query],
                    n_results=20,
                    include=['metadatas', 'documents', 'distances']
                )
            except Exception as e:
                # If vector search fails, return error
                import sys
                print(f"Search error: {e}", file=sys.stderr)
                self.wfile.write(json.dumps({
                    'error': str(e),
                    'message': 'Vector search failed. Try reindexing or use "Show All" instead.'
                }).encode())
                return
            
            photos = []
            for id, doc, meta, dist in zip(
                results['ids'][0],
                results['documents'][0],
                results['metadatas'][0],
                results['distances'][0]
            ):
                photos.append({
                    'uuid': id,
                    'filename': meta.get('filename', 'Unknown'),
                    'path': meta.get('path'),
                    'path_edited': meta.get('path_edited'),
                    'date': meta.get('date'),
                    'location': meta.get('location'),
                    'albums': meta.get('albums', ''),
                    'keywords': meta.get('keywords', ''),
                    'width': meta.get('width'),
                    'height': meta.get('height'),
                    'orientation': meta.get('orientation', 'unknown'),
                    'cloud_asset': meta.get('cloud_asset', False),
                    'description': doc,
                    'relevance': 1 - dist
                })
            
            self.wfile.write(json.dumps(photos).encode())
            
        elif parsed.path == '/api/all':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            results = collection.get(
                limit=50,
                include=['metadatas', 'documents']
            )
            
            photos = []
            for id, doc, meta in zip(results['ids'], results['documents'], results['metadatas']):
                photos.append({
                    'uuid': id,
                    'filename': meta.get('filename', 'Unknown'),
                    'path': meta.get('path'),
                    'path_edited': meta.get('path_edited'),
                    'date': meta.get('date'),
                    'location': meta.get('location'),
                    'albums': meta.get('albums', ''),
                    'keywords': meta.get('keywords', ''),
                    'width': meta.get('width'),
                    'height': meta.get('height'),
                    'orientation': meta.get('orientation', 'unknown'),
                    'cloud_asset': meta.get('cloud_asset', False),
                    'description': doc
                })
            
            self.wfile.write(json.dumps(photos).encode())
    
    def log_message(self, format, *args):
        pass  # Suppress logs

if __name__ == '__main__':
    port = 8080
    server = HTTPServer(('localhost', port), BrowserHandler)
    print(f"🌐 Photo Index Browser running at http://localhost:{port}")
    print("Press Ctrl+C to stop")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()