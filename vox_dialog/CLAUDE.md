# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VoxDialog is a Phoenix LiveView application that provides real-time voice recording, transcription, and conversation management. It features local speech recognition using OpenAI Whisper CLI with no external API dependencies.

## Core Architecture

### Voice Processing Pipeline
1. **Browser Audio Capture**: JavaScript MediaRecorder API captures WebM audio
2. **LiveView Communication**: Base64 audio data sent via Phoenix LiveView events
3. **Database Storage**: Audio clips stored as binary data in PostgreSQL
4. **CLI Transcription**: Whisper CLI processes audio via system commands
5. **Real-time Updates**: Phoenix PubSub broadcasts transcription results

### Key GenServer Architecture
- **WhisperServer**: Manages CLI Whisper availability and transcription requests
- **TranscriptionWorker**: Background processing queue for audio clips
- **SessionServer**: Per-session voice processing state management
- **SessionSupervisor**: Dynamic supervisor for voice sessions

### Database Schema
- **voice_sessions**: User session tracking
- **audio_clips**: Binary audio data with transcription status
- **conversation_messages**: Structured conversation history
- **environmental_sounds**: Detected non-speech audio events

## Essential Commands

### Development Setup
```bash
# Install system dependencies (required before mix setup)
brew install uv ffmpeg  # macOS (uv manages Python and packages)

# Setup Python environment with uv (uses pyproject.toml)
uv python install 3.11      # Install Python 3.11
uv sync                      # Create venv and install all dependencies

# Check device compatibility
uv run python device_utils.py  # Shows available PyTorch devices

# Phoenix setup
mix setup                    # Full setup: deps, DB, assets
mix phx.server              # Start development server

# Test Chatterbox TTS (automatically detects and uses best available device):
# - CUDA (NVIDIA GPUs) - highest priority
# - MPS (Apple Silicon M1/M2/M3) - second priority  
# - CPU (fallback) - lowest priority
uv run python generate_midwest_samples.py  # Test with samples
```

### Database Operations
```bash
mix ecto.reset              # Reset database completely
mix ecto.migrate            # Run pending migrations
mix run priv/repo/seeds.exs # Seed database
```

### Testing & Quality
```bash
mix test                    # Run test suite
mix test test/path/file.exs # Run specific test file
```

### Audio Transcription Tools
```bash
mix run transcribe_clips.exs    # CLI tool to transcribe database clips
mix run check_db.exs           # Check database audio clip status
```

### Asset Management
```bash
mix assets.build            # Build assets for development
mix assets.deploy           # Build and minify for production
```

## Speech Recognition Implementation

The application uses **CLI Whisper** (not Bumblebee/Nx) for speech recognition:

## Text-to-Speech Implementation

The application uses **local Chatterbox TTS** with multi-device support via HTTP API for speech synthesis:

### Multi-Device Support
- **CUDA GPUs**: NVIDIA GPU acceleration with automatic memory management
- **Apple Silicon (MPS)**: M1/M2/M3 Neural Engine acceleration via Metal Performance Shaders  
- **CPU Fallback**: Compatible with any system without GPU acceleration
- **Cross-Device Loading**: Automatic tensor mapping for models saved on different devices

### ChatterboxServer (`lib/vox_dialog/speech_synthesis/chatterbox_server.ex`)
- Auto-detects available PyTorch devices (CUDA/MPS/CPU) on startup
- Executes Chatterbox TTS directly via Python scripts with uv
- Handles text-to-speech synthesis with automatic device selection
- Manages temporary file creation and cleanup for audio output
- Returns high-quality audio data for playback in the application

### WhisperServer (`lib/vox_dialog/speech_recognition/whisper_server.ex`)
- Checks CLI tool availability on startup (`whisper --help`, `ffmpeg -version`)
- Manages temporary audio file creation and cleanup
- Handles audio format conversion (WebM → WAV via FFmpeg)
- Runs system commands: `whisper audio.wav --model tiny --output_format txt`

### TTS Processing Flow
1. **Text Input**: Validate text length (max 1000 characters)
2. **Device Detection**: Auto-select best available PyTorch device
3. **Python Execution**: Run Chatterbox TTS script via uv with text input
4. **Audio Generation**: Direct model inference with device acceleration
5. **File Management**: Read generated WAV file and cleanup temp files
6. **Audio Response**: Return high-quality WAV audio data for client playback

### Audio Processing Flow (Speech Recognition)
1. **Format Detection**: Binary header analysis (WebM, WAV, MP3, etc.)
2. **FFmpeg Conversion**: Convert to 16kHz mono WAV for optimal Whisper performance
3. **CLI Execution**: System.cmd with 2-minute timeout
4. **Result Parsing**: Read generated .txt file and clean up temp files

## LiveView Real-time Features

### Voice Session LiveView (`lib/vox_dialog_web/live/voice_session_live.ex`)
- Real-time recording controls with visual feedback
- Audio level monitoring via JavaScript analyser
- Conversation history with automatic transcription updates
- Environmental sound detection alerts

### JavaScript Audio Hook (`assets/js/hooks/audio_processor.js`)
- MediaRecorder API for browser audio capture
- Real-time audio level visualization
- Base64 encoding for Phoenix transport
- Automatic cleanup on component destruction

### PubSub Event System
- `voice_session:#{session_id}` - Session-specific updates
- `transcription_results` - Broadcast transcription completions
- Real-time conversation updates without page refresh

## Critical File Locations

### Core Application Logic
- `lib/vox_dialog/application.ex` - Supervision tree setup
- `lib/vox_dialog/speech_recognition/whisper_server.ex` - CLI integration
- `lib/vox_dialog_web/live/voice_session_live.ex` - Main user interface

### Database Schemas
- `lib/vox_dialog/voice/audio_clip.ex` - Audio storage with transcription status
- `lib/vox_dialog/voice/voice_session.ex` - Session management

### Frontend Assets
- `assets/js/hooks/audio_processor.js` - Browser audio capture
- `assets/css/app.css` - Styling with live recording indicators

## Environment Requirements

### System Dependencies
- **uv** for Python package management
- **Python 3.11+** with `openai-whisper` and `gguf-connector` packages (managed by uv)
- **FFmpeg** for audio format conversion
- **PostgreSQL** for binary audio storage
- **Elixir 1.14+** and **Phoenix 1.7+**
- **Chatterbox TTS server** running at http://127.0.0.1:7860

### Audio Processing Constraints
- Maximum file size: 25MB per audio clip
- Supported formats: WebM (browser), WAV, MP3, M4A (via FFmpeg)
- Processing timeout: 2 minutes per transcription
- Model: `whisper-tiny` (39MB, ~1.5-3.4s processing time)

## Development Patterns

### Audio Clip Status Management
Audio clips have transcription status: `pending` → `processing` → `completed`/`failed`
Use `transcribe_clips.exs` for batch processing and debugging failed transcriptions.

### Error Handling
- CLI tool availability checked at startup with automatic retry
- Graceful fallback when Whisper/FFmpeg unavailable
- Comprehensive logging for audio processing pipeline debugging

### Session Management
Each browser session creates a unique voice session with isolated audio processing.
Sessions are dynamically supervised and automatically cleaned up.