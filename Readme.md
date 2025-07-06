
# rtsp-bigbuckbunny

Just a Docker image which:

1. downloads Big Buck Bunny video
2. transcodes it to 6 different formats (takes a while, but only done once at build time)
3. uses GStreamer to efficiently stream all of them through RTSP
4. serves a website with streams' info

Tested with ffplay and VLC

Streams served in: rtsp://localhost:8554/*
Website served in: http:localhost:8080

# Build and run

docker build -t pre-encoded-rtsp .
docker run -d -p 8554:8554 -p 8080:8080 --name rtsp-server pre-encoded-rtsp

# Monitor encoding progress

docker logs -f rtsp-server

# Streams

 - h264_480p: High quality H.264 (CRF 20) 
 - h265_480p: High quality H.265 (CRF 22, smaller file) 
 - h264_lowlatency: H.264 480p Low Latency
 - h264_360p: Mobile-friendly resolution
 - h264_720p: Desktop-friendly resolution 
 - h265_720p: Desktop-friendly resolution

# Test streams (after encoding completes)

ffplay rtsp://localhost:8554/h264_hq
gst-launch-1.0 playbin uri=rtsp://localhost:8554/h264_lowlatency

# Website

http://localhost:8080

