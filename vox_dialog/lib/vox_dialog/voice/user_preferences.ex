defmodule VoxDialog.Voice.UserPreferences do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_preferences" do
    field :user_id, :string
    field :notification_preferences, :map, default: %{}
    field :voice_settings, :map, default: %{}
    field :audio_processing_config, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(user_preferences, attrs) do
    user_preferences
    |> cast(attrs, [:user_id, :notification_preferences, :voice_settings, :audio_processing_config])
    |> validate_required([:user_id])
    |> unique_constraint(:user_id)
  end
end