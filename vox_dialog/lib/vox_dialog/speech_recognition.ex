defmodule VoxDialog.SpeechRecognition do
  @moduledoc """
  Local speech recognition service using configurable Whisper backends.
  Handles audio transcription locally without external API dependencies.
  """
  
  require Logger
  
  @doc """
  Transcribes an audio clip using the configured Whisper backend.
  
  ## Parameters
  - audio_clip: %AudioClip{} struct with audio_data
  - opts: Optional backend-specific options
  
  ## Returns
  - {:ok, transcription_text} on success
  - {:error, reason} on failure
  """
  def transcribe_audio_clip(audio_clip, opts \\ %{}) do
    Logger.info("Starting transcription for clip #{audio_clip.clip_id}")
    
    # Update status to processing
    VoxDialog.Voice.update_audio_clip(audio_clip, %{transcription_status: "processing"})
    
    {:ok, processed_audio} = prepare_audio_for_transcription(audio_clip.audio_data, audio_clip.format)
    case transcribe_with_backend(processed_audio, opts) do
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
  end

  @doc """
  Transcribes raw audio data directly.
  
  ## Parameters
  - audio_data: Binary audio data
  - format: Audio format (e.g., "webm", "wav")
  - opts: Optional backend-specific options
  
  ## Returns
  - {:ok, transcription_text} on success
  - {:error, reason} on failure
  """
  def transcribe_audio(audio_data, format \\ "webm", opts \\ %{}) do
    Logger.info("Transcribing raw audio data, size: #{byte_size(audio_data)} bytes, format: #{format}")
    
    {:ok, processed_audio} = prepare_audio_for_transcription(audio_data, format)
    transcribe_with_backend(processed_audio, opts)
  end

  @doc """
  Processes a batch of pending audio clips for transcription.
  """
  def process_pending_transcriptions(limit \\ 10, backend_type \\ nil) do
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
    
    # Switch backend if specified
    if backend_type do
      case VoxDialog.SpeechRecognition.WhisperServer.switch_backend(backend_type) do
        :ok -> Logger.info("Switched to #{backend_type} backend for batch processing")
        {:error, reason} -> Logger.warning("Failed to switch backend: #{inspect(reason)}")
      end
    end
    
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
  Checks if the Whisper backend is ready for transcription.
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

  @doc """
  Gets information about the current backend.
  """
  def get_backend_info do
    VoxDialog.SpeechRecognition.WhisperServer.get_backend_info()
  end

  @doc """
  Gets list of available backends.
  """
  def available_backends do
    VoxDialog.SpeechRecognition.WhisperServer.available_backends()
  end

  @doc """
  Switch to a different backend.
  """
  def switch_backend(backend_type) do
    VoxDialog.SpeechRecognition.WhisperServer.switch_backend(backend_type)
  end

  # Private Functions

  defp prepare_audio_for_transcription(audio_data, format) do
    case format do
      "webm" ->
        # For webm, we need to convert to a format the backend can handle
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

  defp transcribe_with_backend(audio_data, _opts) do
    # Use the WhisperServer GenServer for transcription
    try do
      case VoxDialog.SpeechRecognition.WhisperServer.transcribe(audio_data) do
        {:ok, text} ->
          {:ok, text}
        {:error, :model_not_loaded} ->
          Logger.error("Whisper backend not loaded yet. Please wait for backend to finish loading.")
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
      kind, error ->
        Logger.error("Unexpected error during transcription (#{kind}): #{inspect(error)}")
        {:error, :unexpected_error}
    end
  end
end
