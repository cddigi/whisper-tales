defmodule VoxDialog.Voice do
  @moduledoc """
  The Voice context for managing voice sessions, conversations, and related data.
  """

  import Ecto.Query, warn: false
  alias VoxDialog.Repo

  alias VoxDialog.Voice.{VoiceSession, ConversationMessage, EnvironmentalSound, UserPreferences, AudioClip}

  # Voice Sessions

  @doc """
  Creates a new voice session.
  """
  def create_voice_session(attrs \\ %{}) do
    attrs = Map.put(attrs, :started_at, DateTime.utc_now())
    
    %VoiceSession{}
    |> VoiceSession.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a voice session by session_id.
  """
  def get_voice_session_by_session_id(session_id) do
    Repo.get_by(VoiceSession, session_id: session_id)
  end
  
  @doc """
  Gets a voice session by database ID.
  """
  def get_voice_session(id) do
    Repo.get(VoiceSession, id)
  end

  @doc """
  Updates a voice session.
  """
  def update_voice_session(%VoiceSession{} = voice_session, attrs) do
    voice_session
    |> VoiceSession.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Ends a voice session.
  """
  def end_voice_session(session_id) do
    case get_voice_session_by_session_id(session_id) do
      nil -> {:error, :not_found}
      session -> 
        update_voice_session(session, %{
          status: "completed",
          ended_at: DateTime.utc_now()
        })
    end
  end

  # Conversation Messages

  @doc """
  Creates a conversation message.
  """
  def create_conversation_message(attrs \\ %{}) do
    %ConversationMessage{}
    |> ConversationMessage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists conversation messages for a session.
  """
  def list_conversation_messages(session_id) do
    from(m in ConversationMessage,
      where: m.session_id == ^session_id,
      order_by: [asc: m.inserted_at]
    )
    |> Repo.all()
  end

  # Environmental Sounds

  @doc """
  Records a detected environmental sound.
  """
  def create_environmental_sound(attrs \\ %{}) do
    attrs = Map.put(attrs, :detected_at, DateTime.utc_now())
    
    %EnvironmentalSound{}
    |> EnvironmentalSound.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists environmental sounds for a session.
  """
  def list_environmental_sounds(session_id) do
    from(s in EnvironmentalSound,
      where: s.session_id == ^session_id,
      order_by: [desc: s.detected_at]
    )
    |> Repo.all()
  end

  @doc """
  Marks an environmental sound as notified.
  """
  def mark_sound_notified(%EnvironmentalSound{} = sound) do
    sound
    |> EnvironmentalSound.changeset(%{notified: true})
    |> Repo.update()
  end

  # User Preferences

  @doc """
  Gets or creates user preferences.
  """
  def get_or_create_user_preferences(user_id) do
    case Repo.get_by(UserPreferences, user_id: user_id) do
      nil -> 
        %UserPreferences{}
        |> UserPreferences.changeset(%{user_id: user_id})
        |> Repo.insert()
      preferences -> 
        {:ok, preferences}
    end
  end

  @doc """
  Updates user preferences.
  """
  def update_user_preferences(%UserPreferences{} = preferences, attrs) do
    preferences
    |> UserPreferences.changeset(attrs)
    |> Repo.update()
  end

  # Audio Clips

  @doc """
  Creates an audio clip.
  """
  def create_audio_clip(attrs \\ %{}) do
    attrs = 
      attrs
      |> Map.put(:recorded_at, DateTime.utc_now())
      |> Map.put(:clip_id, AudioClip.generate_clip_id())
      |> Map.put(:file_size, AudioClip.calculate_file_size(attrs[:audio_data] || <<>>))
    
    %AudioClip{}
    |> AudioClip.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets an audio clip by clip_id.
  """
  def get_audio_clip_by_clip_id(clip_id) do
    Repo.get_by(AudioClip, clip_id: clip_id)
  end

  @doc """
  Lists audio clips for a session.
  """
  def list_audio_clips_for_session(session_id) do
    from(a in AudioClip,
      where: a.session_id == ^session_id,
      order_by: [desc: a.recorded_at]
    )
    |> Repo.all()
  end

  @doc """
  Lists audio clips for a user.
  """
  def list_audio_clips_for_user(user_id, limit \\ 50) do
    from(a in AudioClip,
      where: a.user_id == ^user_id,
      order_by: [desc: a.recorded_at],
      limit: ^limit,
      preload: [:voice_session]
    )
    |> Repo.all()
  end

  @doc """
  Updates an audio clip.
  """
  def update_audio_clip(%AudioClip{} = audio_clip, attrs) do
    audio_clip
    |> AudioClip.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an audio clip.
  """
  def delete_audio_clip(%AudioClip{} = audio_clip) do
    Repo.delete(audio_clip)
  end

  # Analytics

  @doc """
  Gets session statistics for a user.
  """
  def get_user_session_stats(user_id) do
    sessions = from(s in VoiceSession,
      where: s.user_id == ^user_id,
      select: %{
        total_sessions: count(s.id),
        active_sessions: sum(fragment("CASE WHEN ? = 'active' THEN 1 ELSE 0 END", s.status)),
        avg_duration: avg(fragment("EXTRACT(EPOCH FROM (? - ?))", s.ended_at, s.started_at))
      }
    )
    |> Repo.one()

    messages = from(m in ConversationMessage,
      join: s in VoiceSession, on: m.session_id == s.id,
      where: s.user_id == ^user_id,
      group_by: m.type,
      select: {m.type, count(m.id)}
    )
    |> Repo.all()
    |> Enum.into(%{})

    audio_clips = from(a in AudioClip,
      where: a.user_id == ^user_id,
      select: %{
        total_clips: count(a.id),
        total_duration: sum(a.duration_ms),
        transcribed_clips: sum(fragment("CASE WHEN ? = 'completed' THEN 1 ELSE 0 END", a.transcription_status))
      }
    )
    |> Repo.one()

    %{
      sessions: sessions,
      messages: messages,
      audio_clips: audio_clips
    }
  end
end