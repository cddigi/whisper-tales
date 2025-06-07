defmodule VoxDialog.SpeechRecognition.WhisperBackend do
  @moduledoc """
  Behavior for Whisper backend implementations.
  Defines the common interface that all Whisper backends must implement.
  """

  @doc """
  Transcribe audio data to text.
  Returns {:ok, text} or {:error, reason}
  """
  @callback transcribe(audio_data :: binary(), opts :: map()) :: {:ok, String.t()} | {:error, any()}

  @doc """
  Check if the backend is available and ready.
  Returns :ok or {:error, reason}
  """
  @callback check_availability() :: :ok | {:error, any()}

  @doc """
  Get information about the backend.
  Returns a map with backend details.
  """
  @callback get_info() :: map()

  @doc """
  Initialize the backend with configuration.
  Returns {:ok, state} or {:error, reason}
  """
  @callback initialize(config :: map()) :: {:ok, any()} | {:error, any()}

  @doc """
  Cleanup backend resources.
  """
  @callback cleanup(state :: any()) :: :ok
end
