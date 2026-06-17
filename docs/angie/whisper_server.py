import os
import tempfile

from flask import Flask, jsonify, request
from faster_whisper import WhisperModel

MODEL_SIZE = os.environ.get("WHISPER_MODEL", "small")
PORT = int(os.environ.get("WHISPER_PORT", "27125"))

app = Flask(__name__)
model = WhisperModel(MODEL_SIZE, device="cpu", compute_type="int8")


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "model": MODEL_SIZE})


@app.route("/transcribe", methods=["POST"])
def transcribe():
    audio_bytes = request.get_data()
    if not audio_bytes:
        return jsonify({"error": "geen audio ontvangen"}), 400
    with tempfile.NamedTemporaryFile(suffix=".oga", delete=True) as tmp:
        tmp.write(audio_bytes)
        tmp.flush()
        segments, _info = model.transcribe(tmp.name, language="nl")
        text = " ".join(seg.text.strip() for seg in segments).strip()
    return jsonify({"text": text})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT, threaded=True)
