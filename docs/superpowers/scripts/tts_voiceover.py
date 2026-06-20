#!/usr/bin/env python3
"""Convert a voiceover text file to MP3 using Piper TTS.

Usage:
    python3 tts_voiceover.py --model /path/to/voice.onnx --input voiceover.txt --output voiceover.mp3

Requires:
    - piper-tts  (CLI binary, already at /usr/bin/piper-tts)
    - ffmpeg      (for WAV -> MP3 conversion)
    - A Piper voice model (.onnx + .json) from:
      https://huggingface.co/rhasspy/piper-voices/

    Recommended English models:
      en_US-lessac-medium  (female, natural)
      en_US-ryan-high      (male, clear)
      en_GB-alan-medium    (male, British)
"""

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def parse_voiceover(path: Path) -> str:
    """Read voiceover file, strip comments and blank lines, return flat text."""
    lines = []
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        lines.append(stripped)
    return "\n".join(lines)


def check_tool(name: str) -> bool:
    return shutil.which(name) is not None


def main():
    parser = argparse.ArgumentParser(
        description="Convert voiceover text to MP3 via Piper TTS"
    )
    parser.add_argument(
        "-m", "--model", required=True, type=Path,
        help="Path to Piper .onnx voice model"
    )
    parser.add_argument(
        "-c", "--config", type=Path, default=None,
        help="Path to model .json config (default: model path + .json)"
    )
    parser.add_argument(
        "-i", "--input", required=True, type=Path,
        help="Path to voiceover text file"
    )
    parser.add_argument(
        "-o", "--output", required=True, type=Path,
        help="Path to output MP3 file"
    )
    parser.add_argument(
        "-s", "--speaker", type=int, default=0,
        help="Speaker ID (default: 0)"
    )
    parser.add_argument(
        "--noise-scale", type=float, default=0.667,
        help="Generator noise (default: 0.667)"
    )
    parser.add_argument(
        "--length-scale", type=float, default=1.0,
        help="Phoneme length (default: 1.0)"
    )
    parser.add_argument(
        "--noise-w", type=float, default=0.8,
        help="Phoneme width noise (default: 0.8)"
    )
    parser.add_argument(
        "--sentence-silence", type=float, default=0.3,
        help="Seconds of silence after each sentence (default: 0.3)"
    )

    args = parser.parse_args()

    # --- Validate tools ---
    if not check_tool("piper-tts"):
        sys.exit(
            "ERROR: piper-tts not found on PATH.\n"
            "Install it from: https://github.com/rhasspy/piper/releases\n"
            "Or: sudo apt install piper-tts"
        )
    if not check_tool("ffmpeg"):
        sys.exit("ERROR: ffmpeg not found on PATH.")

    # --- Validate inputs ---
    if not args.model.exists():
        sys.exit(f"ERROR: model file not found: {args.model}")

    config = args.config
    if not config:
        # Piper models from HuggingFace often use .onnx.json double-extension
        onnx_json = args.model.parent / (args.model.name + ".json")
        plain_json = args.model.with_suffix(".json")
        if onnx_json.exists():
            config = onnx_json
        elif plain_json.exists():
            config = plain_json
        else:
            sys.exit(
                f"ERROR: no config found. Tried:\n"
                f"  {onnx_json}\n"
                f"  {plain_json}\n"
                f"Pass -c explicitly if the config has a different name."
            )

    if not args.input.exists():
        sys.exit(f"ERROR: input file not found: {args.input}")

    # --- Parse voiceover text ---
    text = parse_voiceover(args.input)
    if not text:
        sys.exit("ERROR: no voiceover lines found in input file.")

    print(f"Parsed {text.count(chr(10)) + 1} voiceover lines.")
    print(f"Model:  {args.model}")
    print(f"Config: {config}")

    # --- Synthesize to WAV ---
    args.output.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp_wav:
        wav_path = Path(tmp_wav.name)

    piper_cmd = [
        "piper-tts",
        "-m", str(args.model),
        "-c", str(config),
        "-f", str(wav_path),
        "-s", str(args.speaker),
        "--noise_scale", str(args.noise_scale),
        "--length_scale", str(args.length_scale),
        "--noise_w", str(args.noise_w),
        "--sentence_silence", str(args.sentence_silence),
    ]

    print("Synthesizing speech...")
    result = subprocess.run(
        piper_cmd,
        input=text,
        text=True,
        capture_output=True,
    )

    if result.returncode != 0:
        wav_path.unlink(missing_ok=True)
        sys.exit(f"Piper failed:\n{result.stderr}")

    print(f"WAV written: {wav_path}")

    # --- Convert WAV to MP3 ---
    print("Converting to MP3...")
    ffmpeg_cmd = [
        "ffmpeg",
        "-y",
        "-i", str(wav_path),
        "-codec:a", "libmp3lame",
        "-qscale:a", "2",
        str(args.output),
    ]

    result = subprocess.run(ffmpeg_cmd, capture_output=True, text=True)
    wav_path.unlink(missing_ok=True)

    if result.returncode != 0:
        sys.exit(f"ffmpeg failed:\n{result.stderr}")

    size_kb = args.output.stat().st_size / 1024
    print(f"Done: {args.output} ({size_kb:.0f} KB)")


if __name__ == "__main__":
    main()
