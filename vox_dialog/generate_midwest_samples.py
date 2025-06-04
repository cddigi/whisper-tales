#!/usr/bin/env python3
"""Generate Midwest accent audio samples using Chatterbox TTS with MPS acceleration"""

import os
import torch
import torchaudio
from chatterbox.tts import ChatterboxTTS

def setup_device():
    """Auto-detect and setup the best available device (CUDA > MPS > CPU)"""
    import torch
    
    # Priority order: CUDA > MPS > CPU
    if torch.cuda.is_available():
        device = "cuda"
        device_name = torch.cuda.get_device_name(0)
        memory_gb = torch.cuda.get_device_properties(0).total_memory / 1e9
        print(f"🚀 Using CUDA acceleration: {device_name} ({memory_gb:.1f}GB)")
    elif torch.backends.mps.is_available():
        device = "mps"
        print("🚀 Using MPS (Metal Performance Shaders) acceleration on Apple Silicon")
    else:
        device = "cpu"
        print("⚠️  Using CPU (no GPU acceleration available)")
    
    # Handle tensor loading for models saved on different devices
    if device != "cpu":
        # For GPU devices, ensure proper map_location for cross-device compatibility
        original_load = torch.load
        torch.load = lambda *args, **kwargs: original_load(
            *args, 
            **{**kwargs, 'map_location': kwargs.get('map_location', device)}
        )
    
    return device

def generate_audio_sample(model, text, filename):
    """Generate a single audio sample"""
    print(f"Generating: {text}")
    print(f"Filename: {filename}")
    
    try:
        # Generate speech (use default parameters)
        wav = model.generate(text)
        
        # Save to file
        torchaudio.save(filename, wav, model.sr)
        file_size = os.path.getsize(filename)
        duration = wav.shape[-1] / model.sr
        
        print(f"✅ Success! File size: {file_size:,} bytes, Duration: {duration:.1f}s")
        print("")
        return True
        
    except Exception as e:
        print(f"❌ Error: {e}")
        print("")
        return False

def main():
    print("=== Chatterbox TTS Midwest Accent Generator ===")
    print("")
    
    # Setup device
    device = setup_device()
    
    # Load model
    print("Loading Chatterbox TTS model...")
    try:
        model = ChatterboxTTS.from_pretrained(device=device)
        print(f"✅ Model loaded successfully on {device}!")
        print("")
    except Exception as e:
        print(f"❌ Failed to load model: {e}")
        return
    
    # Midwest accent phrases with regional authenticity
    midwest_samples = [
        {
            "text": "Oh, you betcha! That hotdish was real good, don'tcha know.",
            "filename": "midwest_01_hotdish.wav"
        },
        {
            "text": "Ope, just gonna squeeze right past ya there, sorry bout that.",
            "filename": "midwest_02_ope.wav"
        },
        {
            "text": "It's colder than a well digger's belt buckle out there today, I tell ya.",
            "filename": "midwest_03_cold.wav"
        },
        {
            "text": "The Packers are gonna win the Super Bowl this year, mark my words.",
            "filename": "midwest_04_packers.wav"
        },
        {
            "text": "Would you like to come with us to the grocery store? We're getting some pop and brats.",
            "filename": "midwest_05_come_with.wav"
        },
        {
            "text": "That storm last night was a real doozy, eh? Lost power for three hours.",
            "filename": "midwest_06_storm.wav"
        }
    ]
    
    # Generate samples
    print("Generating Midwest accent audio samples...")
    print("")
    
    successful = 0
    for i, sample in enumerate(midwest_samples, 1):
        print(f"[{i}/{len(midwest_samples)}] ", end="")
        if generate_audio_sample(model, sample["text"], sample["filename"]):
            successful += 1
    
    print(f"=== Complete! Generated {successful}/{len(midwest_samples)} samples ===")
    
    # List generated files
    if successful > 0:
        print("\nGenerated files:")
        for sample in midwest_samples:
            if os.path.exists(sample["filename"]):
                size = os.path.getsize(sample["filename"])
                print(f"  {sample['filename']} ({size:,} bytes)")

if __name__ == "__main__":
    main()