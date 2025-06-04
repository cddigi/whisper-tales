# Debug Whisper inference issue
alias VoxDialog.SpeechRecognition.WhisperServer

IO.puts "=== Whisper Debug Test ==="

# Test if the model responds to any input at all
case WhisperServer.status() do
  %{model_loaded: true} ->
    IO.puts "✅ WhisperServer is ready"
  _ ->
    IO.puts "❌ WhisperServer not ready"
    System.halt(1)
end

# Try with minimal data first
IO.puts "\n=== Testing with minimal input ==="

# Create a very short silence WAV (0.1 seconds)
sample_rate = 16000
duration_samples = round(sample_rate * 0.1)  # 0.1 second
samples = List.duplicate(0, duration_samples)  # Silence

# Simple WAV header for minimal file
wav_header = <<
  "RIFF"::binary,
  (36 + length(samples) * 2)::little-32,
  "WAVE"::binary,
  "fmt "::binary,
  16::little-32,
  1::little-16,
  1::little-16,
  sample_rate::little-32,
  (sample_rate * 2)::little-32,
  2::little-16,
  16::little-16,
  "data"::binary,
  (length(samples) * 2)::little-32
>>

sample_data = samples
  |> Enum.map(&<<&1::little-signed-16>>)
  |> Enum.join()

minimal_wav = wav_header <> sample_data

IO.puts "Created minimal WAV: #{byte_size(minimal_wav)} bytes (#{duration_samples} samples)"

# Test with very short timeout to see if it responds at all
IO.puts "Testing with 5-second timeout..."

try do
  case GenServer.call(
    VoxDialog.SpeechRecognition.WhisperServer,
    {:transcribe, minimal_wav},
    5_000  # 5 second timeout
  ) do
    {:ok, text} ->
      IO.puts "✅ Quick response: #{inspect(text)}"
    {:error, reason} ->
      IO.puts "❌ Quick error: #{inspect(reason)}"
  end
catch
  :exit, {:timeout, _} ->
    IO.puts "⏳ Timed out after 5 seconds - inference is hanging"
    
    # This suggests Nx.Serving.run is blocking indefinitely
    IO.puts "\n🔍 DIAGNOSIS:"
    IO.puts "- Model loads successfully"
    IO.puts "- WhisperServer responds to status calls"
    IO.puts "- But Nx.Serving.run hangs indefinitely"
    IO.puts "- This is likely a Bumblebee/Nx compatibility issue"
    
    IO.puts "\n💡 POSSIBLE SOLUTIONS:"
    IO.puts "1. Try different Bumblebee version"
    IO.puts "2. Use different Whisper model size"
    IO.puts "3. Try with EXLA backend (despite SIGBUS risk)"
    IO.puts "4. Use different audio preprocessing"
    IO.puts "5. Switch to different ML framework"
end

IO.puts "\n=== Debug Complete ==="