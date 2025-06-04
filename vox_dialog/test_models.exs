# Test various ASR models to find one that works with Inference API
alias VoxDialog.SpeechRecognition

IO.puts "=== Testing ASR Models ==="

token = "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"

test_models = [
  "microsoft/speecht5_asr",
  "jonatasgrosman/wav2vec2-large-xlsr-53-english",
  "facebook/s2t-small-librispeech-asr",
  "facebook/hubert-large-ls960-ft"
]

headers = [
  {"Authorization", "Bearer #{token}"},
  {"Content-Type", "application/json"}
]

Enum.each(test_models, fn model ->
  url = "https://api-inference.huggingface.co/models/#{model}"
  IO.puts "\nTesting: #{model}"
  
  case Finch.build(:post, url, headers, "{}")
       |> Finch.request(VoxDialog.Finch) do
    {:ok, %{status: 200}} ->
      IO.puts "✅ Available (200)"
    {:ok, %{status: 503}} ->
      IO.puts "⚠️  Loading (503)"
    {:ok, %{status: 404}} ->
      IO.puts "❌ Not Found (404)"
    {:ok, %{status: status}} ->
      IO.puts "⚠️  Status: #{status}"
    {:error, reason} ->
      IO.puts "❌ Error: #{inspect(reason)}"
  end
end)

IO.puts "\n=== Testing Complete ==="