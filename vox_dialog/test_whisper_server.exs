# Test the new WhisperServer
alias VoxDialog.SpeechRecognition.WhisperServer

IO.puts "=== Testing WhisperServer ==="

# Check if server is running
case WhisperServer.status() do
  %{model_loaded: true, loading: false} ->
    IO.puts "✅ WhisperServer is ready!"
    
  %{model_loaded: false, loading: true} ->
    IO.puts "⏳ WhisperServer is loading model..."
    
    # Wait for model to load
    IO.puts "Waiting for model to load (this may take a minute)..."
    :timer.sleep(5000)
    
    case WhisperServer.status() do
      %{model_loaded: true} ->
        IO.puts "✅ Model loaded successfully!"
      %{loading: true} ->
        IO.puts "⏳ Still loading... (this is normal for first startup)"
      other ->
        IO.puts "❌ Unexpected status: #{inspect(other)}"
    end
    
  other ->
    IO.puts "❌ Unexpected status: #{inspect(other)}"
end

IO.puts "\n=== Test Complete ==="