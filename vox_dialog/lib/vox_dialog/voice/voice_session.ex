defmodule VoxDialog.Voice.VoiceSession do
  use Ecto.Schema
  import Ecto.Changeset

  schema "voice_sessions" do
    field :session_id, :string
    field :user_id, :string
    field :status, :string, default: "active"
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    has_many :conversation_messages, VoxDialog.Voice.ConversationMessage, 
      foreign_key: :session_id, references: :id
    has_many :environmental_sounds, VoxDialog.Voice.EnvironmentalSound,
      foreign_key: :session_id, references: :id

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(voice_session, attrs) do
    voice_session
    |> cast(attrs, [:session_id, :user_id, :status, :started_at, :ended_at, :metadata])
    |> validate_required([:session_id, :user_id, :started_at])
    |> unique_constraint(:session_id)
    |> validate_inclusion(:status, ["active", "completed", "failed"])
  end
end