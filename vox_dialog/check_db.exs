alias VoxDialog.Repo
alias VoxDialog.Voice.{VoiceSession, ConversationMessage, EnvironmentalSound, AudioClip}

# Check voice sessions
sessions = Repo.all(VoiceSession)
IO.puts "=== Voice Sessions (#{length(sessions)}) ==="
Enum.each(sessions, fn session ->
  IO.puts "Session ID: #{session.session_id}"
  IO.puts "User ID: #{session.user_id}"
  IO.puts "Status: #{session.status}"
  IO.puts "Started: #{session.started_at}"
  IO.puts "---"
end)

# Check conversation messages
messages = Repo.all(ConversationMessage)
IO.puts "\n=== Conversation Messages (#{length(messages)}) ==="
Enum.each(messages, fn message ->
  IO.puts "Type: #{message.type}, Content: #{message.content}"
end)

# Check environmental sounds
sounds = Repo.all(EnvironmentalSound)
IO.puts "\n=== Environmental Sounds (#{length(sounds)}) ==="
Enum.each(sounds, fn sound ->
  IO.puts "Type: #{sound.sound_type}, Confidence: #{sound.confidence}"
end)

# Check audio clips
clips = Repo.all(AudioClip)
IO.puts "\n=== Audio Clips (#{length(clips)}) ==="
Enum.each(clips, fn clip ->
  IO.puts "Clip ID: #{clip.clip_id}, User: #{clip.user_id}, Duration: #{clip.duration_ms}ms, Size: #{clip.file_size} bytes"
end)