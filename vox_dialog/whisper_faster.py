#!/usr/bin/env python3
"""Faster Whisper backend using ctranslate2"""

import argparse
import json
import sys
import os
import tempfile
import psutil
import gc
from whisper_common import (
    detect_best_device, save_audio_to_temp_file, 
    convert_to_wav_if_needed, cleanup_temp_files
)

# Model repository mapping
MODEL_REPOSITORIES = {
    # Standard multilingual models
    "tiny": "ctranslate2-4you/whisper-tiny-ct2-float32",
    "base": "ctranslate2-4you/whisper-base-ct2-float32", 
    "small": "ctranslate2-4you/whisper-small-ct2-float32",
    "medium": "ctranslate2-4you/whisper-medium-ct2-float32",
    "large-v3": "ctranslate2-4you/whisper-large-v3-ct2-float32",
    "large": "ctranslate2-4you/whisper-large-v3-ct2-float32",  # Alias for large-v3
    
    # English-only models
    "tiny.en": "ctranslate2-4you/whisper-tiny.en-ct2-float32",
    "base.en": "ctranslate2-4you/whisper-base.en-ct2-float32",
    "small.en": "ctranslate2-4you/whisper-small.en-ct2-float32", 
    "medium.en": "ctranslate2-4you/whisper-medium.en-ct2-float32",
    
    # Distil models
    "distil-small.en": "ctranslate2-4you/distil-whisper-small.en-ct2-float32",
    "distil-medium.en": "ctranslate2-4you/distil-whisper-medium.en-ct2-float32",
    "distil-large-v3": "ctranslate2-4you/distil-whisper-large-v3-ct2-float32",
    "distil-large": "ctranslate2-4you/distil-whisper-large-v3-ct2-float32",  # Alias
}

def check_faster_whisper_availability():
    """Check if faster-whisper is available"""
    try:
        from faster_whisper import WhisperModel
        import ctranslate2
        return True
    except ImportError:
        return False

def get_model_repository(model_name):
    """Get the Hugging Face repository for a given model name"""
    if model_name in MODEL_REPOSITORIES:
        return MODEL_REPOSITORIES[model_name]
    else:
        # Return None for unknown models - will cause an error
        return None

def get_available_models():
    """Get list of available model names"""
    return list(MODEL_REPOSITORIES.keys())

def transcribe_with_faster_whisper(audio_file_path, model_size="tiny", 
                                  beam_size=5, vad_filter=True, 
                                  vad_parameters=None, language="en"):
    """Transcribe audio using faster-whisper with float32 compute type"""
    model = None
    try:
        from faster_whisper import WhisperModel
        
        device, device_info = detect_best_device()
        
        # Always use float32 for consistency
        compute_type = "float32"
        
        # Get model repository path
        model_repo = get_model_repository(model_size)
        if model_repo is None:
            available_models = ", ".join(get_available_models())
            return {"error": f"Unknown model '{model_size}'. Available models: {available_models}"}
        
        print(f"Loading faster-whisper model: {model_repo} on {device} with {compute_type}", file=sys.stderr)
        
        # Initialize model with proper thread configuration
        cpu_threads = psutil.cpu_count(logical=False) if device == "cpu" else 4
        
        model = WhisperModel(
            model_repo, 
            device=device, 
            compute_type=compute_type,
            cpu_threads=cpu_threads,
            download_root=None,  # Use default cache
            local_files_only=False
        )
        
        # Set up VAD parameters
        if vad_filter and vad_parameters:
            vad_params = vad_parameters
        else:
            vad_params = {
                "threshold": 0.5,
                "min_speech_duration_ms": 250,
                "max_speech_duration_s": 30,
                "min_silence_duration_ms": 2000,
                "speech_pad_ms": 400
            } if vad_filter else None
        
        # Transcribe
        segments, info = model.transcribe(
            audio_file_path,
            beam_size=beam_size,
            language=language if language != "auto" else None,  # Let model detect if auto
            vad_filter=vad_filter,
            vad_parameters=vad_params,
            word_timestamps=False,  # Disable for faster processing
            condition_on_previous_text=True  # Better accuracy
        )
        
        # Collect segments
        text_segments = []
        for segment in segments:
            text_segments.append(segment.text.strip())
        
        full_text = " ".join(text_segments).strip()
        
        return {
            "text": full_text if full_text else "[No speech detected]",
            "backend": "faster",
            "model": model_size,
            "model_repository": model_repo,
            "language": info.language,
            "language_probability": info.language_probability,
            "duration": info.duration,
            "compute_type": compute_type,
            "device": device,
            "vad_filter": vad_filter,
            "cpu_threads": cpu_threads
        }
        
    except Exception as e:
        return {"error": f"Faster Whisper transcription failed: {str(e)}"}
    
    finally:
        # Proper cleanup
        if model is not None:
            del model
            gc.collect()

def main():
    parser = argparse.ArgumentParser(description='Faster Whisper transcription')
    parser.add_argument('audio_data', help='Base64 encoded audio data or file path')
    parser.add_argument('--model', default='tiny', help='Whisper model size')
    parser.add_argument('--beam-size', type=int, default=5, help='Beam size')
    parser.add_argument('--language', default='en', help='Language code (use "auto" for detection)')
    parser.add_argument('--vad-filter', action='store_true', help='Enable VAD filter')
    parser.add_argument('--vad-parameters', type=str, help='VAD parameters as JSON')
    parser.add_argument('--input-type', choices=['base64', 'file'], default='base64')
    parser.add_argument('--list-models', action='store_true', help='List available models')
    
    args = parser.parse_args()
    
    # List models if requested
    if args.list_models:
        models = get_available_models()
        result = {"available_models": models}
        print(json.dumps(result, indent=2))
        sys.exit(0)
    
    # Check availability
    if not check_faster_whisper_availability():
        result = {"error": "Faster Whisper not available"}
        print(json.dumps(result))
        sys.exit(1)
    
    temp_files = []
    
    try:
        if args.input_type == 'base64':
            # Decode base64 audio data
            import base64
            audio_data = base64.b64decode(args.audio_data)
            audio_file = save_audio_to_temp_file(audio_data)
            if not audio_file:
                result = {"error": "Failed to save audio data"}
                print(json.dumps(result))
                sys.exit(1)
            temp_files.append(audio_file)
        else:
            audio_file = args.audio_data
        
        # Convert to WAV if needed (faster-whisper prefers 16kHz)
        wav_file = convert_to_wav_if_needed(audio_file, target_sr=16000)
        if wav_file != audio_file:
            temp_files.append(wav_file)
        
        # Parse VAD parameters
        vad_parameters = None
        if args.vad_parameters:
            try:
                vad_parameters = json.loads(args.vad_parameters)
            except json.JSONDecodeError:
                result = {"error": "Invalid VAD parameters JSON"}
                print(json.dumps(result))
                sys.exit(1)
        
        # Transcribe
        result = transcribe_with_faster_whisper(
            wav_file, 
            model_size=args.model,
            beam_size=args.beam_size,
            vad_filter=args.vad_filter,
            vad_parameters=vad_parameters,
            language=args.language
        )
        
        print(json.dumps(result))
        
    except Exception as e:
        result = {"error": f"Unexpected error: {str(e)}"}
        print(json.dumps(result))
        sys.exit(1)
    
    finally:
        cleanup_temp_files(*temp_files)

if __name__ == "__main__":
    main()
