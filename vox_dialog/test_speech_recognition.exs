alias VoxDialog.SpeechRecognition
alias VoxDialog.SpeechRecognition.TranscriptionWorker

# Test configuration
IO.puts "=== Speech Recognition Test ==="

# Check if Hugging Face token is configured
token = Application.get_env(:vox_dialog, :huggingface_token)
if token && String.length(token) > 0 do
  IO.puts "✅ Hugging Face token configured (length: #{String.length(token)})"
else
  IO.puts "❌ Hugging Face token not configured"
  IO.puts "Set HUGGINGFACE_TOKEN environment variable and restart"
  System.halt(1)
end

# Check TranscriptionWorker status
case TranscriptionWorker.get_status() do
  status when is_map(status) ->
    IO.puts "✅ TranscriptionWorker is running"
    IO.puts "   Pending: #{status.pending_count}"
    IO.puts "   Active: #{status.active_jobs}"
    IO.puts "   Processed: #{status.processed_count}"
    IO.puts "   Failed: #{status.failed_count}"
  _ ->
    IO.puts "❌ TranscriptionWorker not responding"
end

import Ecto.Query
alias VoxDialog.Voice.AudioClip

# Check for pending audio clips
pending_clips = VoxDialog.Repo.one(
  from a in AudioClip,
  where: a.transcription_status == "pending",
  select: count(a.id)
)

IO.puts "\n=== Audio Clips Status ==="
IO.puts "Pending transcriptions: #{pending_clips}"

# Get total clips
total_clips = VoxDialog.Repo.one(
  from a in AudioClip,
  select: count(a.id)
)

IO.puts "Total audio clips: #{total_clips}"

if total_clips > 0 do
  # Show clip statuses
  statuses = VoxDialog.Repo.all(
    from a in AudioClip,
    group_by: a.transcription_status,
    select: {a.transcription_status, count(a.id)}
  )
  
  IO.puts "\nTranscription status breakdown:"
  Enum.each(statuses, fn {status, count} ->
    IO.puts "  #{status}: #{count}"
  end)
  
  if pending_clips > 0 do
    IO.puts "\n🚀 Processing pending transcriptions..."
    TranscriptionWorker.process_now()
    IO.puts "Check the server logs for transcription progress"
  end
else
  IO.puts "\n💡 No audio clips found. Record some audio at /voice to test transcription"
end

IO.puts "\n=== Test Complete ==="