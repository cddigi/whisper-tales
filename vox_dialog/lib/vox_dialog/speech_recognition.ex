defmodule VoxDialog.SpeechRecognition do
  @moduledoc """
  Local speech recognition service using Bumblebee with Whisper models.
  Handles audio transcription locally without external API dependencies.
  """
  
  require Logger
  
  @doc """
  Transcribes an audio clip using a local Whisper model.
  
  ## Parameters
  - audio_clip: %AudioClip{} struct with audio_data
  
  ## Returns
  - {:ok, transcription_text} on success
  - {:error, reason} on failure
  """
  def transcribe_audio_clip(audio_clip) do
    Logger.info("Starting local transcription for clip #{audio_clip.clip_id}")
    
    # Update status to processing
    VoxDialog.Voice.update_audio_clip(audio_clip, %{transcription_status: "processing"})
    
    case prepare_audio_for_transcription(audio_clip.audio_data, audio_clip.format) do
      {:ok, processed_audio} ->
        case transcribe_with_local_model(processed_audio) do
          {:ok, transcription} ->
            # Update clip with successful transcription
            VoxDialog.Voice.update_audio_clip(audio_clip, %{
              transcription_status: "completed",
              transcribed_text: transcription
            })
            
            Logger.info("Successfully transcribed clip #{audio_clip.clip_id}: #{String.slice(transcription, 0, 50)}...")
            {:ok, transcription}
            
          {:error, reason} ->
            # Update status to failed
            VoxDialog.Voice.update_audio_clip(audio_clip, %{transcription_status: "failed"})
            Logger.error("Failed to transcribe clip #{audio_clip.clip_id}: #{inspect(reason)}")
            {:error, reason}
        end
        
      {:error, reason} ->
        VoxDialog.Voice.update_audio_clip(audio_clip, %{transcription_status: "failed"})
        Logger.error("Failed to prepare audio for clip #{audio_clip.clip_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Transcribes raw audio data directly.
  
  ## Parameters
  - audio_data: Binary audio data
  - format: Audio format (e.g., "webm", "wav")
  
  ## Returns
  - {:ok, transcription_text} on success
  - {:error, reason} on failure
  """
  def transcribe_audio(audio_data, format \\ "webm") do
    Logger.info("Transcribing raw audio data, size: #{byte_size(audio_data)} bytes, format: #{format}")
    
    case prepare_audio_for_transcription(audio_data, format) do
      {:ok, processed_audio} ->
        transcribe_with_local_model(processed_audio)
        
      {:error, reason} ->
        Logger.error("Failed to prepare raw audio: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Processes a batch of pending audio clips for transcription.
  """
  def process_pending_transcriptions(limit \\ 10) do
    alias VoxDialog.Voice.AudioClip
    import Ecto.Query
    
    # Get pending clips
    pending_clips = VoxDialog.Repo.all(
      from a in AudioClip,
      where: a.transcription_status == "pending",
      limit: ^limit,
      order_by: [asc: a.inserted_at]
    )
    
    Logger.info("Processing #{length(pending_clips)} pending transcriptions")
    
    # Process each clip
    results = Enum.map(pending_clips, fn clip ->
      case transcribe_audio_clip(clip) do
        {:ok, transcription} -> {:ok, clip.clip_id, transcription}
        {:error, reason} -> {:error, clip.clip_id, reason}
      end
    end)
    
    successes = Enum.count(results, fn {status, _, _} -> status == :ok end)
    failures = Enum.count(results, fn {status, _, _} -> status == :error end)
    
    Logger.info("Batch transcription complete: #{successes} successes, #{failures} failures")
    
    {:ok, results}
  end

  @doc """
  Checks if the Whisper model is ready for transcription.
  """
  def model_ready? do
    VoxDialog.SpeechRecognition.WhisperServer.ready?()
  end
  
  @doc """
  Gets the status of the speech recognition system.
  """
  def status do
    VoxDialog.SpeechRecognition.WhisperServer.status()
  end

  # Private Functions

  defp prepare_audio_for_transcription(audio_data, format) do
    case format do
      "webm" ->
        # For webm, we need to convert to a format Nx can handle
        # For now, we'll try to use it directly and see what happens
        {:ok, audio_data}
        
      "wav" ->
        # WAV should work directly
        {:ok, audio_data}
        
      _ ->
        # Try to pass through other formats
        Logger.warning("Unknown audio format: #{format}, attempting passthrough")
        {:ok, audio_data}
    end
  end

  defp transcribe_with_local_model(audio_data) do
    # Use the WhisperServer GenServer for transcription (with longer timeout for large audio files)
    try do
      case VoxDialog.SpeechRecognition.WhisperServer.transcribe(audio_data) do
        {:ok, text} ->
          {:ok, text}
        {:error, :model_not_loaded} ->
          Logger.error("Whisper model not loaded yet. Please wait for model to finish loading.")
          {:error, :model_not_loaded}
        {:error, :audio_too_large} ->
          Logger.error("Audio file too large for transcription (max 25MB)")
          {:error, :audio_too_large}
        {:error, reason} ->
          Logger.error("Transcription failed: #{inspect(reason)}")
          {:error, reason}
      end
    catch
      :exit, {:timeout, _} ->
        Logger.error("Transcription timed out after 2 minutes - audio may be too long or complex")
        {:error, :transcription_timeout}
      error ->
        Logger.error("Unexpected error during transcription: #{inspect(error)}")
        {:error, :unexpected_error}
    end
  end

end