defmodule VoxDialog.SpeechRecognition.WhisperVanilla do
  @moduledoc """
  Vanilla OpenAI Whisper backend implementation.
  Uses the original whisper CLI for transcription.
  """
  
  @behaviour VoxDialog.SpeechRecognition.WhisperBackend
  
  require Logger
  
  defstruct [:config, :model]

  @impl true
  def transcribe(audio_data, opts \\ %{}) do
    config = Map.get(opts, :config, %{})
    model = Map.get(config, :model, "tiny")
    language = Map.get(opts, :language, "en")
    
    # Encode audio data as base64
    base64_audio = Base.encode64(audio_data)
    
    # Build command arguments
    args = [
      "run", "python", "whisper_vanilla.py", base64_audio,
      "--model", model,
      "--language", language,
      "--input-type", "base64"
    ]
    
    case System.cmd("uv", args, stderr_to_stdout: true) do
      {output, 0} ->
        # Extract JSON from output (might have debug messages before it)
        json_output = extract_json_from_output(output)
        
        case Jason.decode(json_output) do
          {:ok, %{"error" => error}} ->
            {:error, error}
          {:ok, %{"text" => text}} ->
            {:ok, text}
          {:error, _} ->
            {:error, "Failed to parse vanilla whisper output"}
        end
        
      {error_output, _exit_code} ->
        Logger.error("Vanilla Whisper failed: #{error_output}")
        {:error, "Vanilla whisper execution failed"}
    end
  end

  @impl true
  def check_availability do
    case System.cmd("uv", ["run", "python", "whisper_vanilla.py", "--help"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      _ -> {:error, :vanilla_whisper_not_available}
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
    %{
      name: "Vanilla OpenAI Whisper",
      backend: :vanilla,
      description: "Original OpenAI Whisper implementation",
      features: ["Multiple model sizes", "Language detection", "CLI-based"],
      models: ["tiny", "base", "small", "medium", "large"]
    }
  end

  @impl true
  def initialize(config) do
    case check_availability() do
      :ok ->
        state = %__MODULE__{
          config: config,
          model: Map.get(config, :model, "tiny")
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
end
