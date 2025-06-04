defmodule VoxDialog.Repo.Migrations.CreateVoiceSessions do
  use Ecto.Migration

  def change do
    create table(:voice_sessions) do
      add :session_id, :string, null: false
      add :user_id, :string, null: false
      add :status, :string, default: "active"
      add :started_at, :utc_datetime_usec, null: false
      add :ended_at, :utc_datetime_usec
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:voice_sessions, [:session_id])
    create index(:voice_sessions, [:user_id])
    create index(:voice_sessions, [:status])
    create index(:voice_sessions, [:started_at])

    create table(:conversation_messages) do
      add :session_id, references(:voice_sessions, on_delete: :delete_all), null: false
      add :type, :string, null: false # "user" or "assistant"
      add :content, :text
      add :confidence, :float
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:conversation_messages, [:session_id])
    create index(:conversation_messages, [:inserted_at])

    create table(:environmental_sounds) do
      add :session_id, references(:voice_sessions, on_delete: :delete_all), null: false
      add :sound_type, :string, null: false
      add :confidence, :float
      add :detected_at, :utc_datetime_usec, null: false
      add :notified, :boolean, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:environmental_sounds, [:session_id])
    create index(:environmental_sounds, [:sound_type])
    create index(:environmental_sounds, [:detected_at])

    create table(:user_preferences) do
      add :user_id, :string, null: false
      add :notification_preferences, :map, default: %{}
      add :voice_settings, :map, default: %{}
      add :audio_processing_config, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:user_preferences, [:user_id])
  end
end