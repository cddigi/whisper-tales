#!/usr/bin/env python3
"""Vanilla OpenAI Whisper backend"""

import argparse
import json
import sys
import os
import subprocess
import tempfile
from whisper_common import (
    detect_best_device, save_audio_to_temp_file, 
    convert_to_wav_if_needed, cleanup_temp_files
)

def check_whisper_availability():
    """Check if vanilla Whisper is available"""
    try:
        result = subprocess.run(['whisper', '--help'], 
                              capture_output=True, text=True)
        return result.returncode == 0
    except FileNotFoundError:
        return False

def transcribe_with_vanilla_whisper(audio_file_path, model="tiny", language="en"):
    """Transcribe audio using vanilla Whisper CLI"""
    output_dir = tempfile.mkdtemp()
    
    try:
        # Run Whisper CLI
        cmd = [
            'whisper', audio_file_path,
            '--model', model,
            '--language', language,
            '--output_format', 'txt',
            '--output_dir', output_dir,
            '--verbose', 'False'
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode != 0:
            return {"error": f"Whisper CLI failed: {result.stderr}"}
        
        # Read the generated text file
        base_name = os.path.splitext(os.path.basename(audio_file_path))[0]
        txt_file = os.path.join(output_dir, f"{base_name}.txt")
        
        if os.path.exists(txt_file):
            with open(txt_file, 'r', encoding='utf-8') as f:
                text = f.read().strip()
            
            # Clean up output file
            os.remove(txt_file)
            
            return {
                "text": text if text else "[No speech detected]",
                "backend": "vanilla",
                "model": model,
                "language": language
            }
        else:
            return {"error": "Whisper output file not found"}
            
    except Exception as e:
        return {"error": f"Transcription failed: {str(e)}"}
    
    finally:
        # Clean up output directory
        try:
            os.rmdir(output_dir)
        except:
            pass

def main():
    parser = argparse.ArgumentParser(description='Vanilla Whisper transcription')
    parser.add_argument('audio_data', help='Base64 encoded audio data or file path')
    parser.add_argument('--model', default='tiny', help='Whisper model size')
    parser.add_argument('--language', default='en', help='Language code')
    parser.add_argument('--input-type', choices=['base64', 'file'], default='base64')
    
    args = parser.parse_args()
    
    device, device_info = detect_best_device()
    print(device_info, file=sys.stderr)
    
    # Check availability
    if not check_whisper_availability():
        result = {"error": "Vanilla Whisper CLI not available"}
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
        
        # Convert to WAV if needed
        wav_file = convert_to_wav_if_needed(audio_file)
        if wav_file != audio_file:
            temp_files.append(wav_file)
        
        # Transcribe
        result = transcribe_with_vanilla_whisper(wav_file, args.model, args.language)
        print(json.dumps(result))
        
    except Exception as e:
        result = {"error": f"Unexpected error: {str(e)}"}
        print(json.dumps(result))
        sys.exit(1)
    
    finally:
        cleanup_temp_files(*temp_files)

if __name__ == "__main__":
    main()
