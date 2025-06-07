#!/usr/bin/env python3
"""Common utilities for Whisper backends"""

import os
import sys
import tempfile
import torch
import torchaudio.functional as F
from pathlib import Path

def detect_best_device():
    """Detect the best available device for processing"""
    if torch.cuda.is_available():
        device = "cuda"
        device_name = torch.cuda.get_device_name(0)
        device_info = f"🚀 Using CUDA acceleration: {device_name}"
    elif torch.backends.mps.is_available():
        device = "mps"
        device_info = "🚀 Using MPS (Metal Performance Shaders) acceleration"
    else:
        device = "cpu"
        device_info = "⚠️  Using CPU (no GPU acceleration available)"
    
    return device, device_info

def detect_audio_format(audio_data):
    """Detect audio format from binary data"""
    if len(audio_data) < 12:
        return "unknown"
        
    # WebM signature
    if audio_data.startswith(b'\x1A\x45\xDF\xA3'):
        return "webm"
    # WAV signature  
    elif audio_data[0:4] == b'RIFF' and audio_data[8:12] == b'WAVE':
        return "wav"
    # MP3 signature
    elif audio_data[0:2] in [b'\xFF\xFB', b'\xFF\xFA']:
        return "mp3"
    # M4A signature
    elif audio_data[4:8] == b'ftyp':
        return "m4a"
    else:
        return "webm"  # Default fallback

def save_audio_to_temp_file(audio_data, format_hint=None):
    """Save audio data to temporary file"""
    if format_hint is None:
        format_hint = detect_audio_format(audio_data)
    
    temp_dir = tempfile.gettempdir()
    temp_filename = f"whisper_{os.getpid()}_{hash(audio_data) % 999999}.{format_hint}"
    temp_file_path = os.path.join(temp_dir, temp_filename)
    
    try:
        with open(temp_file_path, 'wb') as f:
            f.write(audio_data)
        return temp_file_path
    except Exception as e:
        print(f"Error saving audio to temp file: {e}", file=sys.stderr)
        return None

def convert_to_wav_if_needed(file_path, target_sr=16000):
    """Convert audio file to WAV format if needed"""
    if file_path.lower().endswith('.wav'):
        return file_path
    
    wav_path = file_path.rsplit('.', 1)[0] + '.wav'
    
    # Use FFmpeg for conversion
    import subprocess
    try:
        subprocess.run([
            'ffmpeg', '-i', file_path,
            '-acodec', 'pcm_s16le',  # 16-bit PCM
            '-ar', str(target_sr),   # Target sample rate
            '-ac', '1',              # Mono
            '-y',                    # Overwrite output
            wav_path
        ], check=True, capture_output=True)
        
        return wav_path
    except subprocess.CalledProcessError as e:
        print(f"FFmpeg conversion failed: {e}", file=sys.stderr)
        return file_path  # Return original if conversion fails

def cleanup_temp_files(*file_paths):
    """Clean up temporary files"""
    for file_path in file_paths:
        if file_path and os.path.exists(file_path):
            try:
                os.remove(file_path)
            except Exception as e:
                print(f"Warning: Failed to remove temp file {file_path}: {e}", file=sys.stderr)

def get_compute_type_for_device(device, requested_compute_type="auto"):
    """Get appropriate compute type for device"""
    if requested_compute_type != "auto":
        return requested_compute_type
    
    if device == "cuda":
        # Check if GPU supports float16
        try:
            if torch.cuda.get_device_capability()[0] >= 7:  # Volta or newer
                return "float16"
            else:
                return "float32"
        except:
            return "float32"
    elif device == "mps":
        return "float32"  # MPS generally supports float16
    else:
        return "float32"  # CPU works best with int8
