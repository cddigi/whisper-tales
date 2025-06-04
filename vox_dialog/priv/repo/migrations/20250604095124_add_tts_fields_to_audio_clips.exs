defmodule VoxDialog.Repo.Migrations.AddTtsFieldsToAudioClips do
  use Ecto.Migration

  def change do
    alter table(:audio_clips) do
      add :audio_type, :string, default: "recording"  # "recording" or "tts"
      add :source_text, :text  # Original text for TTS clips
      add :accent, :string  # Accent used for TTS generation
      add :voice_settings, :map, default: %{}  # Store pitch, speed, tone settings
    end

    create index(:audio_clips, [:audio_type])
    create index(:audio_clips, [:accent])
  end
end
