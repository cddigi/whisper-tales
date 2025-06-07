defmodule VoxDialog.SpeechRecognition.WhisperFaster do
  @moduledoc """
  Faster Whisper backend implementation using ctranslate2.
  Provides optimized inference with lower memory usage.
  """
  
  @behaviour VoxDialog.SpeechRecognition.WhisperBackend
  
  require Logger
  
  defstruct [:config, :model_size, :compute_type, :beam_size, :vad_filter, :vad_parameters]

  @impl true
  def transcribe(audio_data, opts \\ %{}) do
    config = Map.get(opts, :config, %{})
    language = Map.get(opts, :language, "en")
    
    # Encode audio data as base64
    base64_audio = Base.encode64(audio_data)
    
    # Build command arguments
    args = build_command_args(base64_audio, config, language)
    
    case System.cmd("uv", args, stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, %{"error" => error}} ->
            {:error, error}
          {:ok, %{"text" => text} = result} ->
            # Log additional metadata
            Logger.debug("Faster Whisper result: #{inspect(Map.drop(result, ["text"]))}")
            {:ok, text}
          {:error, _} ->
            {:error, "Failed to parse faster whisper output"}
        end
        
      {error_output, _exit_code} ->
        Logger.error("Faster Whisper failed: #{error_output}")
        {:error, "Faster whisper execution failed"}
    end
  end

  @impl true
  def check_availability do
    case System.cmd("uv", ["run", "python", "whisper_faster.py", "--help"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      _ -> {:error, :faster_whisper_not_available}
    end
  end

  @impl true
  def get_info do
    %{
      name: "Faster Whisper",
      backend: :faster,
      description: "Optimized Whisper implementation using ctranslate2",
      features: ["Faster inference", "Lower memory usage", "VAD filtering", "Beam search"],
      models: ["tiny", "tiny.en", "base", "base.en", "small", "small.en", "medium", "medium.en", "large-v3"],
      compute_types: ["int8", "bfloat16", "float16", "float32", "auto"]
    }
  end

  @impl true
  def initialize(config) do
    case check_availability() do
      :ok ->
        state = %__MODULE__{
          config: config,
          model_size: Map.get(config, :model_size, "tiny"),
          compute_type: Map.get(config, :compute_type, "float32"),
          beam_size: Map.get(config, :beam_size, 5),
          vad_filter: Map.get(config, :vad_filter, true),
          vad_parameters: Map.get(config, :vad_parameters, %{})
        }
        {:ok, state}
      error ->
        error
    end
  end

  @impl true
  def cleanup(_state) do
    :ok
  end

  # Private functions

  defp build_command_args(base64_audio, config, language) do
    base_args = [
      "run", "python", "whisper_faster.py", base64_audio,
      "--model", Map.get(config, :model_size, "tiny"),
      "--compute-type", Map.get(config, :compute_type, "auto"),
      "--beam-size", to_string(Map.get(config, :beam_size, 5)),
      "--language", language,
      "--input-type", "base64"
    ]
    
    # Add VAD filter if enabled
    vad_args = if Map.get(config, :vad_filter, true) do
      vad_params = Map.get(config, :vad_parameters, %{})
      if map_size(vad_params) > 0 do
        ["--vad-filter", "--vad-parameters", Jason.encode!(vad_params)]
      else
        ["--vad-filter"]
      end
    else
      []
    end
    
    base_args ++ vad_args
  end
end
