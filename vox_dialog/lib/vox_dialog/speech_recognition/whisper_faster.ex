defmodule VoxDialog.SpeechRecognition.WhisperFaster do
  @moduledoc """
  Faster Whisper backend implementation using ctranslate2.
  Uses ctranslate2-4you repositories for all models.
  """
  
  @behaviour VoxDialog.SpeechRecognition.WhisperBackend
  
  require Logger
  
  defstruct [:config, :model_size, :beam_size, :vad_filter, :vad_parameters, :language]

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
        # Extract JSON from output (might have debug messages before it)
        json_output = extract_json_from_output(output)
        
        case Jason.decode(json_output) do
          {:ok, %{"error" => error}} ->
            {:error, error}
          {:ok, %{"text" => text} = result} ->
            # Log additional metadata including model repository
            Logger.debug("Faster Whisper result: #{inspect(Map.drop(result, ["text"]))}")
            {:ok, text}
          {:error, decode_error} ->
            Logger.error("Failed to parse faster whisper output: #{inspect(decode_error)}")
            Logger.error("Raw output was: #{inspect(output)}")
            {:error, "Failed to parse faster whisper output"}
        end
        
      {error_output, exit_code} ->
        Logger.error("Faster Whisper failed with exit code #{exit_code}: #{error_output}")
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
  
  defp extract_json_from_output(output) do
    # Find the first '{' and extract from there
    case String.split(output, "\n") do
      lines when is_list(lines) ->
        # Find the line that starts with '{'
        Enum.find(lines, "{}", fn line -> 
          String.trim(line) |> String.starts_with?("{")
        end)
      _ -> output
    end
  end

  @impl true
  def get_info do
    # Get available models
    available_models = case get_available_models() do
      {:ok, models} -> models
      _ -> ["tiny", "base", "small", "medium", "large"]  # Fallback
    end
    
    %{
      name: "Faster Whisper (ctranslate2-4you)",
      backend: :faster,
      description: "Optimized Whisper implementation using ctranslate2 float32 models",
      features: ["Faster inference", "Lower memory usage", "VAD filtering", "Beam search", "English-only models", "Distil models"],
      models: available_models,
      compute_type: "float32",
      repository: "ctranslate2-4you"
    }
  end

  @impl true
  def initialize(config) do
    case check_availability() do
      :ok ->
        state = %__MODULE__{
          config: config,
          model_size: Map.get(config, :model_size, "tiny"),
          beam_size: Map.get(config, :beam_size, 5),
          vad_filter: Map.get(config, :vad_filter, true),
          vad_parameters: Map.get(config, :vad_parameters, %{}),
          language: Map.get(config, :language, "en")
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

  # Public function to get available models
  def get_available_models do
    case System.cmd("uv", ["run", "python", "whisper_faster.py", "--list-models"], stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, %{"available_models" => models}} -> {:ok, models}
          _ -> {:error, :failed_to_parse_models}
        end
      _ ->
        {:error, :failed_to_get_models}
    end
  end

  # Private functions

  defp build_command_args(base64_audio, config, language) do
    base_args = [
      "run", "python", "whisper_faster.py", base64_audio,
      "--model", Map.get(config, :model_size, "tiny"),
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
