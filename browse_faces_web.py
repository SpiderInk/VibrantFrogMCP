#!/usr/bin/env python3
"""
Web UI for browsing and labeling face clusters
"""
import chromadb
import os
import base64
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
from urllib.parse import parse_qs, urlparse
from collections import defaultdict
import cv2

DB_PATH = os.path.expanduser("~/Library/Application Support/VibrantFrogMCP/photo_index")
chroma_client = chromadb.PersistentClient(path=DB_PATH)

try:
    faces_collection = chroma_client.get_collection(name="faces")
    photos_collection = chroma_client.get_collection(name="photos")
except:
    print("Error: Collections not found. Please run index_faces.py first.")
    exit(1)

def get_face_thumbnail(photo_path, bbox, size=(150, 150)):
    """Extract and encode face thumbnail from photo"""
    try:
        # Handle HEIC
        if photo_path.lower().endswith('.heic') or photo_path.lower().endswith('.heif'):
            import tempfile
            import subprocess
            temp_dir = tempfile.mkdtemp()
            jpeg_path = os.path.join(temp_dir, 'temp.jpg')
            subprocess.run(['sips', '-s', 'format', 'jpeg', photo_path, '--out', jpeg_path],
                          capture_output=True, timeout=10)
            if os.path.exists(jpeg_path):
                photo_path = jpeg_path
            else:
                return None

        img = cv2.imread(photo_path)
        if img is None:
            return None

        # Extract face region
        x, y, w, h = bbox['bbox_x'], bbox['bbox_y'], bbox['bbox_w'], bbox['bbox_h']

        # Add padding (20%)
        padding = int(max(w, h) * 0.2)
        x = max(0, x - padding)
        y = max(0, y - padding)
        w = min(img.shape[1] - x, w + 2*padding)
        h = min(img.shape[0] - y, h + 2*padding)

        face_img = img[y:y+h, x:x+w]

        # Resize to thumbnail
        face_img = cv2.resize(face_img, size)

        # Encode to base64
        _, buffer = cv2.imencode('.jpg', face_img)
        img_base64 = base64.b64encode(buffer).decode('utf-8')

        return img_base64
    except Exception as e:
        print(f"Error creating thumbnail: {e}")
        return None

class FaceBrowserHandler(BaseHTTPRequestHandler):
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
                <title>Face Cluster Browser</title>
                <style>
                    body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
                    h1 { color: #333; }
                    .controls { background: white; padding: 20px; margin-bottom: 20px; border-radius: 8px; }
                    .cluster { background: white; margin: 20px 0; padding: 20px; border-radius: 8px; }
                    .cluster-header {
                        display: flex;
                        justify-content: space-between;
                        align-items: center;
                        margin-bottom: 15px;
                        padding-bottom: 10px;
                        border-bottom: 2px solid #eee;
                    }
                    .cluster-info { font-size: 18px; font-weight: bold; }
                    .label-input {
                        display: flex;
                        gap: 10px;
                        align-items: center;
                    }
                    .label-input input {
                        padding: 8px;
                        border: 1px solid #ddd;
                        border-radius: 4px;
                        font-size: 14px;
                    }
                    .label-input button {
                        padding: 8px 16px;
                        background: #4CAF50;
                        color: white;
                        border: none;
                        border-radius: 4px;
                        cursor: pointer;
                    }
                    .label-input button:hover { background: #45a049; }
                    .faces-grid {
                        display: grid;
                        grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
                        gap: 15px;
                    }
                    .face-item {
                        text-align: center;
                        background: #fafafa;
                        padding: 10px;
                        border-radius: 4px;
                    }
                    .face-item img {
                        width: 150px;
                        height: 150px;
                        object-fit: cover;
                        border-radius: 4px;
                        border: 2px solid #ddd;
                    }
                    .face-item small {
                        display: block;
                        margin-top: 5px;
                        color: #666;
                        font-size: 11px;
                    }
                    .stats {
                        background: #e3f2fd;
                        padding: 15px;
                        border-radius: 4px;
                        margin-bottom: 20px;
                    }
                    .outliers { opacity: 0.6; }
                    .filter-controls { margin: 15px 0; }
                    .filter-controls label { margin-right: 15px; }
                    .current-label {
                        color: #4CAF50;
                        font-style: italic;
                        margin-left: 10px;
                    }
                </style>
            </head>
            <body>
                <h1>👥 Face Cluster Browser</h1>

                <div class="stats" id="stats">Loading...</div>

                <div class="controls">
                    <div class="filter-controls">
                        <label>
                            <input type="checkbox" id="hideOutliers" checked onchange="loadClusters()">
                            Hide outliers (single faces)
                        </label>
                        <label>
                            <input type="checkbox" id="hideLabeledOnly" onchange="loadClusters()">
                            Show only unlabeled clusters
                        </label>
                        <label>
                            Min cluster size:
                            <input type="number" id="minSize" value="3" min="2" onchange="loadClusters()" style="width: 60px;">
                        </label>
                    </div>
                </div>

                <div id="clusters"></div>

                <script>
                    async function loadStats() {
                        const response = await fetch('/api/stats');
                        const data = await response.json();
                        document.getElementById('stats').innerHTML = `
                            <strong>Total faces:</strong> ${data.total_faces} |
                            <strong>Clusters:</strong> ${data.num_clusters} |
                            <strong>Labeled:</strong> ${data.labeled_clusters} |
                            <strong>Outliers:</strong> ${data.outliers}
                        `;
                    }

                    async function loadClusters() {
                        const hideOutliers = document.getElementById('hideOutliers').checked;
                        const hideLabeledOnly = document.getElementById('hideLabeledOnly').checked;
                        const minSize = document.getElementById('minSize').value;

                        const response = await fetch(
                            `/api/clusters?hide_outliers=${hideOutliers}&unlabeled_only=${hideLabeledOnly}&min_size=${minSize}`
                        );
                        const clusters = await response.json();

                        const div = document.getElementById('clusters');
                        if (clusters.length === 0) {
                            div.innerHTML = '<p>No clusters to display.</p>';
                            return;
                        }

                        div.innerHTML = clusters.map(cluster => `
                            <div class="cluster ${cluster.cluster_id === -1 ? 'outliers' : ''}">
                                <div class="cluster-header">
                                    <div class="cluster-info">
                                        Cluster ${cluster.cluster_id}
                                        <span style="color: #666; font-size: 14px; font-weight: normal;">
                                            (${cluster.size} faces)
                                        </span>
                                        ${cluster.label ? `<span class="current-label">→ ${cluster.label}</span>` : ''}
                                    </div>
                                    ${cluster.cluster_id !== -1 ? `
                                        <div class="label-input">
                                            <input type="text"
                                                   id="label_${cluster.cluster_id}"
                                                   placeholder="Enter person's name"
                                                   value="${cluster.label || ''}" />
                                            <button onclick="saveLabel(${cluster.cluster_id})">
                                                ${cluster.label ? 'Update' : 'Save'} Label
                                            </button>
                                        </div>
                                    ` : ''}
                                </div>
                                <div class="faces-grid">
                                    ${cluster.faces.map(face => `
                                        <div class="face-item">
                                            <img src="data:image/jpeg;base64,${face.thumbnail}"
                                                 alt="Face"
                                                 title="${face.photo_uuid}" />
                                            <small>conf: ${(face.confidence * 100).toFixed(0)}%</small>
                                        </div>
                                    `).join('')}
                                </div>
                            </div>
                        `).join('');
                    }

                    async function saveLabel(clusterId) {
                        const label = document.getElementById(`label_${clusterId}`).value;
                        if (!label) {
                            alert('Please enter a name');
                            return;
                        }

                        const response = await fetch('/api/label', {
                            method: 'POST',
                            headers: {'Content-Type': 'application/json'},
                            body: JSON.stringify({cluster_id: clusterId, label: label})
                        });

                        const result = await response.json();
                        if (result.success) {
                            alert(`Labeled ${result.updated_faces} faces as "${label}"`);
                            loadClusters();
                            loadStats();
                        } else {
                            alert('Error saving label');
                        }
                    }

                    // Load on page load
                    loadStats();
                    loadClusters();
                </script>
            </body>
            </html>
            """
            self.wfile.write(html.encode())

        elif parsed.path == '/api/stats':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()

            all_faces = faces_collection.get(include=['metadatas'])
            metadatas = all_faces['metadatas']

            cluster_ids = [m.get('cluster_id', -1) for m in metadatas]
            unique_clusters = set(cluster_ids)
            num_clusters = len(unique_clusters) - (1 if -1 in unique_clusters else 0)
            outliers = sum(1 for c in cluster_ids if c == -1)
            labeled_clusters = len(set(m.get('person_name') for m in metadatas if m.get('person_name')))

            self.wfile.write(json.dumps({
                'total_faces': len(metadatas),
                'num_clusters': num_clusters,
                'outliers': outliers,
                'labeled_clusters': labeled_clusters
            }).encode())

        elif parsed.path.startswith('/api/clusters'):
            query_params = parse_qs(parsed.query)
            hide_outliers = query_params.get('hide_outliers', ['true'])[0] == 'true'
            unlabeled_only = query_params.get('unlabeled_only', ['false'])[0] == 'true'
            min_size = int(query_params.get('min_size', ['3'])[0])

            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()

            # Get all faces
            all_faces = faces_collection.get(include=['metadatas'])

            # Group by cluster
            clusters = defaultdict(list)
            for face_id, metadata in zip(all_faces['ids'], all_faces['metadatas']):
                cluster_id = metadata.get('cluster_id', -1)
                clusters[cluster_id].append({
                    'id': face_id,
                    'metadata': metadata
                })

            # Build cluster data
            cluster_list = []
            for cluster_id, faces in sorted(clusters.items(), key=lambda x: len(x[1]), reverse=True):
                # Apply filters
                if hide_outliers and cluster_id == -1:
                    continue
                if len(faces) < min_size:
                    continue

                # Check if labeled
                label = faces[0]['metadata'].get('person_name')
                if unlabeled_only and label:
                    continue

                # Get sample faces (max 20 for display)
                sample_faces = []
                for face in faces[:20]:
                    metadata = face['metadata']

                    # Get photo path
                    photo = photos_collection.get(ids=[metadata['photo_uuid']], include=['metadatas'])
                    if not photo['metadatas']:
                        continue

                    photo_path = photo['metadatas'][0].get('path')
                    if not photo_path or not os.path.exists(photo_path):
                        continue

                    # Get thumbnail
                    thumbnail = get_face_thumbnail(photo_path, metadata)
                    if thumbnail:
                        sample_faces.append({
                            'photo_uuid': metadata['photo_uuid'],
                            'confidence': metadata.get('confidence', 0),
                            'thumbnail': thumbnail
                        })

                if sample_faces:
                    cluster_list.append({
                        'cluster_id': cluster_id,
                        'size': len(faces),
                        'label': label,
                        'faces': sample_faces
                    })

            self.wfile.write(json.dumps(cluster_list).encode())

    def do_POST(self):
        if self.path == '/api/label':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data.decode('utf-8'))

            cluster_id = data['cluster_id']
            label = data['label']

            # Get all faces in cluster
            all_faces = faces_collection.get(include=['metadatas'])

            # Update faces in this cluster
            updated_count = 0
            for face_id, metadata in zip(all_faces['ids'], all_faces['metadatas']):
                if metadata.get('cluster_id') == cluster_id:
                    metadata['person_name'] = label
                    faces_collection.update(
                        ids=[face_id],
                        metadatas=[metadata]
                    )
                    updated_count += 1

            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({
                'success': True,
                'updated_faces': updated_count
            }).encode())

    def log_message(self, format, *args):
        pass  # Suppress logs

if __name__ == '__main__':
    port = 8081
    server = HTTPServer(('localhost', port), FaceBrowserHandler)
    print(f"🌐 Face Cluster Browser running at http://localhost:{port}")
    print("Press Ctrl+C to stop")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()
