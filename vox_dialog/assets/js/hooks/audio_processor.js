export default {
  mounted() {
    this.sessionId = this.el.dataset.sessionId;
    this.mediaRecorder = null;
    this.audioContext = null;
    this.analyser = null;
    this.dataArray = null;
    this.animationId = null;
    this.stream = null;
    this.recordingStartTime = null;
    this.audioChunks = [];
    
    // Initialize audio processing
    this.initAudio();
    
    // Listen for recording events from LiveView
    window.addEventListener("phx:start_recording", () => this.startRecording());
    window.addEventListener("phx:stop_recording", () => this.stopRecording());
  },
  
  destroyed() {
    this.cleanup();
  },
  
  async initAudio() {
    try {
      // Create audio context
      this.audioContext = new (window.AudioContext || window.webkitAudioContext)();
      
      // Get user media
      this.stream = await navigator.mediaDevices.getUserMedia({ 
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true
        } 
      });
      
      // Create audio analyser for level monitoring
      this.analyser = this.audioContext.createAnalyser();
      this.analyser.fftSize = 256;
      
      const source = this.audioContext.createMediaStreamSource(this.stream);
      source.connect(this.analyser);
      
      this.dataArray = new Uint8Array(this.analyser.frequencyBinCount);
      
      // Start monitoring audio levels
      this.monitorAudioLevel();
      
    } catch (error) {
      console.error('Error initializing audio:', error);
      this.pushEvent("audio_error", { error: error.message });
    }
  },
  
  startRecording() {
    console.log('Starting recording...');
    if (!this.stream) {
      console.error('No audio stream available');
      return;
    }
    
    // Reset audio chunks and start time
    this.audioChunks = [];
    this.recordingStartTime = Date.now();
    
    // Configure media recorder
    const options = {
      mimeType: 'audio/webm;codecs=opus',
      audioBitsPerSecond: 16000
    };
    
    this.mediaRecorder = new MediaRecorder(this.stream, options);
    
    // Collect audio chunks
    this.mediaRecorder.ondataavailable = (event) => {
      if (event.data.size > 0) {
        this.audioChunks.push(event.data);
      }
    };
    
    // Handle recording stop
    this.mediaRecorder.onstop = () => {
      this.processCompleteRecording();
    };
    
    // Start recording
    this.mediaRecorder.start();
  },
  
  stopRecording() {
    console.log('Stopping recording...');
    if (this.mediaRecorder && this.mediaRecorder.state === 'recording') {
      this.mediaRecorder.stop();
      this.mediaRecorder = null;
    }
  },
  
  async processCompleteRecording() {
    try {
      console.log('Processing complete recording...');
      // Calculate duration
      const duration = this.recordingStartTime ? Date.now() - this.recordingStartTime : null;
      console.log('Recording duration:', duration, 'ms');
      
      // Combine all audio chunks
      const completeBlob = new Blob(this.audioChunks, { type: 'audio/webm;codecs=opus' });
      console.log('Audio blob size:', completeBlob.size, 'bytes');
      
      // Convert to base64
      const reader = new FileReader();
      reader.onloadend = () => {
        const base64Data = reader.result.split(',')[1];
        console.log('Sending audio data to server. Base64 length:', base64Data.length);
        this.pushEvent("audio_data", { 
          data: base64Data,
          duration: duration
        });
      };
      reader.readAsDataURL(completeBlob);
      
    } catch (error) {
      console.error('Error processing complete recording:', error);
    }
  },
  
  monitorAudioLevel() {
    const updateLevel = () => {
      if (!this.analyser) return;
      
      this.analyser.getByteFrequencyData(this.dataArray);
      
      // Calculate average level
      let sum = 0;
      for (let i = 0; i < this.dataArray.length; i++) {
        sum += this.dataArray[i];
      }
      const average = sum / this.dataArray.length;
      const normalizedLevel = average / 255;
      
      // Send level update
      this.pushEvent("audio_level", { level: normalizedLevel });
      
      // Continue monitoring
      this.animationId = requestAnimationFrame(updateLevel);
    };
    
    updateLevel();
  },
  
  cleanup() {
    // Stop recording
    this.stopRecording();
    
    // Stop animation
    if (this.animationId) {
      cancelAnimationFrame(this.animationId);
    }
    
    // Close audio context
    if (this.audioContext) {
      this.audioContext.close();
    }
    
    // Stop media stream
    if (this.stream) {
      this.stream.getTracks().forEach(track => track.stop());
    }
  }
};