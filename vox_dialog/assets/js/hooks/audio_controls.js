/**
 * AudioControls Hook
 * Provides enhanced audio playback controls including speed and pitch adjustment
 */
export const AudioControls = {
  mounted() {
    this.audio = this.el;
    this.setupAudioControls();
  },

  updated() {
    this.updateAudioSettings();
  },

  setupAudioControls() {
    // Set initial values
    this.updateAudioSettings();

    // Listen for audio events
    this.audio.addEventListener('loadedmetadata', () => {
      this.updateAudioSettings();
    });

    this.audio.addEventListener('play', () => {
      console.log('Audio started playing');
    });

    this.audio.addEventListener('pause', () => {
      console.log('Audio paused');
    });

    this.audio.addEventListener('error', (e) => {
      console.error('Audio error:', e);
    });
  },

  updateAudioSettings() {
    const speed = parseFloat(this.el.dataset.speed) || 1.0;
    const pitch = parseFloat(this.el.dataset.pitch) || 1.0;

    // Update playback rate (speed)
    if (this.audio.playbackRate !== speed) {
      this.audio.playbackRate = speed;
    }

    // Note: Web Audio API pitch shifting would require more complex implementation
    // For now, we'll adjust the playback rate which affects both speed and pitch
    // In a production app, you might want to use Web Audio API for true pitch shifting
    
    // Store current time to preserve position during updates
    const currentTime = this.audio.currentTime;
    
    // Apply pitch adjustment (simple implementation using playback rate)
    // This is a simplified approach - true pitch shifting requires Web Audio API
    if (pitch !== 1.0) {
      // For demonstration, we'll just log the pitch value
      // In a real implementation, you'd use Web Audio API nodes
      console.log(`Pitch adjustment requested: ${pitch}x`);
    }

    // Restore playback position
    if (currentTime && this.audio.currentTime !== currentTime) {
      this.audio.currentTime = currentTime;
    }
  },

  beforeDestroy() {
    // Cleanup if needed
    if (this.audio) {
      this.audio.removeEventListener('loadedmetadata', this.updateAudioSettings);
      this.audio.removeEventListener('play', () => {});
      this.audio.removeEventListener('pause', () => {});
      this.audio.removeEventListener('error', () => {});
    }
  }
};