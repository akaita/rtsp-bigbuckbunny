# Use Ubuntu as base image
FROM ubuntu:22.04

# Set environment variables to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install required packages
RUN apt-get update && apt-get install -y \
    gstreamer1.0-tools \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    gstreamer1.0-rtsp \
    libgstrtspserver-1.0-dev \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    python3 \
    python3-pip \
    python3-gi \
    python3-gi-cairo \
    gir1.2-gst-rtsp-server-1.0 \
    ffmpeg \
    wget \
    curl \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip3 install flask flask-cors

# Create working directory and required directories
WORKDIR /app
RUN mkdir -p /app/media /app/encoded /app/logs /var/log/supervisor

# Download Big Buck Bunny during build
RUN echo "🎬 Downloading source video..." && \
    (wget -O /app/media/source.mp4 \
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4" || \
    wget -O /app/media/source.mp4 \
    "https://archive.org/download/BigBuckBunny_124/Content/big_buck_bunny_720p_surround.mp4") && \
    echo "✅ Source video downloaded"

# PRE-ENCODE ALL STREAMS DURING BUILD (INCLUDING 720p H.265)
RUN echo "🎬 Starting build-time pre-encoding process..." && \
    SOURCE_FILE="/app/media/source.mp4" && \
    ENCODED_DIR="/app/encoded" && \
    \
    # Verify source file exists
    if [ ! -f "$SOURCE_FILE" ]; then \
        echo "❌ Source file not found: $SOURCE_FILE"; \
        exit 1; \
    fi && \
    \
    # Analyze source video
    echo "📊 Analyzing source video..." && \
    ffprobe -v quiet -print_format json -show_format -show_streams "$SOURCE_FILE" > /tmp/source_info.json && \
    VIDEO_DURATION=$(ffprobe -v quiet -show_entries format=duration -of csv="p=0" "$SOURCE_FILE") && \
    echo "📏 Video duration: ${VIDEO_DURATION}s" && \
    \
    # Pre-encode H.264 (480p quality, streaming optimized)
    echo "🔄 Pre-encoding H.264 480p stream..." && \
    ffmpeg -i "$SOURCE_FILE" \
        -c:v libx264 \
        -preset medium \
        -crf 20 \
        -profile:v high \
        -level 4.0 \
        -vf "scale=min(854\,iw):min(480\,ih)" \
        -x264-params "keyint=60:min-keyint=60:scenecut=0" \
        -c:a aac \
        -b:a 128k \
        -ar 44100 \
        -ac 2 \
        -movflags +faststart \
        -f mp4 \
        -y "$ENCODED_DIR/h264_stream.mp4" && \
    \
    # Pre-encode H.265 (480p efficient compression)
    echo "🔄 Pre-encoding H.265 480p stream..." && \
    ffmpeg -i "$SOURCE_FILE" \
        -c:v libx265 \
        -preset medium \
        -crf 22 \
        -profile:v main \
        -level 4.0 \
        -vf "scale=min(854\,iw):min(480\,ih)" \
        -x265-params "keyint=60:min-keyint=60:scenecut=0" \
        -c:a aac \
        -b:a 128k \
        -ar 44100 \
        -ac 2 \
        -movflags +faststart \
        -f mp4 \
        -y "$ENCODED_DIR/h265_stream.mp4" && \
    \
    # Create low-latency version (480p for real-time applications)
    echo "🔄 Pre-encoding low-latency H.264 480p stream..." && \
    ffmpeg -i "$SOURCE_FILE" \
        -c:v libx264 \
        -preset ultrafast \
        -tune zerolatency \
        -crf 23 \
        -profile:v baseline \
        -level 3.1 \
        -vf "scale=min(854\,iw):min(480\,ih)" \
        -x264-params "keyint=30:min-keyint=30:scenecut=0:ref=1:bframes=0" \
        -c:a aac \
        -b:a 96k \
        -ar 44100 \
        -ac 2 \
        -movflags +faststart \
        -f mp4 \
        -y "$ENCODED_DIR/lowlatency_stream.mp4" && \
    \
    # Create 360p version
    echo "🔄 Pre-encoding 360p stream..." && \
    ffmpeg -i "$SOURCE_FILE" \
        -c:v libx264 \
        -preset medium \
        -crf 21 \
        -profile:v main \
        -level 3.1 \
        -vf "scale=min(640\,iw):min(360\,ih)" \
        -x264-params "keyint=60:min-keyint=60:scenecut=0" \
        -c:a aac \
        -b:a 96k \
        -ar 44100 \
        -ac 2 \
        -movflags +faststart \
        -f mp4 \
        -y "$ENCODED_DIR/h264_360p.mp4" && \
    \
    # Create 720p H.264 version
    echo "🔄 Pre-encoding 720p H.264 stream..." && \
    ffmpeg -i "$SOURCE_FILE" \
        -c:v libx264 \
        -preset medium \
        -crf 20 \
        -profile:v high \
        -level 4.0 \
        -vf "scale=min(1280\,iw):min(720\,ih)" \
        -x264-params "keyint=60:min-keyint=60:scenecut=0" \
        -c:a aac \
        -b:a 128k \
        -ar 44100 \
        -ac 2 \
        -movflags +faststart \
        -f mp4 \
        -y "$ENCODED_DIR/h264_720p.mp4" && \
    \
    # Create 720p H.265 version (NEW!)
    echo "🔄 Pre-encoding 720p H.265 stream..." && \
    ffmpeg -i "$SOURCE_FILE" \
        -c:v libx265 \
        -preset medium \
        -crf 21 \
        -profile:v main \
        -level 4.1 \
        -vf "scale=min(1280\,iw):min(720\,ih)" \
        -x265-params "keyint=60:min-keyint=60:scenecut=0" \
        -c:a aac \
        -b:a 128k \
        -ar 44100 \
        -ac 2 \
        -movflags +faststart \
        -f mp4 \
        -y "$ENCODED_DIR/h265_720p.mp4" && \
    \
    # Create encoding status file
    echo "✅ Build-time pre-encoding complete!" && \
    echo "📁 Encoded files:" && \
    ls -lh "$ENCODED_DIR"/*.mp4 && \
    \
    # Create encoding status file
    cat > "$ENCODED_DIR/encoding_complete.json" << 'JSON'
{
    "status": "complete",
    "build_time": true,
    "timestamp": "BUILD_TIME_ENCODED",
    "source_file": "/app/media/source.mp4",
    "encoded_files": [
        "h264_stream.mp4",
        "h265_stream.mp4", 
        "lowlatency_stream.mp4",
        "h264_360p.mp4",
        "h264_720p.mp4",
        "h265_720p.mp4"
    ]
}
JSON

# Create GStreamer RTSP server (updated with 720p H.265 support)
RUN cat > /app/gstreamer_rtsp_server.py << 'EOF'
#!/usr/bin/env python3

import gi
gi.require_version('Gst', '1.0')
gi.require_version('GstRtspServer', '1.0')
from gi.repository import Gst, GstRtspServer, GLib
import sys
import os
import json

class PreEncodedRTSPServer:
    def __init__(self):
        Gst.init(None)
        
        # Verify encoded files exist (they should since they're built into the image)
        self.verify_encoded_files()
        
        # Create RTSP server
        self.server = GstRtspServer.RTSPServer()
        self.server.set_property('service', '8554')
        
        # Get the mount points
        self.mounts = self.server.get_mount_points()
        
        # Setup all streams
        self.setup_all_streams()
        
    def verify_encoded_files(self):
        """Verify all encoded files exist"""
        print("🔍 Verifying pre-encoded files...")
        
        required_files = [
            "/app/encoded/h264_stream.mp4",
            "/app/encoded/h265_stream.mp4",
            "/app/encoded/lowlatency_stream.mp4",
            "/app/encoded/h264_360p.mp4",
            "/app/encoded/h264_720p.mp4",
            "/app/encoded/h265_720p.mp4"
        ]
        
        missing_files = []
        for file_path in required_files:
            if not os.path.exists(file_path):
                missing_files.append(file_path)
        
        if missing_files:
            print(f"❌ Missing encoded files: {missing_files}")
            sys.exit(1)
        
        print("✅ All pre-encoded files verified")
        
    def create_stream_factory(self, media_file, stream_name):
        """Create a stream factory for a pre-encoded file"""
        factory = GstRtspServer.RTSPMediaFactory()

        # Pipeline for pre-encoded stream (no transcoding!)
        pipeline = (
	    f"multifilesrc location={media_file} loop=true ! "
	    "qtdemux name=demux ! "
	    "queue max-size-buffers=0 max-size-time=0 max-size-bytes=0 ! "
	    "h264parse config-interval=1 ! "
	    "queue ! rtph264pay name=pay0 pt=96 config-interval=1 aggregate-mode=zero-latency "
	    "demux. ! queue max-size-buffers=0 max-size-time=0 max-size-bytes=0 ! "
	    "aacparse ! queue ! rtpmp4apay name=pay1 pt=97"
	)
        
        factory.set_launch(pipeline)
        factory.set_shared(True)  # Share among multiple clients
        #factory.set_eos_shutdown(True)
        factory.set_stop_on_disconnect(False)
        factory.set_buffer_size(0x10000)  # 64KB buffer
        factory.set_latency(0)
        
        print(f"📺 Created factory for {stream_name}: {media_file}")
        return factory
        
    def create_h265_stream_factory(self, media_file, stream_name):
        """Create H.265 stream factory"""
        factory = GstRtspServer.RTSPMediaFactory()
        
        # Pipeline for H.265 pre-encoded stream
        pipeline = (
	    f"multifilesrc location={media_file} loop=true ! "
	    "qtdemux name=demux ! "
	    "queue max-size-buffers=0 max-size-time=0 max-size-bytes=0 ! "
	    "h265parse config-interval=1 disable-passthrough=true ! "
	    "queue ! rtph265pay name=pay0 pt=96 config-interval=1 aggregate-mode=zero-latency mtu=1400 "
	    "demux. ! queue max-size-buffers=0 max-size-time=0 max-size-bytes=0 ! "
	    "aacparse ! queue ! rtpmp4apay name=pay1 pt=97 mtu=1400"
	)
        
        factory.set_launch(pipeline)
        factory.set_shared(True)  # Share among multiple clients
        #factory.set_eos_shutdown(True)
        factory.set_stop_on_disconnect(False)
        factory.set_buffer_size(0x10000)  # 64KB buffer
        factory.set_latency(0)
        
        print(f"📺 Created H.265 factory for {stream_name}: {media_file}")
        return factory
        
    def setup_all_streams(self):
        """Setup all available streams"""
        
        streams = [
            ("/h264_480p", "/app/encoded/h264_stream.mp4", "H.264 480p Quality"),
            ("/h265_480p", "/app/encoded/h265_stream.mp4", "H.265 480p Quality"),
            ("/h264_lowlatency", "/app/encoded/lowlatency_stream.mp4", "H.264 480p Low Latency"),
            ("/h264_360p", "/app/encoded/h264_360p.mp4", "H.264 360p"),
            ("/h264_720p", "/app/encoded/h264_720p.mp4", "H.264 720p"),
            ("/h265_720p", "/app/encoded/h265_720p.mp4", "H.265 720p"),
        ]
        
        for mount_point, file_path, description in streams:
            if "h265" in file_path:
                factory = self.create_h265_stream_factory(file_path, description)
            else:
                factory = self.create_stream_factory(file_path, description)
                
            self.mounts.add_factory(mount_point, factory)
            print(f"🔗 Mounted {description} at {mount_point}")
	    
    def run(self):
        """Start the RTSP server"""
        # Attach server to default main context
        self.server.attach(None)
        
        print("\n🚀 GStreamer RTSP Server started on port 8554")
        print("📡 Available streams:")
        print("   rtsp://localhost:8554/h264_480p      - H.264 480p Quality")
        print("   rtsp://localhost:8554/h265_480p      - H.265 480p Quality") 
        print("   rtsp://localhost:8554/h264_lowlatency - H.264 480p Low Latency")
        print("   rtsp://localhost:8554/h264_360p      - H.264 360p")
        print("   rtsp://localhost:8554/h264_720p      - H.264 720p")
        print("   rtsp://localhost:8554/h265_720p      - H.265 720p")
        print("\n🧪 Test commands:")
        print("   gst-launch-1.0 playbin uri=rtsp://localhost:8554/h264_480p")
        print("   gst-launch-1.0 playbin uri=rtsp://localhost:8554/h265_720p")
        print("   ffplay rtsp://localhost:8554/h265_720p")
        print("   vlc rtsp://localhost:8554/h265_720p")
        print("\nPress Ctrl+C to stop")
        
        # Start main loop
        loop = GLib.MainLoop()
        try:
            loop.run()
        except KeyboardInterrupt:
            print("\n🛑 Shutting down RTSP server...")
            loop.quit()

if __name__ == '__main__':
    server = PreEncodedRTSPServer()
    server.run()
EOF

# Create enhanced web interface (updated with 720p H.265 support)
RUN cat > /app/web_interface.py << 'EOF'
#!/usr/bin/env python3
from flask import Flask, jsonify, render_template_string
import subprocess
import os
import time
import json

app = Flask(__name__)

HTML_TEMPLATE = '''
<!DOCTYPE html>
<html>
<head>
    <title>Pre-encoded RTSP Server</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 0; padding: 20px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); }
        .container { max-width: 1200px; margin: 0 auto; background: white; border-radius: 15px; box-shadow: 0 10px 30px rgba(0,0,0,0.2); overflow: hidden; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; }
        .header h1 { margin: 0; font-size: 2.5em; }
        .content { padding: 30px; }
        .status-bar { background: #f8f9fa; padding: 20px; border-radius: 10px; margin-bottom: 30px; }
        .stream-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(350px, 1fr)); gap: 20px; }
        .stream-card { background: #f8f9fa; border-radius: 10px; padding: 20px; border-left: 5px solid #007bff; transition: transform 0.2s; }
        .stream-card:hover { transform: translateY(-2px); box-shadow: 0 5px 15px rgba(0,0,0,0.1); }
        .stream-card h3 { color: #007bff; margin-top: 0; }
        .stream-card.h265 { border-left-color: #28a745; }
        .stream-card.h265 h3 { color: #28a745; }
        .stream-card.h265-hd { border-left-color: #17a2b8; }
        .stream-card.h265-hd h3 { color: #17a2b8; }
        .stream-card.lowlatency { border-left-color: #ffc107; }
        .stream-card.lowlatency h3 { color: #e6930e; }
        .stream-card.hd { border-left-color: #6f42c1; }
        .stream-card.hd h3 { color: #6f42c1; }
        .url-display { background: #2d3748; color: #e2e8f0; padding: 12px; border-radius: 6px; font-family: 'Courier New', monospace; word-break: break-all; font-size: 0.9em; }
        .command-section { background: #1a202c; color: #e2e8f0; padding: 15px; border-radius: 6px; margin-top: 10px; }
        .command-section h4 { color: #90cdf4; margin-top: 0; }
        .status-indicator { display: inline-block; width: 12px; height: 12px; border-radius: 50%; margin-right: 10px; animation: pulse 2s infinite; }
        .status-running { background: #10b981; }
        .status-error { background: #ef4444; }
        .info-badge { background: #3b82f6; color: white; padding: 4px 8px; border-radius: 12px; font-size: 0.8em; margin-left: 10px; }
        .quality-badge { padding: 2px 6px; border-radius: 10px; font-size: 0.75em; font-weight: bold; }
        .quality-360p { background: #dbeafe; color: #1e40af; }
        .quality-480p { background: #dcfce7; color: #166534; }
        .quality-720p { background: #fef3c7; color: #92400e; }
        .quality-h265 { background: #f3e8ff; color: #7c3aed; }
        .quality-h265-hd { background: #e0f2fe; color: #0277bd; }
        .quality-lowlatency { background: #fef3c7; color: #b45309; }
        .performance-note { background: #ecfdf5; border: 1px solid #10b981; padding: 15px; border-radius: 8px; margin: 20px 0; }
        .performance-note h4 { color: #059669; margin-top: 0; }
        .build-info { background: #fef3c7; border: 1px solid #f59e0b; padding: 15px; border-radius: 8px; margin: 20px 0; }
        .build-info h4 { color: #d97706; margin-top: 0; }
        .new-feature { background: #f0f9ff; border: 2px solid #0ea5e9; padding: 15px; border-radius: 8px; margin: 20px 0; }
        .new-feature h4 { color: #0369a1; margin-top: 0; }
        .new-feature::before { content: "🆕 "; }
        @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🎬 Pre-encoded RTSP Server</h1>
            <p>Build-time encoded streams for instant startup</p>
        </div>
        
        <div class="content">
            <div class="status-bar">
                <h2>📊 Server Status</h2>
                <p><span id="status-indicator" class="status-indicator status-running"></span>
                   Status: <span id="server-status">Running</span>
                   <span id="encoding-badge" class="info-badge">Build-time Encoded</span></p>
                <p>Uptime: <span id="uptime">0s</span></p>
                <button onclick="refreshStatus()" style="background: #3b82f6; color: white; border: none; padding: 8px 16px; border-radius: 6px; cursor: pointer;">Refresh Status</button>
            </div>
            
            <div class="stream-grid">
                <div class="stream-card">
                    <h3>🎥 H.264 480p Quality <span class="quality-badge quality-480p">480p</span></h3>
                    <div class="url-display">rtsp://{{host}}:8554/h264_480p</div>
                    <div class="command-section">
                        <h4>Test Commands:</h4>
                        <div># GStreamer<br>gst-launch-1.0 playbin uri=rtsp://{{host}}:8554/h264_480p</div>
                        <div># FFplay<br>ffplay rtsp://{{host}}:8554/h264_480p</div>
                        <div># VLC<br>vlc rtsp://{{host}}:8554/h264_480p</div>
                    </div>
                </div>
                
                <div class="stream-card h265">
                    <h3>🎥 H.265 480p Quality <span class="quality-badge quality-h265">H.265</span></h3>
                    <div class="url-display">rtsp://{{host}}:8554/h265_480p</div>
                    <div class="command-section">
                        <h4>Test Commands:</h4>
                        <div># GStreamer<br>gst-launch-1.0 playbin uri=rtsp://{{host}}:8554/h265_480p</div>
                        <div># FFplay<br>ffplay rtsp://{{host}}:8554/h265_480p</div>
                        <div># VLC<br>vlc rtsp://{{host}}:8554/h265_480p</div>
                    </div>
                </div>
                
                <div class="stream-card lowlatency">
                    <h3>⚡ Low Latency 480p <span class="quality-badge quality-lowlatency">Low Latency</span></h3>
                    <div class="url-display">rtsp://{{host}}:8554/h264_lowlatency</div>
                    <div class="command-section">
                        <h4>Best for:</h4>
                        <div>Real-time applications, video conferencing, live monitoring</div>
                        <h4>Features:</h4>
                        <div>• Zero-latency tuning<br>• Ultrafast encoding<br>• Minimal buffering</div>
                    </div>
                </div>
                
                <div class="stream-card">
                    <h3>📺 Standard Definition <span class="quality-badge quality-360p">360p</span></h3>
                    <div class="url-display">rtsp://{{host}}:8554/h264_360p</div>
                    <div class="command-section">
                        <h4>Best for:</h4>
                        <div>Mobile devices, limited bandwidth, embedded systems</div>
                        <h4>Specs:</h4>
                        <div>• 640x360 resolution<br>• 96kbps audio<br>• Optimized for mobile</div>
                    </div>
                </div>
                
                <div class="stream-card hd">
                    <h3>📺 H.264 HD <span class="quality-badge quality-720p">720p</span></h3>
                    <div class="url-display">rtsp://{{host}}:8554/h264_720p</div>
                    <div class="command-section">
                        <h4>Best for:</h4>
                        <div>Desktop viewing, good quality/bandwidth balance</div>
                        <h4>Specs:</h4>
                        <div>• 1280x720 resolution<br>• 128kbps audio<br>• High quality profile</div>
                    </div>
                </div>
                
                <div class="stream-card h265-hd">
                    <h3>🎬 H.265 HD Premium <span class="quality-badge quality-h265-hd">720p H.265</span></h3>
                    <div class="url-display">rtsp://{{host}}:8554/h265_720p</div>
                    <div class="command-section">
                        <h4>Best for:</h4>
                        <div>Premium quality streaming, digital signage, professional applications</div>
                        <h4>Features:</h4>
                        <div>• 1280x720 resolution<br>• H.265 advanced compression<br>• Superior quality/bitrate ratio<br>• Future-proof codec</div>
                        <h4>Test Commands:</h4>
                        <div># GStreamer<br>gst-launch-1.0 playbin uri=rtsp://{{host}}:8554/h265_720p</div>
                        <div># FFplay<br>ffplay rtsp://{{host}}:8554/h265_720p</div>
                        <div># VLC<br>vlc rtsp://{{host}}:8554/h265_720p</div>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <script>
        let startTime = Date.now();
        
        function updateUptime() {
            const uptime = Math.floor((Date.now() - startTime) / 1000);
            const hours = Math.floor(uptime / 3600);
            const minutes = Math.floor((uptime % 3600) / 60);
            const seconds = uptime % 60;
            document.getElementById('uptime').textContent = 
                `${hours}h ${minutes}m ${seconds}s`;
        }
        
        function refreshStatus() {
            fetch('/api/status')
                .then(response => response.json())
                .then(data => {
                    const statusEl = document.getElementById('server-status');
                    const indicatorEl = document.getElementById('status-indicator');
                    const badgeEl = document.getElementById('encoding-badge');
                    
                    statusEl.textContent = data.status;
                    
                    if (data.status === 'running') {
                        indicatorEl.className = 'status-indicator status-running';
                        badgeEl.textContent = 'Ready';
                        badgeEl.style.background = '#10b981';
                    } else {
                        indicatorEl.className = 'status-indicator status-error';
                        badgeEl.textContent = 'Error';
                        badgeEl.style.background = '#ef4444';
                    }
                })
                .catch(error => {
                    console.error('Status check failed:', error);
                });
        }
        
        setInterval(updateUptime, 1000);
        setInterval(refreshStatus, 10000);
        refreshStatus();
    </script>
</body>
</html>
'''

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE, host='localhost')

@app.route('/api/status')
def api_status():
    try:
        # Check if RTSP server is running
        result = subprocess.run(['pgrep', '-f', 'gstreamer_rtsp_server'], 
                               capture_output=True, text=True)
        rtsp_running = result.returncode == 0
        
        # Check encoded files (should always exist since they're built into the image)
        encoded_files_exist = all(os.path.exists(f"/app/encoded/{f}") for f in [
            'h264_stream.mp4', 'h265_stream.mp4', 'lowlatency_stream.mp4',
            'h264_360p.mp4', 'h264_720p.mp4'
        ])
        
        status = 'running' if rtsp_running and encoded_files_exist else 'error'
            
        return jsonify({
            'status': status,
            'build_time_encoded': True,
            'rtsp_running': rtsp_running,
            'encoded_files_exist': encoded_files_exist,
            'streams': {
                'h264_hq': 'rtsp://localhost:8554/h264_hq',
                'h265_hq': 'rtsp://localhost:8554/h265_hq',
                'h264_lowlatency': 'rtsp://localhost:8554/h264_lowlatency',
                'h264_360p': 'rtsp://localhost:8554/h264_360p',
                'h264_720p': 'rtsp://localhost:8554/h264_720p'
            }
        })
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/health')
def health():
    return jsonify({'status': 'healthy'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
EOF

# Create simplified supervisor configuration (no pre-encoding needed)
RUN cat > /etc/supervisor/conf.d/rtsp-services.conf << 'EOF'
[program:gstreamer-rtsp-server]
command=python3 /app/gstreamer_rtsp_server.py
directory=/app
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/gstreamer-rtsp.log
stderr_logfile=/var/log/supervisor/gstreamer-rtsp.log
priority=200
environment=GST_DEBUG=2

[program:web-interface]
command=python3 /app/web_interface.py
directory=/app
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/web-interface.log
stderr_logfile=/var/log/supervisor/web-interface.log
priority=300
EOF

# Make scripts executable
RUN chmod +x /app/gstreamer_rtsp_server.py /app/web_interface.py

# Clean up source file to save space (optional - uncomment if you want to save space)
# RUN rm -f /app/media/source.mp4

# Expose ports
EXPOSE 8554 8080

# Health check (shorter start period since no encoding needed)
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Start supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf", "-n"]
