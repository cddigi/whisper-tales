#!/usr/bin/env python3
"""Test script for Chatterbox TTS"""

import os
import sys
from chatterbox.tts import ChatterboxTTS
import torchaudio

def main():
    if len(sys.argv) < 2:
        print("Usage: python test_chatterbox.py 'text to synthesize'")
        sys.exit(1)
    
    text = sys.argv[1]
    print(f"Synthesizing: {text}")
    
    try:
        # Initialize Chatterbox TTS
        print("Loading Chatterbox TTS model...")
        import torch
        
        # Auto-detect best available device with proper priority
        if torch.cuda.is_available():
            device = "cuda"
            device_name = torch.cuda.get_device_name(0)
            print(f"🚀 Using CUDA acceleration: {device_name}")
        elif torch.backends.mps.is_available():
            device = "mps"
            print("🚀 Using MPS (Metal Performance Shaders) acceleration on Apple Silicon")
        else:
            device = "cpu"
            print("⚠️  Using CPU (no GPU acceleration available)")
        
        # Handle tensor loading for models saved on different devices
        if device != "cpu":
            # For GPU devices, ensure proper map_location for models saved on different devices
            original_load = torch.load
            torch.load = lambda *args, **kwargs: original_load(
                *args, 
                **{**kwargs, 'map_location': kwargs.get('map_location', device)}
            )
            
        model = ChatterboxTTS.from_pretrained(device=device)
        print(f"✅ Model loaded successfully on {device}!")
        
        # Generate speech
        print("Generating speech...")
        wav = model.generate(text)
        
        # Save to file
        output_file = "test_output.wav"
        torchaudio.save(output_file, wav, model.sr)
        print(f"Audio saved to: {output_file}")
        
        # Print file info
        file_size = os.path.getsize(output_file)
        print(f"File size: {file_size} bytes")
        print(f"Sample rate: {model.sr} Hz")
        
        return output_file
        
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()