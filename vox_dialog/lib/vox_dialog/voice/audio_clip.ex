defmodule VoxDialog.Voice.AudioClip do
  use Ecto.Schema
  import Ecto.Changeset

  schema "audio_clips" do
    field :clip_id, :string
    field :user_id, :string
    field :audio_data, :binary
    field :duration_ms, :integer
    field :format, :string, default: "webm"
    field :sample_rate, :integer, default: 16000
    field :file_size, :integer
    field :recorded_at, :utc_datetime_usec
    field :transcription_status, :string, default: "pending"
    field :transcribed_text, :string
    field :ai_response, :string
    field :metadata, :map, default: %{}
    field :audio_type, :string, default: "recording"
    field :source_text, :string
    field :accent, :string
    field :voice_settings, :map, default: %{}

    belongs_to :voice_session, VoxDialog.Voice.VoiceSession,
      foreign_key: :session_id, references: :id

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(audio_clip, attrs) do
    audio_clip
    |> cast(attrs, [
      :session_id, :clip_id, :user_id, :audio_data, :duration_ms, 
      :format, :sample_rate, :file_size, :recorded_at, 
      :transcription_status, :transcribed_text, :ai_response, :metadata,
      :audio_type, :source_text, :accent, :voice_settings
    ])
    |> validate_required([:session_id, :clip_id, :user_id, :audio_data, :recorded_at])
    |> validate_inclusion(:transcription_status, ["pending", "processing", "completed", "failed"])
    |> validate_inclusion(:format, ["webm", "wav", "mp3", "ogg"])
    |> validate_inclusion(:audio_type, ["recording", "tts"])
    |> unique_constraint(:clip_id)
  end

  @doc """
  Generates a unique clip ID.
  """
  def generate_clip_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  @doc """
  Calculates file size from audio data.
  """
  def calculate_file_size(audio_data) when is_binary(audio_data) do
    byte_size(audio_data)
  end

  @doc """
  Gets a base64 encoded version of the audio data for playback.
  """
  def get_audio_data_url(%__MODULE__{audio_data: audio_data, format: format}) do
    base64_data = Base.encode64(audio_data)
    "data:audio/#{format};base64,#{base64_data}"
  end
end