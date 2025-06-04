defmodule VoxDialog.Voice.EnvironmentalSound do
  use Ecto.Schema
  import Ecto.Changeset

  schema "environmental_sounds" do
    field :sound_type, :string
    field :confidence, :float
    field :detected_at, :utc_datetime_usec
    field :notified, :boolean, default: false

    belongs_to :voice_session, VoxDialog.Voice.VoiceSession,
      foreign_key: :session_id, references: :id

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(environmental_sound, attrs) do
    environmental_sound
    |> cast(attrs, [:session_id, :sound_type, :confidence, :detected_at, :notified])
    |> validate_required([:session_id, :sound_type, :detected_at])
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end
end