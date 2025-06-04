defmodule VoxDialog.Modules.TTS do
  @moduledoc """
  Text-to-Speech module implementation.
  Converts text input to audio output using Chatterbox TTS.
  """
  
  @behaviour VoxDialog.ModuleSystem
  
  require Logger
  
  @impl true
  def info do
    %{
      id: "tts",
      name: "Text-to-Speech",
      version: "1.0.0",
      interface: %{
        input: "text/plain",
        output: "audio/wav"
      }
    }
  end
  
  @impl true
  def initialize(opts) do
    default_settings = %{
      accent: "midwest",
      voice_settings: %{
        pitch: 1.0,
        speed: 1.0,
        tone: "neutral"
      }
    }
    
    state = Map.merge(default_settings, opts)
    
    # Check if Chatterbox is available
    case VoxDialog.SpeechSynthesis.ChatterboxServer.check_availability() do
      :ok ->
        {:ok, state}
      {:error, reason} ->
        {:error, {:initialization_failed, reason}}
    end
  end
  
  @impl true
  def process(text, state) when is_binary(text) do
    Logger.info("TTS module processing text of length: #{String.length(text)}")
    
    options = %{
      "accent" => state.accent,
      "voice_settings" => state.voice_settings
    }
    
    case VoxDialog.SpeechSynthesis.ChatterboxServer.synthesize(text, options) do
      {:ok, audio_data} ->
        {:ok, audio_data, state}
      {:error, reason} ->
        Logger.error("TTS processing failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @impl true
  def shutdown(_state) do
    Logger.info("TTS module shutting down")
    :ok
  end
end