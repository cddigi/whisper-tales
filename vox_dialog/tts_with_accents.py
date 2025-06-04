#!/usr/bin/env python3
"""Enhanced TTS script with accent and voice settings support"""

import os
import sys
import json
import argparse
from chatterbox.tts import ChatterboxTTS
import torchaudio
import torch

# Accent-specific Chatterbox TTS settings
ACCENT_SETTINGS = {
    "midwest": {"exaggeration": 0.4, "cfg_weight": 0.5},      # Neutral, clear
    "southern": {"exaggeration": 0.6, "cfg_weight": 0.4},     # Slightly more expressive, slower pace
    "british": {"exaggeration": 0.3, "cfg_weight": 0.6},      # Refined, precise
    "australian": {"exaggeration": 0.5, "cfg_weight": 0.4},   # Relaxed, friendly
    "canadian": {"exaggeration": 0.3, "cfg_weight": 0.5},     # Polite, clear
    "newyork": {"exaggeration": 0.7, "cfg_weight": 0.3},      # Confident, direct
    "california": {"exaggeration": 0.4, "cfg_weight": 0.4},   # Laid-back, smooth
    "texas": {"exaggeration": 0.8, "cfg_weight": 0.3}         # Bold, expressive
}

def apply_voice_modifications(wav, settings, sample_rate):
    """Apply pitch, speed, and tone modifications to the audio"""
    try:
        import torchaudio.functional as F
        
        # Extract settings with defaults
        pitch_factor = float(settings.get('pitch', 1.0))
        speed_factor = float(settings.get('speed', 1.0))
        tone = settings.get('tone', 'neutral')
        
        # Apply pitch shifting (simple approach using resampling)
        if pitch_factor != 1.0:
            # Calculate target sample rate for pitch shift
            target_sr = int(sample_rate * pitch_factor)
            # Resample to change pitch, then back to original rate
            wav = F.resample(wav, sample_rate, target_sr)
            wav = F.resample(wav, target_sr, sample_rate)
        
        # Apply speed changes (time stretching - simple approach)
        if speed_factor != 1.0:
            # Simple speed change by resampling
            target_length = int(wav.shape[-1] / speed_factor)
            if target_length > 0:
                wav = torch.nn.functional.interpolate(
                    wav.unsqueeze(0), 
                    size=target_length, 
                    mode='linear'
                ).squeeze(0)
        
        # Apply tone modifications (basic filtering)
        if tone == 'happy':
            # Slight brightness boost (simplified)
            wav = wav * 1.1
        elif tone == 'serious':
            # Slight darkening
            wav = wav * 0.9
        elif tone == 'calm':
            # Gentle compression
            wav = torch.tanh(wav * 0.8)
        elif tone == 'excited':
            # Slight emphasis
            wav = wav * 1.2
        
        # Ensure audio doesn't clip
        wav = torch.clamp(wav, -1.0, 1.0)
        
        return wav
        
    except Exception as e:
        print(f"Warning: Could not apply voice modifications: {e}")
        return wav

def main():
    parser = argparse.ArgumentParser(description='Generate TTS with accent and voice settings')
    parser.add_argument('text', help='Text to synthesize')
    parser.add_argument('--accent', default='midwest', choices=ACCENT_SETTINGS.keys(),
                        help='Accent style to use for speech generation')
    parser.add_argument('--voice-settings', type=str, default='{}',
                        help='JSON string with voice settings (pitch, speed, tone)')
    parser.add_argument('--output', '-o', default='tts_output.wav',
                        help='Output audio file path')
    
    args = parser.parse_args()
    
    try:
        # Parse voice settings
        voice_settings = json.loads(args.voice_settings)
        
        # Auto-detect best available device
        if torch.cuda.is_available():
            device = "cuda"
            device_name = torch.cuda.get_device_name(0)
            print(f"🚀 Using CUDA acceleration: {device_name}")
        elif torch.backends.mps.is_available():
            device = "mps"
            print("🚀 Using MPS (Metal Performance Shaders) acceleration")
        else:
            device = "cpu"
            print("⚠️  Using CPU (no GPU acceleration available)")
        
        # Handle cross-device tensor loading
        if device != "cpu":
            original_load = torch.load
            torch.load = lambda *args, **kwargs: original_load(
                *args, 
                **{**kwargs, 'map_location': kwargs.get('map_location', device)}
            )
        
        # Load model
        print("Loading Chatterbox TTS model...")
        model = ChatterboxTTS.from_pretrained(device=device)
        print(f"✅ Model loaded successfully on {device}!")
        
        # Get accent-specific settings
        accent_config = ACCENT_SETTINGS.get(args.accent, ACCENT_SETTINGS['midwest'])
        exaggeration = accent_config["exaggeration"]
        cfg_weight = accent_config["cfg_weight"]
        
        print(f"Generating speech with {args.accent} style...")
        print(f"Text: {args.text}")
        print(f"Settings: exaggeration={exaggeration}, cfg_weight={cfg_weight}")
        
        # Generate speech with Chatterbox parameters
        wav = model.generate(
            args.text,
            exaggeration=exaggeration,
            cfg_weight=cfg_weight
        )
        
        # Apply voice modifications
        if voice_settings:
            print(f"Applying voice settings: {voice_settings}")
            wav = apply_voice_modifications(wav, voice_settings, model.sr)
        
        # Save audio file
        torchaudio.save(args.output, wav, model.sr)
        
        # Print file info
        file_size = os.path.getsize(args.output)
        print(f"✅ Audio saved to: {args.output}")
        print(f"📁 File size: {file_size} bytes")
        print(f"🎵 Sample rate: {model.sr} Hz")
        print(f"⏱️  Duration: {wav.shape[-1] / model.sr:.2f} seconds")
        
        return args.output
        
    except json.JSONDecodeError as e:
        print(f"Error parsing voice settings JSON: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error generating TTS: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()