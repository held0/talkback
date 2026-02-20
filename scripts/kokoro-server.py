#!/usr/bin/env python3
"""Minimal Kokoro TTS server with OpenAI-compatible API."""
import sys
import io
import json
import argparse
from http.server import HTTPServer, BaseHTTPRequestHandler

# Lazy imports - loaded on first request
_kokoro_pipeline = None
_voices = None

def get_pipeline():
    global _kokoro_pipeline
    if _kokoro_pipeline is None:
        from kokoro import KPipeline
        _kokoro_pipeline = KPipeline(lang_code='a')
    return _kokoro_pipeline

def get_voices():
    """Return list of available voice names."""
    return [
        "af_heart", "af_alloy", "af_aoede", "af_bella", "af_jessica",
        "af_kore", "af_nicole", "af_nova", "af_river", "af_sarah", "af_sky",
        "am_adam", "am_echo", "am_eric", "am_fenrir", "am_liam", "am_michael",
        "am_onyx", "am_puck",
        "bf_emma", "bf_isabella",
        "bm_george", "bm_lewis",
    ]

class KokoroHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Suppress request logs

    def do_GET(self):
        if self.path == '/v1/models':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"data": [{"id": "kokoro"}]}).encode())
        elif self.path == '/v1/audio/voices':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"voices": get_voices()}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == '/v1/audio/speech':
            content_length = int(self.headers['Content-Length'])
            body = json.loads(self.rfile.read(content_length))

            text = body.get('input', '')
            voice = body.get('voice', 'af_heart')
            speed = body.get('speed', 1.0)

            if not text:
                self.send_response(400)
                self.end_headers()
                return

            try:
                pipeline = get_pipeline()
                # Generate audio
                samples = []
                for _, _, audio in pipeline(text, voice=voice, speed=speed):
                    samples.append(audio)

                if not samples:
                    self.send_response(500)
                    self.end_headers()
                    return

                import numpy as np
                import soundfile as sf

                combined = np.concatenate(samples)
                buf = io.BytesIO()
                sf.write(buf, combined, 24000, format='WAV')
                audio_bytes = buf.getvalue()

                self.send_response(200)
                self.send_header('Content-Type', 'audio/wav')
                self.send_header('Content-Length', str(len(audio_bytes)))
                self.end_headers()
                self.wfile.write(audio_bytes)

            except Exception as e:
                print(f"TTS error: {e}", file=sys.stderr)
                self.send_response(500)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default='0.0.0.0')
    parser.add_argument('--port', type=int, default=8880)
    args = parser.parse_args()

    print(f"Starting Kokoro TTS server on {args.host}:{args.port}")
    server = HTTPServer((args.host, args.port), KokoroHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.shutdown()
