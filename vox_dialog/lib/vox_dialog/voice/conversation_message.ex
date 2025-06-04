defmodule VoxDialog.Voice.ConversationMessage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "conversation_messages" do
    field :type, :string
    field :content, :string
    field :confidence, :float
    field :metadata, :map, default: %{}

    belongs_to :voice_session, VoxDialog.Voice.VoiceSession,
      foreign_key: :session_id, references: :id

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(conversation_message, attrs) do
    conversation_message
    |> cast(attrs, [:session_id, :type, :content, :confidence, :metadata])
    |> validate_required([:session_id, :type])
    |> validate_inclusion(:type, ["user", "assistant"])
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end
end