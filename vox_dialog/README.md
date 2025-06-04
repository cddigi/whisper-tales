# VoxDialog - Modular Voice AI System

VoxDialog is a Phoenix LiveView application that implements a modular architecture where voice processing components can be dynamically loaded, unloaded, and swapped as long as their input/output interfaces meet the specifications.

## 🏗️ Architecture Philosophy

VoxDialog treats each voice processing capability as an independent, swappable module:

- **Speech-to-Text (STT)** - Audio input → Text output
- **Text-to-Speech (TTS)** - Text input → Audio output  
- **Voice Session** - Audio stream input → Audio stream output
- **Audio Library** - Audio management with CRUD operations

Each module implements a standard interface (`initialize/1`, `process/2`, `shutdown/1`) allowing them to be:
- Loaded and unloaded on demand
- Piped together (output of one becomes input of another)
- Replaced with alternative implementations
- Monitored and managed through a central Module Manager

## 🚀 Features

### Modular Dashboard
- Dynamic module loading/unloading with visual feedback
- Real-time module status monitoring
- Responsive interface that adapts to all screen sizes
- Module activation and embedded interface display

### Voice Processing Capabilities
- **Local Speech Recognition** using OpenAI Whisper CLI (no API dependencies)
- **High-Quality Text-to-Speech** using Chatterbox TTS with multi-device support
- **Real-time Voice Conversations** with AI integration
- **Audio Library Management** with advanced filtering and playback controls

### Technical Implementation
- **Phoenix LiveView** for real-time UI updates
- **GenServer-based Module Manager** for lifecycle management
- **Multi-device TTS Support** (CUDA/MPS/CPU with automatic detection)
- **Responsive Grid Layout** with fluid table design
- **PubSub Integration** for module state broadcasting

## 🛠️ Setup & Installation

### System Dependencies
```bash
# macOS setup
brew install uv ffmpeg

# Install Python 3.11+ and dependencies
uv python install 3.11
uv sync
```

### Development Setup
```bash
# Full setup: dependencies, database, assets
mix setup

# Start development server
mix phx.server
```

### Testing Audio Components
```bash
# Test device compatibility
uv run python device_utils.py

# Test TTS with sample generation
uv run python generate_midwest_samples.py

# Test CLI transcription tool
mix run transcribe_clips.exs
```

## 🌐 Usage

Visit [`localhost:4000`](http://localhost:4000) to access the modular dashboard where you can:

1. **Load Modules** - Click on available modules to load them into the system
2. **Activate Modules** - Select loaded modules to view their interfaces
3. **Unload Modules** - Remove modules when no longer needed
4. **Monitor System** - View real-time module status and system health

### Module Interfaces

Each module provides specific capabilities:
- **STT Module**: Upload audio files or record voice for transcription
- **TTS Module**: Enter text and generate speech with accent selection
- **Voice Session**: Real-time voice conversations with AI
- **Audio Library**: Manage, filter, and playback all audio clips

## 🔧 Technical Details

### Module System Architecture
```elixir
# Standard module interface
@behaviour VoxDialog.ModuleSystem
def info() # Module metadata and interface specification
def initialize(opts) # Setup module state
def process(input, state) # Main processing function
def shutdown(state) # Cleanup resources
```

### Database Schema
- **voice_sessions**: Session tracking and management
- **audio_clips**: Binary audio storage with metadata
- **conversation_messages**: Structured conversation history
- **environmental_sounds**: Non-speech audio event detection

### Audio Processing Pipeline
1. Browser captures WebM audio via MediaRecorder API
2. Base64 encoded data sent through Phoenix LiveView
3. Binary storage in PostgreSQL with metadata
4. CLI Whisper processes audio for transcription
5. Real-time updates via Phoenix PubSub

## 📊 Performance & Compatibility

### TTS Multi-Device Support
- **CUDA GPUs**: NVIDIA acceleration with automatic memory management
- **Apple Silicon (MPS)**: M1/M2/M3 Neural Engine via Metal Performance Shaders
- **CPU Fallback**: Universal compatibility without GPU requirements
- **Cross-Device Loading**: Automatic tensor mapping for different hardware

### Audio Format Support
- **Input**: WebM (browser), WAV, MP3, M4A (via FFmpeg conversion)
- **Output**: High-quality WAV files for playback and download
- **Processing**: 16kHz mono optimization for Whisper
- **Limits**: 25MB max file size, 2-minute processing timeout

## 🎯 Development Philosophy

This project demonstrates:
- **Modular Architecture**: Components with well-defined interfaces
- **Hot Swapping**: Runtime module loading/unloading
- **Interface Compatibility**: Standardized input/output specifications
- **Graceful Degradation**: Fallback when modules are unavailable
- **Real-time Feedback**: Live system status and module state

## 📚 Additional Resources

- [Phoenix LiveView Documentation](https://hexdocs.pm/phoenix_live_view)
- [Whisper CLI Documentation](https://github.com/openai/whisper)
- [Chatterbox TTS](https://github.com/chatterbox-tts)

---

*Built with Phoenix Framework, demonstrating modular system design principles.*
