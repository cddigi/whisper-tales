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
    synthesize(text, %{})
  end
  
  @doc """
  Synthesizes speech from text with custom options (accent, voice settings).
  """
  def synthesize(text, options) when is_binary(text) and is_map(options) do
    # Increase timeout for longer text - roughly 1 minute per 100 characters
    text_length = String.length(text)
    timeout = max(60_000, min(300_000, text_length * 600))
    GenServer.call(@name, {:synthesize, text, options}, timeout)
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
  
  @doc """
  Checks if Chatterbox TTS is available.
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
  def handle_call({:synthesize, _text}, _from, %{model_available?: false} = state) do
    {:reply, {:error, :model_not_available}, state}
  end
  
  @impl true
  def handle_call({:synthesize, _text, _options}, _from, %{model_available?: false} = state) do
    {:reply, {:error, :model_not_available}, state}
  end

  @impl true
  def handle_call({:synthesize, text}, _from, state) do
    handle_call({:synthesize, text, %{}}, nil, state)
  end

  @impl true
  def handle_call({:synthesize, text, options}, _from, state) do
    # Validate text length - allow up to 2000 characters but recommend chunking for very long texts
    text_length = String.length(text)
    
    if text_length > 2000 do
      Logger.warning("Text too long: #{text_length} characters (max 2000)")
      {:reply, {:error, :text_too_long}, state}
    else
      # For texts over 800 characters, consider chunking for better performance
      if text_length > 800 do
        Logger.info("Processing long text (#{text_length} chars) - this may take a while...")
        result = perform_synthesis_with_chunking(text, options)
        {:reply, result, state}
      else
        result = perform_synthesis(text, options)
        {:reply, result, state}
      end
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

  defp perform_synthesis(text, options) do
    Logger.info("Starting TTS synthesis for text: #{String.slice(text, 0, 50)}...")
    
    # Use the enhanced Python TTS script with accent and voice settings
    case synthesize_with_python(text, options) do
      {:ok, audio_data} ->
        Logger.info("TTS synthesis completed successfully")
        {:ok, audio_data}
      {:error, reason} ->
        Logger.error("TTS synthesis failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp perform_synthesis_with_chunking(text, options) do
    Logger.info("Starting chunked TTS synthesis for long text...")
    
    # Split text into manageable chunks at sentence boundaries
    chunks = split_text_into_chunks(text, 400)
    Logger.info("Split text into #{length(chunks)} chunks")
    
    # Process each chunk and combine the audio
    case process_chunks(chunks, options, []) do
      {:ok, audio_chunks} ->
        # Combine all audio chunks
        combined_audio = Enum.join(audio_chunks, "")
        Logger.info("Chunked TTS synthesis completed successfully")
        {:ok, combined_audio}
      {:error, reason} ->
        Logger.error("Chunked TTS synthesis failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp split_text_into_chunks(text, max_chunk_size) do
    # Split by sentences first
    sentences = String.split(text, ~r/[.!?]+\s*/, include_captures: true, trim: true)
    
    # Group sentences into chunks that don't exceed max_chunk_size
    {chunks, current_chunk} = 
      Enum.reduce(sentences, {[], ""}, fn sentence, {chunks, current_chunk} ->
        test_chunk = current_chunk <> sentence
        
        if String.length(test_chunk) <= max_chunk_size do
          {chunks, test_chunk}
        else
          # Current chunk is full, start a new one
          new_chunks = if String.length(current_chunk) > 0, do: [current_chunk | chunks], else: chunks
          {new_chunks, sentence}
        end
      end)
    
    # Add the final chunk if it's not empty
    final_chunks = if String.length(current_chunk) > 0, do: [current_chunk | chunks], else: chunks
    
    # Reverse to maintain original order and ensure no empty chunks
    final_chunks
    |> Enum.reverse()
    |> Enum.filter(&(String.length(&1) > 0))
  end
  
  defp process_chunks([], _options, acc), do: {:ok, Enum.reverse(acc)}
  defp process_chunks([chunk | rest], options, acc) do
    case synthesize_with_python(chunk, options) do
      {:ok, audio_data} ->
        process_chunks(rest, options, [audio_data | acc])
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp synthesize_with_python(text, options) do
    # Create a temporary file for the output
    temp_dir = System.tmp_dir!()
    temp_filename = "chatterbox_#{:rand.uniform(999999)}.wav"
    temp_file_path = Path.join(temp_dir, temp_filename)
    
    try do
      # Prepare command arguments for enhanced TTS script
      accent = Map.get(options, "accent", "midwest")
      voice_settings = Map.get(options, "voice_settings", %{})
      voice_settings_json = Jason.encode!(voice_settings)
      
      args = [
        "run", "python", "tts_with_accents.py", text,
        "--accent", accent,
        "--voice-settings", voice_settings_json,
        "--output", temp_file_path
      ]
      
      # Run the enhanced TTS script
      case System.cmd("uv", args, 
        stderr_to_stdout: true, 
        cd: File.cwd!()
      ) do
        {_output, 0} ->
          # Read the generated audio file
          case File.read(temp_file_path) do
            {:ok, audio_data} ->
              # Clean up the output file
              File.rm(temp_file_path)
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