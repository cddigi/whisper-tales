# Test local Whisper model setup
alias VoxDialog.SpeechRecognition

IO.puts "=== Testing Local Whisper Model ==="

case SpeechRecognition.setup_model() do
  :ok ->
    IO.puts "✅ Model loaded successfully!"
    
    # Test with dummy audio
    IO.puts "\nTesting with dummy audio data..."
    case SpeechRecognition.transcribe_audio(<<0, 0, 0, 0>>, "wav") do
      {:ok, text} ->
        IO.puts "✅ Transcription successful: #{text}"
      {:error, reason} ->
        IO.puts "❌ Transcription failed: #{inspect(reason)}"
    end
    
  {:error, reason} ->
    IO.puts "❌ Failed to load model: #{inspect(reason)}"
end

IO.puts "\n=== Test Complete ==="