#!/usr/bin/env python3
"""Device detection utility for PyTorch models"""

import torch

def detect_best_device(verbose=True):
    """Detect the best available PyTorch device with priority: CUDA > MPS > CPU"""
    
    if torch.cuda.is_available():
        device = "cuda"
        device_name = torch.cuda.get_device_name(0)
        device_info = f"🚀 Using CUDA acceleration: {device_name}"
    elif torch.backends.mps.is_available():
        device = "mps"
        device_info = "🚀 Using MPS (Metal Performance Shaders) acceleration on Apple Silicon"
    else:
        device = "cpu"
        device_info = "⚠️  Using CPU (no GPU acceleration available)"
    
    if verbose:
        print(device_info)
    
    return device, device_info

def main():
    """Main function for command-line usage"""
    device, device_info = detect_best_device(verbose=True)
    
    # Print additional device information
    print(f"Device: {device}")
    
    if device == "cuda":
        print(f"CUDA Version: {torch.version.cuda}")
        print(f"CUDA Devices Available: {torch.cuda.device_count()}")
        for i in range(torch.cuda.device_count()):
            props = torch.cuda.get_device_properties(i)
            print(f"  Device {i}: {props.name} ({props.total_memory // 1024**2} MB)")
    elif device == "mps":
        print("MPS Backend Available: True")
    
    print(f"PyTorch Version: {torch.__version__}")

if __name__ == "__main__":
    main()