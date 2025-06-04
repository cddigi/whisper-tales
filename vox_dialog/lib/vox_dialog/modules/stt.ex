defmodule VoxDialog.Modules.STT do
  @moduledoc """
  Speech-to-Text module implementation.
  Converts audio input to text output using Whisper AI.
  """
  
  @behaviour VoxDialog.ModuleSystem
  
  require Logger
  
  @impl true
  def info do
    %{
      id: "stt",
      name: "Speech-to-Text",
      version: "1.0.0",
      interface: %{
        input: "audio/webm",
        output: "text/plain"
      }
    }
  end
  
  @impl true
  def initialize(_opts) do
    # Check if Whisper is available
    case VoxDialog.SpeechRecognition.WhisperServer.check_availability() do
      :ok -> 
        {:ok, %{status: :ready}}
      {:error, reason} ->
        {:error, {:initialization_failed, reason}}
    end
  end
  
  @impl true
  def process(audio_data, state) when is_binary(audio_data) do
    Logger.info("STT module processing audio data of size: #{byte_size(audio_data)}")
    
    # Create a temporary audio clip for processing
    clip_id = VoxDialog.Voice.AudioClip.generate_clip_id()
    
    case save_and_transcribe(audio_data, clip_id) do
      {:ok, transcription} ->
        {:ok, transcription, state}
      {:error, reason} ->
        Logger.error("STT processing failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @impl true
  def shutdown(_state) do
    Logger.info("STT module shutting down")
    :ok
  end
  
  # Private functions
  
  defp save_and_transcribe(audio_data, clip_id) do
    # Create temporary voice session
    session = %{
      id: System.unique_integer([:positive]),
      session_id: "stt_module_#{clip_id}"
    }
    
    # Create audio clip record
    clip_attrs = %{
      session_id: session.id,
      user_id: "stt_module",
      audio_data: audio_data,
      format: "webm",
      clip_id: clip_id
    }
    
    case VoxDialog.Voice.create_audio_clip(clip_attrs) do
      {:ok, clip} ->
        # Transcribe the audio
        case VoxDialog.SpeechRecognition.WhisperServer.transcribe_audio(clip) do
          {:ok, transcription} ->
            {:ok, transcription}
          error ->
            error
        end
      {:error, reason} ->
        {:error, {:save_failed, reason}}
    end
  end
end