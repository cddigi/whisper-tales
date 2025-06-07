defmodule VoxDialog.SpeechRecognition.WhisperFactory do
  @moduledoc """
  Factory for creating and managing Whisper backend instances.
  """
  
  require Logger

  @backends %{
    vanilla: VoxDialog.SpeechRecognition.WhisperVanilla,
    faster: VoxDialog.SpeechRecognition.WhisperFaster
  }

  @doc """
  Create a backend instance based on configuration.
  """
  def create_backend(backend_type \\ nil) do
    backend_type = backend_type || get_configured_backend()
    
    case Map.get(@backends, backend_type) do
      nil ->
        Logger.error("Unknown Whisper backend: #{backend_type}")
        {:error, :unknown_backend}
        
      module ->
        config = get_backend_config(backend_type)
        
        case module.check_availability() do
          :ok ->
            case module.initialize(config) do
              {:ok, state} ->
                {:ok, {module, state}}
              error ->
                Logger.error("Failed to initialize #{backend_type} backend: #{inspect(error)}")
                try_fallback_backend(backend_type)
            end
            
          {:error, reason} ->
            Logger.warning("#{backend_type} backend not available: #{inspect(reason)}")
            try_fallback_backend(backend_type)
        end
    end
  end

  @doc """
  Get list of available backends.
  """
  def available_backends do
    @backends
    |> Enum.filter(fn {_name, module} ->
      module.check_availability() == :ok
    end)
    |> Enum.map(fn {name, _module} -> name end)
  end

  @doc """
  Get backend information.
  """
  def get_backend_info(backend_type) do
    case Map.get(@backends, backend_type) do
      nil -> {:error, :unknown_backend}
      module -> {:ok, module.get_info()}
    end
  end

  # Private functions

  defp get_configured_backend do
    Application.get_env(:vox_dialog, :whisper, %{})
    |> Map.get(:backend, :faster)
  end

  defp get_fallback_backend do
    Application.get_env(:vox_dialog, :whisper, %{})
    |> Map.get(:fallback_backend, :vanilla)
  end

  defp get_backend_config(backend_type) do
    whisper_config = Application.get_env(:vox_dialog, :whisper, %{})
    
    case backend_type do
      :vanilla -> Map.get(whisper_config, :vanilla_whisper, %{})
      :faster -> Map.get(whisper_config, :faster_whisper, %{})
      _ -> %{}
    end
  end

  defp try_fallback_backend(failed_backend) do
    fallback = get_fallback_backend()
    
    if fallback != failed_backend do
      Logger.info("Trying fallback backend: #{fallback}")
      create_backend(fallback)
    else
      {:error, :no_available_backend}
    end
  end
end
