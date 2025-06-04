defmodule VoxDialog.SpeechRecognition.WhisperServer do
  @moduledoc """
  GenServer that manages the local Whisper model and provides transcription services
  to other processes in the application.
  """
  
  use GenServer
  require Logger
  
  @name __MODULE__
  
  defstruct [:serving, :model_loaded?, :loading?]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: @name)
  end

  @doc """
  Transcribes audio data using the loaded Whisper model.
  """
  def transcribe(audio_data) when is_binary(audio_data) do
    # Increase timeout to 2 minutes for large audio files or slow processing
    GenServer.call(@name, {:transcribe, audio_data}, 120_000)
  end

  @doc """
  Checks if the Whisper model is loaded and ready.
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

  # GenServer Callbacks

  @impl true
  def init([]) do
    Logger.info("WhisperServer starting with CLI backend...")
    
    # Check CLI availability asynchronously
    send(self(), :check_cli)
    
    state = %__MODULE__{
      serving: nil,
      model_loaded?: false,
      loading?: false
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:transcribe, audio_data}, _from, %{model_loaded?: false} = state) do
    {:reply, {:error, :model_not_loaded}, state}
  end

  @impl true
  def handle_call({:transcribe, audio_data}, _from, %{serving: serving} = state) do
    # Add size check to prevent very large audio files from timing out
    audio_size_mb = byte_size(audio_data) / (1024 * 1024)
    
    if audio_size_mb > 25 do
      Logger.warning("Audio file too large: #{:erlang.float_to_binary(audio_size_mb, [{:decimals, 1}])}MB (max 25MB)")
      {:reply, {:error, :audio_too_large}, state}
    else
      result = perform_transcription(serving, audio_data)
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
      loading: state.loading?
    }
    {:reply, status, state}
  end

  @impl true
  def handle_info(:check_cli, state) do
    Logger.info("Checking CLI tools availability...")
    
    new_state = %{state | loading?: true}
    
    case check_cli_tools() do
      :ok ->
        Logger.info("CLI tools available - WhisperServer ready")
        {:noreply, %{new_state | model_loaded?: true, loading?: false}}
        
      {:error, reason} ->
        Logger.error("CLI tools not available: #{inspect(reason)}")
        # Retry checking after 30 seconds
        Process.send_after(self(), :check_cli, 30_000)
        {:noreply, %{new_state | loading?: false}}
    end
  end

  # Private Functions

  defp check_cli_tools do
    # Check if Whisper CLI is available via uv
    case System.cmd("uv", ["run", "whisper", "--help"], stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.info("✅ Whisper CLI available via uv")
        
        # Check if FFmpeg is available
        case System.cmd("ffmpeg", ["-version"], stderr_to_stdout: true) do
          {_output, 0} ->
            Logger.info("✅ FFmpeg available")
            :ok
            
          {_error, _} ->
            Logger.error("❌ FFmpeg not available")
            {:error, :ffmpeg_not_found}
        end
        
      {_error, _} ->
        Logger.error("❌ Whisper CLI not available via uv")
        {:error, :whisper_not_found}
    end
  end

  defp perform_transcription(_serving, audio_data) do
    Logger.info("Starting CLI transcription for #{byte_size(audio_data)} bytes of audio data")
    
    # Use CLI Whisper for actual transcription
    case transcribe_with_cli(audio_data) do
      {:ok, text} ->
        Logger.info("CLI transcription completed successfully")
        {:ok, text}
      {:error, reason} ->
        Logger.error("CLI transcription failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp transcribe_with_cli(audio_data) do
    # Create temporary file for audio data
    case save_audio_to_temp_file(audio_data) do
      {:ok, temp_file_path} ->
        try do
          # Convert to WAV if needed (Whisper CLI handles most formats, but WAV is most reliable)
          wav_file_path = convert_to_wav_if_needed(temp_file_path)
          
          # Run Whisper CLI
          case run_whisper_command(wav_file_path) do
            {:ok, text} ->
              # Clean up temp files
              File.rm(temp_file_path)
              if wav_file_path != temp_file_path, do: File.rm(wav_file_path)
              {:ok, text}
              
            {:error, reason} ->
              # Clean up temp files
              File.rm(temp_file_path)
              if wav_file_path != temp_file_path, do: File.rm(wav_file_path)
              {:error, reason}
          end
        rescue
          error ->
            File.rm(temp_file_path)
            Logger.error("CLI transcription error: #{inspect(error)}")
            {:error, {:transcription_error, error}}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp convert_to_wav_if_needed(file_path) do
    # Check if file is already WAV
    case detect_audio_format_from_file(file_path) do
      "wav" ->
        file_path  # Already WAV, use as-is
        
      _other_format ->
        # Convert to WAV using FFmpeg
        wav_path = String.replace(file_path, ~r/\.[^.]+$/, ".wav")
        
        case System.cmd("ffmpeg", [
          "-i", file_path,
          "-acodec", "pcm_s16le",  # 16-bit PCM
          "-ar", "16000",          # 16kHz sample rate (Whisper's preferred)
          "-ac", "1",              # Mono
          "-y",                    # Overwrite output file
          wav_path
        ], stderr_to_stdout: true) do
          {_output, 0} ->
            Logger.info("Converted audio to WAV: #{wav_path}")
            wav_path
            
          {error_output, _exit_code} ->
            Logger.error("FFmpeg conversion failed: #{error_output}")
            # Fall back to original file, Whisper CLI might handle it
            file_path
        end
    end
  end

  defp run_whisper_command(audio_file_path) do
    # Create output directory
    output_dir = Path.dirname(audio_file_path)
    
    # Run Whisper CLI with optimal settings via uv
    case System.cmd("uv", ["run", "whisper",
      audio_file_path,
      "--model", "tiny",           # Fast, lightweight model
      "--language", "en",          # English (can be auto-detected by removing this)
      "--output_format", "txt",    # Plain text output
      "--output_dir", output_dir,
      "--verbose", "False"         # Reduce output noise
    ], stderr_to_stdout: true) do
      {output, 0} ->
        # Read the generated text file
        base_name = Path.basename(audio_file_path, Path.extname(audio_file_path))
        txt_file = Path.join(output_dir, base_name <> ".txt")
        
        case File.read(txt_file) do
          {:ok, text} ->
            # Clean up the output file
            File.rm(txt_file)
            cleaned_text = String.trim(text)
            
            if cleaned_text == "" do
              Logger.warning("Whisper returned empty transcription")
              {:ok, "[No speech detected]"}
            else
              {:ok, cleaned_text}
            end
            
          {:error, reason} ->
            Logger.error("Failed to read Whisper output file #{txt_file}: #{inspect(reason)}")
            {:error, {:output_read_error, reason}}
        end
        
      {error_output, exit_code} ->
        Logger.error("Whisper CLI failed (exit code #{exit_code}): #{error_output}")
        {:error, {:whisper_cli_error, exit_code, error_output}}
    end
  end

  defp detect_audio_format_from_file(file_path) do
    case File.open(file_path, [:read, :binary]) do
      {:ok, file} ->
        case IO.binread(file, 12) do
          data when is_binary(data) ->
            File.close(file)
            detect_audio_format(data)
          _ ->
            File.close(file)
            "unknown"
        end
      {:error, _} ->
        "unknown"
    end
  end

  defp save_audio_to_temp_file(audio_data) do
    # Detect audio format from header
    format = detect_audio_format(audio_data)
    Logger.info("Detected audio format: #{format}")
    
    # Create a temporary file for the audio data
    temp_dir = System.tmp_dir!()
    temp_filename = "whisper_#{:rand.uniform(999999)}.#{format}"
    temp_file_path = Path.join(temp_dir, temp_filename)
    
    try do
      case File.write(temp_file_path, audio_data) do
        :ok ->
          {:ok, temp_file_path}
        {:error, reason} ->
          Logger.error("Failed to write audio to temp file: #{inspect(reason)}")
          {:error, {:file_write_error, reason}}
      end
    rescue
      error ->
        Logger.error("Failed to create temp file: #{inspect(error)}")
        {:error, {:temp_file_error, error}}
    end
  end

  defp detect_audio_format(audio_data) do
    case audio_data do
      # WebM signature
      <<0x1A, 0x45, 0xDF, 0xA3, _::binary>> -> "webm"
      # WAV signature  
      <<"RIFF", _::binary-size(4), "WAVE", _::binary>> -> "wav"
      # MP3 signature
      <<0xFF, 0xFB, _::binary>> -> "mp3"
      <<0xFF, 0xFA, _::binary>> -> "mp3"
      # M4A signature
      <<_::binary-size(4), "ftyp", _::binary>> -> "m4a"
      # Default to webm if unknown
      _ -> "webm"
    end
  end
end