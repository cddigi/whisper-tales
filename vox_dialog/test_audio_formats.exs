# Test Whisper with different audio formats to identify the issue
alias VoxDialog.SpeechRecognition.WhisperServer

IO.puts "=== Audio Format Testing ==="

# Check if WhisperServer is ready
case WhisperServer.status() do
  %{model_loaded: true} ->
    IO.puts "✅ WhisperServer is ready"
  _ ->
    IO.puts "❌ WhisperServer not ready, exiting"
    System.halt(1)
end

# Create a simple sine wave WAV file for testing
IO.puts "\n=== Creating Test WAV File ==="

# Simple WAV header + sine wave data (1 second, 16kHz, mono)
sample_rate = 16000
duration_seconds = 1
samples = for i <- 0..(sample_rate * duration_seconds - 1) do
  # Generate a 440Hz sine wave
  frequency = 440
  sample = :math.sin(2 * :math.pi() * frequency * i / sample_rate)
  # Convert to 16-bit signed integer
  round(sample * 32767)
end

# Create WAV header
wav_header = <<
  # RIFF header
  "RIFF"::binary,
  (36 + length(samples) * 2)::little-32,  # file size - 8
  "WAVE"::binary,
  # fmt chunk
  "fmt "::binary,
  16::little-32,           # fmt chunk size
  1::little-16,            # PCM format
  1::little-16,            # mono
  sample_rate::little-32,  # sample rate
  (sample_rate * 2)::little-32,  # byte rate
  2::little-16,            # block align
  16::little-16,           # bits per sample
  # data chunk
  "data"::binary,
  (length(samples) * 2)::little-32  # data size
>>

# Convert samples to binary
sample_data = samples
  |> Enum.map(&<<&1::little-signed-16>>)
  |> Enum.join()

wav_data = wav_header <> sample_data

IO.puts "Created test WAV: #{byte_size(wav_data)} bytes"

# Test transcription with the WAV data
IO.puts "\n=== Testing WAV Transcription ==="
start_time = System.monotonic_time(:millisecond)

case WhisperServer.transcribe(wav_data) do
  {:ok, text} ->
    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time
    IO.puts "✅ WAV transcription SUCCESS (#{duration_ms}ms)"
    IO.puts "Text: #{inspect(text)}"
    
  {:error, reason} ->
    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time
    IO.puts "❌ WAV transcription FAILED (#{duration_ms}ms): #{inspect(reason)}"
end

# Test with a minimal WebM-like header (this will likely fail)
IO.puts "\n=== Testing WebM Detection ==="
webm_header = <<0x1A, 0x45, 0xDF, 0xA3, 0x9F, 0x42, 0x86, 0x81, 0x01, 0x42, 0xF7, 0x81>>
fake_webm = webm_header <> <<0::size(1000*8)>>  # Add some dummy data

IO.puts "Created fake WebM: #{byte_size(fake_webm)} bytes"

start_time = System.monotonic_time(:millisecond)
case WhisperServer.transcribe(fake_webm) do
  {:ok, text} ->
    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time
    IO.puts "✅ WebM transcription SUCCESS (#{duration_ms}ms)"
    IO.puts "Text: #{inspect(text)}"
    
  {:error, reason} ->
    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time
    IO.puts "❌ WebM transcription FAILED (#{duration_ms}ms): #{inspect(reason)}"
end

IO.puts "\n=== Test Complete ==="