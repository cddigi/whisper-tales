defmodule VoxDialog.VoiceProcessing.AudioProcessor do
  @moduledoc """
  Handles the voice activity detection pipeline with multi-layered audio analysis.
  Implements energy level detection, spectral feature extraction, and temporal pattern recognition.
  Distinguishes between user speech, background noise, and environmental sounds.
  """
  use GenServer
  require Logger

  defstruct [:session_id, :buffer, :noise_profile, :detection_state, :config]

  @buffer_size 16_384  # 1 second at 16kHz
  @energy_threshold 0.02

  def start_link(session_id) do
    GenServer.start_link(__MODULE__, session_id)
  end

  def process_chunk(pid, audio_data) do
    GenServer.cast(pid, {:process_chunk, audio_data})
  end

  @impl true
  def init(session_id) do
    state = %__MODULE__{
      session_id: session_id,
      buffer: :queue.new(),
      noise_profile: %{
        baseline_energy: 0.0,
        frequency_profile: []
      },
      detection_state: :idle,
      config: %{
        sensitivity: :normal,
        environmental_detection: true
      }
    }
    
    {:ok, state}
  end

  @impl true
  def handle_cast({:process_chunk, audio_data}, state) do
    # Add to circular buffer
    updated_buffer = update_buffer(state.buffer, audio_data)
    
    # Perform multi-layered analysis
    analysis_result = analyze_audio(audio_data, state)
    
    # Update state based on analysis
    new_state = case analysis_result do
      {:speech_detected, confidence} ->
        handle_speech_detection(state, confidence)
        
      {:environmental_sound, sound_type} ->
        handle_environmental_detection(state, sound_type)
        
      :silence ->
        %{state | detection_state: :idle}
        
      _ ->
        state
    end
    
    {:noreply, %{new_state | buffer: updated_buffer}}
  end

  # Private Functions

  defp update_buffer(buffer, new_data) do
    # Implement circular buffer logic
    updated = :queue.in(new_data, buffer)
    
    # Remove old data if buffer exceeds size
    if :queue.len(updated) > @buffer_size do
      {_, trimmed} = :queue.out(updated)
      trimmed
    else
      updated
    end
  end

  defp analyze_audio(audio_data, state) do
    # Calculate energy level
    energy = calculate_energy(audio_data)
    
    # Extract spectral features
    spectral_features = extract_spectral_features(audio_data)
    
    # Analyze temporal patterns
    temporal_patterns = analyze_temporal_patterns(state.buffer)
    
    # Determine activity type
    cond do
      is_speech?(energy, spectral_features, temporal_patterns) ->
        {:speech_detected, calculate_confidence(energy, spectral_features)}
        
      is_environmental_sound?(energy, spectral_features) ->
        sound_type = classify_environmental_sound(spectral_features)
        {:environmental_sound, sound_type}
        
      energy < @energy_threshold ->
        :silence
        
      true ->
        :background_noise
    end
  end

  defp calculate_energy(audio_data) do
    # Calculate RMS energy
    sum_squares = audio_data
    |> Enum.map(&(&1 * &1))
    |> Enum.sum()
    
    :math.sqrt(sum_squares / length(audio_data))
  end

  defp extract_spectral_features(audio_data) do
    # Simplified spectral analysis
    # In production, this would use FFT and extract multiple features
    %{
      dominant_frequency: estimate_dominant_frequency(audio_data),
      spectral_centroid: calculate_spectral_centroid(audio_data),
      zero_crossing_rate: calculate_zero_crossing_rate(audio_data)
    }
  end

  defp analyze_temporal_patterns(buffer) do
    # Analyze patterns over time
    %{
      continuity: check_speech_continuity(buffer),
      rhythm: detect_speech_rhythm(buffer)
    }
  end

  defp is_speech?(energy, spectral_features, temporal_patterns) do
    energy > @energy_threshold and
    spectral_features.dominant_frequency > 85 and
    spectral_features.dominant_frequency < 3000 and
    temporal_patterns.continuity > 0.7
  end

  defp is_environmental_sound?(energy, spectral_features) do
    energy > @energy_threshold * 2 and
    (spectral_features.dominant_frequency > 3000 or
     spectral_features.zero_crossing_rate > 0.5)
  end

  defp classify_environmental_sound(spectral_features) do
    # Simplified classification
    cond do
      spectral_features.dominant_frequency > 4000 -> :alarm
      spectral_features.dominant_frequency > 2000 -> :doorbell
      spectral_features.zero_crossing_rate > 0.7 -> :phone_ring
      true -> :unknown
    end
  end

  defp calculate_confidence(energy, spectral_features) do
    # Simple confidence calculation
    base_confidence = min(energy / (@energy_threshold * 5), 1.0)
    
    if spectral_features.dominant_frequency > 85 and 
       spectral_features.dominant_frequency < 255 do
      base_confidence
    else
      base_confidence * 0.8
    end
  end

  defp handle_speech_detection(state, confidence) do
    # Notify session server about detected speech
    session_pid = get_session_pid(state.session_id)
    send(session_pid, {:voice_activity_detected, :user_speech, %{confidence: confidence}})
    
    %{state | detection_state: :speech_active}
  end

  defp handle_environmental_detection(state, sound_type) do
    # Notify about environmental sounds
    session_pid = get_session_pid(state.session_id)
    send(session_pid, {:voice_activity_detected, :environmental_sound, %{type: sound_type}})
    
    state
  end

  defp get_session_pid(session_id) do
    case Registry.lookup(VoxDialog.SessionRegistry, session_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  # Simplified implementations of audio analysis functions
  defp estimate_dominant_frequency(_audio_data), do: 150.0
  defp calculate_spectral_centroid(_audio_data), do: 500.0
  defp calculate_zero_crossing_rate(_audio_data), do: 0.3
  defp check_speech_continuity(_buffer), do: 0.8
  defp detect_speech_rhythm(_buffer), do: 0.6
end