defmodule VoxDialog.SpeechRecognition.WhisperServer do
  @moduledoc """
  GenServer that manages Whisper backends and provides transcription services
  to other processes in the application.
  """
  
  use GenServer
  require Logger
  
  @name __MODULE__
  
  defstruct [:backend_module, :backend_state, :backend_type, :model_loaded?, :loading?]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: @name)
  end

  @doc """
  Transcribes audio data using the configured Whisper backend.
  """
  def transcribe(audio_data) when is_binary(audio_data) do
    # Increase timeout to 2 minutes for large audio files or slow processing
    GenServer.call(@name, {:transcribe, audio_data}, 120_000)
  end

  @doc """
  Checks if the Whisper backend is loaded and ready.
  """
  def ready? do
    GenServer.call(@name, :ready?, 5_000)
  end

  @doc """
  Gets the current status of the Whisper server.
  """
  def status do
    GenServer.call(@name, :status, 5_000)
  end
  
  @doc """
  Gets information about the current backend.
  """
  def get_backend_info do
    GenServer.call(@name, :get_backend_info, 5_000)
  end
  
  @doc """
  Switch to a different backend at runtime.
  """
  def switch_backend(backend_type) do
    GenServer.call(@name, {:switch_backend, backend_type}, 30_000)
  end
  
  @doc """
  Get list of available backends.
  """
  def available_backends do
    VoxDialog.SpeechRecognition.WhisperFactory.available_backends()
  end
  
  @doc """
  Alias for transcribe/1 to maintain compatibility.
  """
  def transcribe_audio(audio_clip) do
    transcribe(audio_clip.audio_data)
  end
  
  @doc """
  Checks if Whisper is available.
  """
  def check_availability do
    case GenServer.call(@name, :ready?, 5_000) do
      true -> :ok
      false -> {:error, :not_available}
    end
  end

  # GenServer Callbacks

  @impl true
  def init([]) do
    Logger.info("WhisperServer starting with configurable backend...")
    
    # Initialize backend asynchronously
    send(self(), :initialize_backend)
    
    state = %__MODULE__{
      backend_module: nil,
      backend_state: nil,
      backend_type: nil,
      model_loaded?: false,
      loading?: true
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:transcribe, _audio_data}, _from, %{model_loaded?: false} = state) do
    {:reply, {:error, :model_not_loaded}, state}
  end

  def handle_call({:transcribe, audio_data}, _from, %{backend_module: module, backend_state: _backend_state} = state) do
    # Add size check to prevent very large audio files from timing out
    audio_size_mb = byte_size(audio_data) / (1024 * 1024)
    
    if audio_size_mb > 25 do
      Logger.warning("Audio file too large: #{:erlang.float_to_binary(audio_size_mb, [{:decimals, 1}])}MB (max 25MB)")
      {:reply, {:error, :audio_too_large}, state}
    else
      opts = %{config: get_backend_config(state.backend_type)}
      result = module.transcribe(audio_data, opts)
      {:reply, result, state}
    end
  end

  @impl true
  def handle_call(:ready?, _from, state) do
    {:reply, state.model_loaded?, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      model_loaded: state.model_loaded?,
      loading: state.loading?,
      backend_type: state.backend_type,
      backend_available: state.backend_module != nil
    }
    {:reply, status, state}
  end

  @impl true
  def handle_call(:get_backend_info, _from, %{backend_module: nil} = state) do
    {:reply, {:error, :no_backend_loaded}, state}
  end

  @impl true
  def handle_call(:get_backend_info, _from, %{backend_module: module} = state) do
    info = module.get_info()
    {:reply, {:ok, info}, state}
  end

  @impl true
  def handle_call({:switch_backend, backend_type}, _from, state) do
    Logger.info("Switching to backend: #{backend_type}")
    
    # Cleanup current backend
    if state.backend_module && state.backend_state do
      state.backend_module.cleanup(state.backend_state)
    end
    
    # Initialize new backend
    case VoxDialog.SpeechRecognition.WhisperFactory.create_backend(backend_type) do
      {:ok, {module, backend_state}} ->
        new_state = %{state |
          backend_module: module,
          backend_state: backend_state,
          backend_type: backend_type,
          model_loaded?: true,
          loading?: false
        }
        Logger.info("Successfully switched to #{backend_type} backend")
        {:reply, :ok, new_state}
        
      {:error, reason} ->
        Logger.error("Failed to switch to #{backend_type} backend: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:initialize_backend, state) do
    Logger.info("Initializing Whisper backend...")
    
    case VoxDialog.SpeechRecognition.WhisperFactory.create_backend() do
      {:ok, {module, backend_state}} ->
        backend_type = get_backend_type_from_module(module)
        Logger.info("Successfully initialized #{backend_type} backend")
        
        new_state = %{state |
          backend_module: module,
          backend_state: backend_state,
          backend_type: backend_type,
          model_loaded?: true,
          loading?: false
        }
        {:noreply, new_state}
        
      {:error, reason} ->
        Logger.error("Failed to initialize any Whisper backend: #{inspect(reason)}")
        # Retry after 30 seconds
        Process.send_after(self(), :initialize_backend, 30_000)
        {:noreply, %{state | loading?: false}}
    end
  end

  # Private Functions

  defp get_backend_config(backend_type) do
    whisper_config = Application.get_env(:vox_dialog, :whisper, [])
    
    case backend_type do
      :vanilla -> Keyword.get(whisper_config, :vanilla_whisper, %{})
      :faster -> Keyword.get(whisper_config, :faster_whisper, %{})
      _ -> %{}
    end
  end

  defp get_backend_type_from_module(module) do
    case module do
      VoxDialog.SpeechRecognition.WhisperVanilla -> :vanilla
      VoxDialog.SpeechRecognition.WhisperFaster -> :faster
      _ -> :unknown
    end
  end
end
