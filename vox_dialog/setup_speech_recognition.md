# Speech Recognition Setup

## CLI Whisper Implementation

VoxDialog uses **local CLI-based speech recognition** with no external dependencies:

- **Backend**: OpenAI Whisper CLI (system-installed)
- **Framework**: System commands via Elixir
- **Runs locally**: No API keys or internet required
- **Privacy**: Audio never leaves your machine
- **Cost**: Completely free after initial setup

## Installation Requirements

Before starting VoxDialog, install the required CLI tools:

1. **Install Whisper CLI**:
   ```bash
   pip3 install openai-whisper
   ```

2. **Install FFmpeg** (for audio conversion):
   ```bash
   # macOS
   brew install ffmpeg
   
   # Ubuntu/Debian
   sudo apt update && sudo apt install ffmpeg
   
   # Windows
   # Download from https://ffmpeg.org/download.html
   ```

3. **Verify installation**:
   ```bash
   whisper --help    # Should show Whisper CLI help
   ffmpeg -version   # Should show FFmpeg version
   ```

## How It Works

VoxDialog automatically:
1. **Detects audio format** from browser recordings (WebM, WAV, etc.)
2. **Converts to WAV** using FFmpeg for optimal Whisper compatibility
3. **Transcribes with Whisper CLI** using the fast "tiny" model
4. **Cleans up** temporary files after processing

## Model Information

**Default Model**: `whisper-tiny`
- **Type**: Automatic Speech Recognition (ASR)
- **Language**: Multilingual (100+ languages, auto-detected)
- **Size**: ~39MB (downloads automatically on first use)
- **Quality**: Good accuracy for clear speech
- **Speed**: ~1.5-3.4 seconds per audio clip
- **Supports**: All audio formats via FFmpeg conversion

## Why CLI Whisper?

- **Privacy**: Audio processing happens entirely on your machine
- **No costs**: No API fees or usage limits
- **Reliable**: No hanging inference or memory issues
- **Fast**: Direct CLI execution without ML framework overhead
- **Stable**: Works consistently across different systems
- **Flexible**: Easy to upgrade or change Whisper models

## Testing Speech Recognition

1. **Install dependencies and start the server**:
   ```bash
   # Install Elixir dependencies
   mix deps.get
   
   # Start the Phoenix server
   mix phx.server
   ```
   
   **Startup output**:
   ```
   [info] WhisperServer starting with CLI backend...
   [info] Checking CLI tools availability...
   [info] ✅ Whisper CLI available
   [info] ✅ FFmpeg available
   [info] CLI tools available - WhisperServer ready
   ```

2. **Record audio**:
   - Visit http://localhost:4000/voice
   - Click "Start Recording"
   - Speak clearly for a few seconds
   - Click "Stop Recording"

3. **Check transcription**:
   - Processing happens locally via CLI
   - Check the conversation display for transcribed text
   - Visit http://localhost:4000/clips to see all transcriptions

## Verification

To verify CLI tools are working:
```bash
# Test Whisper CLI directly
whisper --help

# Test FFmpeg
ffmpeg -version

# Test transcription of existing clips
mix run transcribe_clips.exs
```

## Troubleshooting

- **"Whisper CLI not available"**: Install with `pip3 install openai-whisper`
- **"FFmpeg not available"**: Install FFmpeg for your system
- **Slow transcription**: First-time model download (~39MB) may take time
- **Audio format issues**: FFmpeg automatically converts all formats to WAV
- **Permission errors**: Ensure Whisper CLI is in your PATH
- **Audio too large**: Maximum file size is 25MB
- **No speech detected**: Whisper returns "[No speech detected]" for silence

## CLI Transcription Tool

Transcribe existing database clips without starting the web server:
```bash
mix run transcribe_clips.exs
```

This tool allows you to:
- Transcribe pending clips
- Retry failed transcriptions
- Process specific clips
- Batch process all clips

## Performance

CLI Whisper Performance:
- **Model size**: 39MB (tiny), 139MB (base), 461MB (small)
- **Memory usage**: Minimal (CLI process)
- **Speed**: ~1.5-3.4 seconds per audio clip
- **Timeout**: 2 minutes maximum per audio file
- **File size limit**: 25MB maximum
- **Accuracy**: Good for clear speech, handles accents well
- **Languages**: 100+ languages supported (auto-detected)

## System Requirements

- **Python 3**: For Whisper CLI installation
- **FFmpeg**: For audio format conversion
- **Storage**: ~100MB for Whisper models
- **Memory**: Minimal (temporary audio files only)
- **CPU**: Any modern CPU

## Advanced Configuration

To use a different Whisper model, edit `whisper_server.ex:220`:
```elixir
# For better accuracy (but slower):
"--model", "base",    # or "small", "medium", "large"
```

Available models:
- `tiny`: 39MB, fastest, good accuracy
- `base`: 139MB, better accuracy
- `small`: 461MB, even better accuracy
- `medium`: 1.5GB, high accuracy
- `large`: 3GB, best accuracy

## Alternative Backends

If CLI Whisper doesn't meet your needs:

1. **OpenAI Whisper API**: Most reliable option with costs (~$0.006/minute)
2. **AssemblyAI**: Good accuracy with free tier available
3. **Google Speech-to-Text**: Enterprise-grade with generous free tier
4. **Azure Speech Services**: Microsoft's offering with real-time capabilities