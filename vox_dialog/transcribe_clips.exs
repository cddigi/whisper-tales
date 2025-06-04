# CLI tool to transcribe existing audio clips in the database
alias VoxDialog.Voice.AudioClip
alias VoxDialog.SpeechRecognition
alias VoxDialog.SpeechRecognition.WhisperServer
import Ecto.Query

IO.puts "=== Audio Clip Transcription Tool ==="

# Check if WhisperServer is ready
case WhisperServer.status() do
  %{model_loaded: true} ->
    IO.puts "✅ WhisperServer is ready"
  %{model_loaded: false, loading: true} ->
    IO.puts "⏳ WhisperServer is loading, waiting..."
    :timer.sleep(5000)
    case WhisperServer.status() do
      %{model_loaded: true} ->
        IO.puts "✅ WhisperServer is now ready"
      _ ->
        IO.puts "❌ WhisperServer still not ready, exiting"
        System.halt(1)
    end
  _ ->
    IO.puts "❌ WhisperServer not available, exiting"
    System.halt(1)
end

# Get all audio clips
all_clips = VoxDialog.Repo.all(
  from a in AudioClip,
  order_by: [desc: a.inserted_at]
)

IO.puts "\n=== Audio Clips Summary ==="
IO.puts "Total clips: #{length(all_clips)}"

if length(all_clips) == 0 do
  IO.puts "No audio clips found in database"
  System.halt(0)
end

# Group by status
status_counts = Enum.group_by(all_clips, & &1.transcription_status)
Enum.each(status_counts, fn {status, clips} ->
  IO.puts "  #{status}: #{length(clips)}"
end)

# Show recent clips with details
IO.puts "\n=== Recent Audio Clips ==="
recent_clips = Enum.take(all_clips, 5)
Enum.each(recent_clips, fn clip ->
  size_kb = (clip.file_size / 1024) |> Float.round(1)
  duration_s = if clip.duration_ms, do: (clip.duration_ms / 1000) |> Float.round(1), else: "unknown"
  
  IO.puts """
  Clip: #{clip.clip_id}
    Status: #{clip.transcription_status}
    Size: #{size_kb} KB
    Duration: #{duration_s}s
    Format: #{clip.format}
    Recorded: #{clip.recorded_at}
    Text: #{if clip.transcribed_text, do: String.slice(clip.transcribed_text, 0, 50) <> "...", else: "none"}
  """
end)

# Ask user which clips to transcribe
IO.puts "\n=== Transcription Options ==="
IO.puts "1. Transcribe pending clips only"
IO.puts "2. Transcribe failed clips"
IO.puts "3. Re-transcribe a specific clip"
IO.puts "4. Transcribe all clips (overwrite existing)"

# Default to processing failed clips to test CLI transcription
choice = "2"
IO.puts "Auto-selecting option 2: Transcribe failed clips to test CLI"

clips_to_process = case choice do
  "1" ->
    pending = Map.get(status_counts, "pending", [])
    IO.puts "Found #{length(pending)} pending clips"
    pending
    
  "2" ->
    failed = Map.get(status_counts, "failed", [])
    IO.puts "Found #{length(failed)} failed clips"
    failed
    
  "3" ->
    IO.puts "Available clips:"
    Enum.with_index(recent_clips) |> Enum.each(fn {clip, idx} ->
      IO.puts "  #{idx + 1}. #{clip.clip_id} (#{clip.transcription_status})"
    end)
    
    clip_choice = case IO.gets("Enter clip number: ") do
      :eof -> 1  # Default to first clip
      input -> String.trim(input) |> String.to_integer()
    end
    if clip_choice >= 1 and clip_choice <= length(recent_clips) do
      [Enum.at(recent_clips, clip_choice - 1)]
    else
      IO.puts "Invalid choice"
      []
    end
    
  "4" ->
    IO.puts "This will re-transcribe ALL #{length(all_clips)} clips"
    confirm = case IO.gets("Are you sure? (y/N): ") do
      :eof -> "n"  # Default to no
      input -> String.trim(input) |> String.downcase()
    end
    if confirm == "y" or confirm == "yes" do
      all_clips
    else
      IO.puts "Cancelled"
      []
    end
    
  _ ->
    IO.puts "Invalid choice"
    []
end

if length(clips_to_process) == 0 do
  IO.puts "No clips to process"
  System.halt(0)
end

IO.puts "\n=== Starting Transcription ==="
IO.puts "Processing #{length(clips_to_process)} clips..."

# Process each clip
Enum.with_index(clips_to_process) |> Enum.each(fn {clip, idx} ->
  IO.puts "\n[#{idx + 1}/#{length(clips_to_process)}] Processing clip: #{clip.clip_id}"
  IO.puts "  Size: #{clip.file_size} bytes, Format: #{clip.format}"
  
  # Time the transcription
  start_time = System.monotonic_time(:millisecond)
  
  case SpeechRecognition.transcribe_audio_clip(clip) do
    {:ok, transcription} ->
      end_time = System.monotonic_time(:millisecond)
      duration_ms = end_time - start_time
      
      IO.puts "  ✅ SUCCESS (#{duration_ms}ms)"
      IO.puts "  Text: #{String.slice(transcription, 0, 100)}..."
      
    {:error, reason} ->
      end_time = System.monotonic_time(:millisecond)
      duration_ms = end_time - start_time
      
      IO.puts "  ❌ FAILED (#{duration_ms}ms): #{inspect(reason)}"
  end
end)

IO.puts "\n=== Transcription Complete ==="

# Show final status
final_clips = VoxDialog.Repo.all(
  from a in AudioClip,
  where: a.id in ^Enum.map(clips_to_process, & &1.id),
  order_by: [desc: a.updated_at]
)

final_status_counts = Enum.group_by(final_clips, & &1.transcription_status)
IO.puts "Final status:"
Enum.each(final_status_counts, fn {status, clips} ->
  IO.puts "  #{status}: #{length(clips)}"
end)

# Show successful transcriptions
completed = Map.get(final_status_counts, "completed", [])
if length(completed) > 0 do
  IO.puts "\n=== Successful Transcriptions ==="
  Enum.each(completed, fn clip ->
    IO.puts "#{clip.clip_id}: #{clip.transcribed_text}"
  end)
end