# Whisper Tales - Modular Voice AI Research

This repository contains research projects exploring how voice processing components can be built as interchangeable modules with standardized interfaces. It demonstrates a modular computing approach where voice AI components can be dynamically loaded, unloaded, and swapped as long as their input/output interfaces meet specifications.

## 🏗️ Project Philosophy

This repository implements voice AI systems where components function as independent, swappable modules that can be composed together to create larger systems.

## 📁 Projects

### VoxDialog (`vox_dialog/`)
A Phoenix LiveView application showcasing a complete modular voice AI system with:

- **Dynamic Module Loading**: STT, TTS, Voice Session, and Audio Library modules
- **Real-time Dashboard**: Visual module management with responsive design
- **Local Processing**: Whisper CLI + Chatterbox TTS (no external API dependencies)
- **Multi-device Support**: CUDA/MPS/CPU automatic detection and optimization
- **Hot-swappable Components**: Runtime module loading/unloading with interface validation

**Key Features:**
- Modular architecture with standardized interfaces (`initialize/1`, `process/2`, `shutdown/1`)
- Visual module loading/unloading with animated feedback
- Module compatibility checking (output type → input type validation)
- Phoenix PubSub integration for real-time module state broadcasting
- Responsive grid layout adapting from mobile to desktop

## 🎯 Research Goals

This repository explores:

1. **Interface Standardization**: How to define compatible input/output specifications for voice modules
2. **Hot Module Swapping**: Runtime loading/unloading without system restart
3. **Module Composition**: Piping modules together (output of one → input of another)
4. **Graceful Degradation**: System behavior when modules are unavailable
5. **Performance Optimization**: Multi-device AI acceleration with automatic fallback

## 🛠️ Technical Architecture

### Module System Design
```elixir
# Standard interface all modules must implement
@behaviour VoxDialog.ModuleSystem
def info()              # Module metadata and I/O specification
def initialize(opts)    # Setup module state and resources
def process(input, state) # Main processing with state management
def shutdown(state)     # Cleanup and resource deallocation
```

### Voice Processing Pipeline
1. **Audio Capture**: Browser MediaRecorder API → WebM encoding
2. **Data Transport**: Phoenix LiveView channels with Base64 encoding
3. **Module Processing**: Hot-swappable STT/TTS/Voice Session modules
4. **State Management**: GenServer-based Module Manager with supervision
5. **Real-time Updates**: Phoenix PubSub for module status broadcasting

## 🌟 Core Principles

This work demonstrates key modular computing principles:

- **Interchangeable Components** - Voice modules as swappable building blocks
- **Interface Compatibility** - Standardized input/output specifications
- **Modular Composition** - Connecting modules like building blocks
- **System Resilience** - Graceful handling of module failures
- **Future Extensibility** - Easy addition of new voice processing capabilities

## 🚀 Getting Started

Navigate to `vox_dialog/` for complete setup instructions and technical documentation.

Quick start:
```bash
cd vox_dialog/
mix setup
mix phx.server
# Visit http://localhost:4000
```

## 📚 Research Applications

This modular approach enables:
- **Voice AI Research**: Rapid prototyping of new voice processing algorithms
- **System Architecture Studies**: Analysis of modular design patterns
- **Educational Demonstrations**: Teaching modular programming principles
- **Production Systems**: Scalable voice AI with hot-swappable components

---

*Exploring modular computing systems in the age of AI.*
