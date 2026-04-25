#!/usr/bin/env python3
import argparse
import json
import sys


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Transcribe a WAV file with faster-whisper."
    )
    parser.add_argument("--audio", required=True, help="Path to the input WAV file")
    parser.add_argument(
        "--model-size", default="small", help="faster-whisper model size or path"
    )
    parser.add_argument("--device", default="cpu", help="Inference device")
    parser.add_argument(
        "--compute-type", default="int8", help="faster-whisper compute type"
    )
    parser.add_argument(
        "--model-dir",
        default=None,
        help="Optional directory used for model downloads and cache reuse",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    try:
        from faster_whisper import WhisperModel
    except Exception as exc:  # pragma: no cover - import failure path
        print(
            json.dumps(
                {
                    "error": f"failed_to_import_faster_whisper: {exc}",
                }
            ),
            file=sys.stderr,
        )
        return 1

    model_kwargs = {
        "device": args.device,
        "compute_type": args.compute_type,
    }
    if args.model_dir:
        model_kwargs["download_root"] = args.model_dir

    try:
        model = WhisperModel(args.model_size, **model_kwargs)
        segments, info = model.transcribe(
            args.audio,
            beam_size=5,
            vad_filter=True,
            condition_on_previous_text=False,
        )
        text = " ".join(segment.text.strip() for segment in segments).strip()
        payload = {
            "text": text,
            "language": getattr(info, "language", None),
        }
        print(json.dumps(payload, ensure_ascii=False))
        return 0
    except Exception as exc:  # pragma: no cover - runtime failure path
        print(
            json.dumps(
                {
                    "error": f"transcription_failed: {exc}",
                }
            ),
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
