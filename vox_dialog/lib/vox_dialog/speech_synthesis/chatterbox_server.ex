defmodule VoxDialog.SpeechSynthesis.ChatterboxServer do
  @moduledoc """
  GenServer that manages the local Chatterbox TTS model and provides speech synthesis services
  to other processes in the application using direct Python execution with multi-device support.
  """
  
  use GenServer
  require Logger
  
  @name __MODULE__
  @device_detect_script "device_utils.py"
  
  defstruct [:model_available?, :checking?]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: @name)
  end

  @doc """
  Synthesizes speech from text using the local Chatterbox TTS model.
  """
  def synthesize(text) when is_binary(text) do
    GenServer.call(@name, {:synthesize, text}, 30_000)
  end

  @doc """
  Checks if the Chatterbox TTS server is available and ready.
  """
  def ready? do
    GenServer.call(@name, :ready?, 5_000)
  end

  @doc """
  Gets the current status of the Chatterbox server.
  """
  def status do
    GenServer.call(@name, :status, 5_000)
  end

  # GenServer Callbacks

  @impl true
  def init([]) do
    Logger.info("ChatterboxServer starting with direct Python execution...")
    
    # Check model availability asynchronously
    send(self(), :check_server)
    
    state = %__MODULE__{
      model_available?: false,
      checking?: false
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:synthesize, text}, _from, %{model_available?: false} = state) do
    {:reply, {:error, :model_not_available}, state}
  end

  @impl true
  def handle_call({:synthesize, text}, _from, state) do
    # Validate text length to prevent extremely long synthesis
    text_length = String.length(text)
    
    if text_length > 1000 do
      Logger.warning("Text too long: #{text_length} characters (max 1000)")
      {:reply, {:error, :text_too_long}, state}
    else
      result = perform_synthesis(text)
      {:reply, result, state}
    end
  end

  @impl true
  def handle_call(:ready?, _from, state) do
    {:reply, state.model_available?, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      model_available: state.model_available?,
      checking: state.checking?
    }
    {:reply, status, state}
  end

  @impl true
  def handle_info(:check_server, state) do
    Logger.info("Checking Chatterbox TTS model availability...")
    
    new_state = %{state | checking?: true}
    
    case check_server_health() do
      :ok ->
        Logger.info("Chatterbox TTS model loaded and ready")
        {:noreply, %{new_state | model_available?: true, checking?: false}}
        
      {:error, reason} ->
        Logger.error("Chatterbox TTS model not available: #{inspect(reason)}")
        # Retry checking after 30 seconds
        Process.send_after(self(), :check_server, 30_000)
        {:noreply, %{new_state | checking?: false}}
    end
  end

  # Private Functions

  defp check_server_health do
    # Check if we can detect PyTorch devices and run TTS
    case check_pytorch_devices() do
      {:ok, device_info} ->
        Logger.info("PyTorch device detected: #{device_info}")
        
        # Test if we can import Chatterbox TTS
        case test_chatterbox_import() do
          :ok ->
            Logger.info("✅ Chatterbox TTS available and ready")
            :ok
            
          {:error, reason} ->
            Logger.error("❌ Chatterbox TTS import failed: #{inspect(reason)}")
            {:error, {:import_error, reason}}
        end
        
      {:error, reason} ->
        Logger.error("❌ PyTorch device detection failed: #{inspect(reason)}")
        {:error, {:device_error, reason}}
    end
  end

  defp test_chatterbox_import do
    case System.cmd("uv", ["run", "python", "-c", "from chatterbox.tts import ChatterboxTTS; print('OK')"], 
      stderr_to_stdout: true,
      cd: File.cwd!()
    ) do
      {output, 0} ->
        if String.contains?(output, "OK") do
          :ok
        else
          {:error, "Import test failed: #{output}"}
        end
        
      {error_output, _exit_code} ->
        {:error, error_output}
    end
  end

  defp check_pytorch_devices do
    case System.cmd("uv", ["run", "python", @device_detect_script], stderr_to_stdout: true) do
      {output, 0} ->
        # Extract device info from output
        device_line = output 
          |> String.split("\n") 
          |> Enum.find(&String.contains?(&1, "Using"))
        
        if device_line do
          {:ok, String.trim(device_line)}
        else
          {:ok, "Device detected successfully"}
        end
        
      {error_output, _exit_code} ->
        {:error, error_output}
    end
  end

  defp perform_synthesis(text) do
    Logger.info("Starting TTS synthesis for text: #{String.slice(text, 0, 50)}...")
    
    # Use the Python TTS script directly instead of HTTP API
    case synthesize_with_python(text) do
      {:ok, audio_data} ->
        Logger.info("TTS synthesis completed successfully")
        {:ok, audio_data}
      {:error, reason} ->
        Logger.error("TTS synthesis failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp synthesize_with_python(text) do
    # Create a temporary file for the output
    temp_dir = System.tmp_dir!()
    temp_filename = "chatterbox_#{:rand.uniform(999999)}.wav"
    temp_file_path = Path.join(temp_dir, temp_filename)
    
    try do
      # Run the TTS script directly
      case System.cmd("uv", ["run", "python", "test_chatterbox.py", text], 
        stderr_to_stdout: true, 
        cd: File.cwd!()
      ) do
        {_output, 0} ->
          # The script saves to "test_output.wav" by default
          output_file = Path.join(File.cwd!(), "test_output.wav")
          
          case File.read(output_file) do
            {:ok, audio_data} ->
              # Clean up the output file
              File.rm(output_file)
              {:ok, audio_data}
              
            {:error, reason} ->
              Logger.error("Failed to read TTS output file: #{inspect(reason)}")
              {:error, {:file_read_error, reason}}
          end
          
        {error_output, exit_code} ->
          Logger.error("TTS script failed (exit code #{exit_code}): #{error_output}")
          {:error, {:script_error, exit_code, error_output}}
      end
    rescue
      error ->
        Logger.error("TTS synthesis error: #{inspect(error)}")
        {:error, {:synthesis_error, error}}
    end
  end

end