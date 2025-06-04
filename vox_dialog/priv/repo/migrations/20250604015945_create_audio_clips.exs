defmodule VoxDialog.Repo.Migrations.CreateAudioClips do
  use Ecto.Migration

  def change do
    create table(:audio_clips) do
      add :session_id, references(:voice_sessions, on_delete: :delete_all), null: false
      add :clip_id, :string, null: false
      add :user_id, :string, null: false
      add :audio_data, :binary, null: false
      add :duration_ms, :integer
      add :format, :string, default: "webm"
      add :sample_rate, :integer, default: 16000
      add :file_size, :integer
      add :recorded_at, :utc_datetime_usec, null: false
      add :transcription_status, :string, default: "pending"
      add :transcribed_text, :text
      add :ai_response, :text
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:audio_clips, [:session_id])
    create index(:audio_clips, [:user_id])
    create index(:audio_clips, [:recorded_at])
    create index(:audio_clips, [:transcription_status])
    create unique_index(:audio_clips, [:clip_id])
  end
end