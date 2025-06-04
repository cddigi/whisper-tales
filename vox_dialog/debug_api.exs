alias VoxDialog.SpeechRecognition
alias VoxDialog.Voice.AudioClip
import Ecto.Query

IO.puts "=== Hugging Face API Debug ==="

# Check token configuration
token = Application.get_env(:vox_dialog, :huggingface_token)
if token && String.length(token) > 0 do
  IO.puts "✅ Token configured: #{String.slice(token, 0, 10)}..."
else
  IO.puts "❌ No token configured"
  IO.puts "Set HUGGINGFACE_TOKEN environment variable"
  System.halt(1)
end

# Test API connectivity first
IO.puts "\n=== Testing API Connectivity ==="
test_url = "https://api-inference.huggingface.co/models/facebook/wav2vec2-large-960h-lv60-self"

# Also test the model info endpoint
info_url = "https://huggingface.co/api/models/hf-audio/wav2vec2-bert-CV16-en"

headers = [
  {"Authorization", "Bearer #{token}"},
  {"Content-Type", "application/json"}
]

# Test with empty request to check model status
case Finch.build(:post, test_url, headers, "{}")
     |> Finch.request(VoxDialog.Finch) do
  {:ok, %{status: status, body: body}} ->
    IO.puts "API responded with status: #{status}"
    case Jason.decode(body) do
      {:ok, parsed} ->
        IO.puts "Response: #{inspect(parsed)}"
      {:error, _} ->
        IO.puts "Raw response: #{String.slice(body, 0, 200)}..."
    end
  {:error, reason} ->
    IO.puts "❌ API request failed: #{inspect(reason)}"
    System.halt(1)
end

# Check for existing audio clips
IO.puts "\n=== Checking Audio Clips ==="
audio_clips = VoxDialog.Repo.all(
  from a in AudioClip,
  order_by: [desc: a.inserted_at],
  limit: 3
)

IO.puts "Found #{length(audio_clips)} audio clips"

if length(audio_clips) > 0 do
  clip = List.first(audio_clips)
  IO.puts "\nTesting with clip: #{clip.clip_id}"
  IO.puts "Format: #{clip.format}"
  IO.puts "Size: #{clip.file_size} bytes"
  IO.puts "Status: #{clip.transcription_status}"
  
  if clip.file_size > 0 do
    IO.puts "\n=== Testing Direct API Call ==="
    
    # Test the API call directly
    audio_headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/octet-stream"}
    ]
    
    case Finch.build(:post, test_url, audio_headers, clip.audio_data)
         |> Finch.request(VoxDialog.Finch, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"text" => transcription}} ->
            IO.puts "✅ SUCCESS! Transcription: #{transcription}"
          {:ok, response} ->
            IO.puts "⚠️  Unexpected response format: #{inspect(response)}"
          {:error, _} ->
            IO.puts "❌ Failed to parse JSON: #{response_body}"
        end
        
      {:ok, %{status: 503, body: body}} ->
        IO.puts "⚠️  Model loading (503): #{body}"
        
      {:ok, %{status: status, body: body}} ->
        IO.puts "❌ API error #{status}: #{body}"
        
      {:error, reason} ->
        IO.puts "❌ Request failed: #{inspect(reason)}"
    end
  else
    IO.puts "❌ Clip has no audio data"
  end
else
  IO.puts "💡 No audio clips found. Record some audio first at /voice"
end

IO.puts "\n=== Debug Complete ==="