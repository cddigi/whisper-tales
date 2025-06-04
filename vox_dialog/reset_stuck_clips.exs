# Reset clips stuck in "processing" status back to "pending"
alias VoxDialog.Voice.AudioClip
import Ecto.Query

IO.puts "=== Resetting Stuck Clips ==="

# Find clips stuck in processing
stuck_clips = VoxDialog.Repo.all(
  from a in AudioClip,
  where: a.transcription_status == "processing"
)

IO.puts "Found #{length(stuck_clips)} clips stuck in processing status"

if length(stuck_clips) > 0 do
  Enum.each(stuck_clips, fn clip ->
    IO.puts "Resetting clip: #{clip.clip_id}"
  end)
  
  # Reset all stuck clips to pending
  {count, _} = VoxDialog.Repo.update_all(
    from(a in AudioClip, where: a.transcription_status == "processing"),
    set: [transcription_status: "pending", updated_at: DateTime.utc_now()]
  )
  
  IO.puts "✅ Reset #{count} clips from 'processing' to 'pending'"
else
  IO.puts "No stuck clips found"
end

IO.puts "=== Reset Complete ==="