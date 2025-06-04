defmodule VoxDialog.VoiceProcessing.EnvironmentalDetector do
  @moduledoc """
  Monitors audio input for patterns indicating events that warrant user notification.
  Detects doorbell sounds, phone calls, alarms, and unusual noise patterns.
  """
  
  defmodule SoundPattern do
    @moduledoc false
    defstruct [:name, :frequency_range, :duration_ms, :pattern_type, :confidence_threshold]
  end

  alias VoxDialog.VoiceProcessing.EnvironmentalDetector.SoundPattern

  # Define common environmental sound patterns
  defp sound_patterns do
    [
      %SoundPattern{
        name: :doorbell,
        frequency_range: {800, 2000},
        duration_ms: {500, 2000},
        pattern_type: :tonal,
        confidence_threshold: 0.7
      },
      %SoundPattern{
        name: :phone_ring,
        frequency_range: {400, 1200},
        duration_ms: {800, 3000},
        pattern_type: :periodic,
        confidence_threshold: 0.75
      },
      %SoundPattern{
        name: :smoke_alarm,
        frequency_range: {2000, 4000},
        duration_ms: {500, 1500},
        pattern_type: :periodic_high,
        confidence_threshold: 0.8
      },
      %SoundPattern{
        name: :baby_cry,
        frequency_range: {300, 600},
        duration_ms: {1000, 5000},
        pattern_type: :variable_pitch,
        confidence_threshold: 0.6
      },
      %SoundPattern{
        name: :dog_bark,
        frequency_range: {200, 800},
        duration_ms: {200, 1000},
        pattern_type: :burst,
        confidence_threshold: 0.65
      }
    ]
  end

  @doc """
  Analyzes audio features to detect environmental sounds.
  Returns {:ok, sound_type, confidence} or {:ok, :none}
  """
  def detect(audio_features) do
    detections = sound_patterns()
    |> Enum.map(&match_pattern(&1, audio_features))
    |> Enum.filter(fn {_pattern, confidence} -> confidence > 0 end)
    |> Enum.sort_by(fn {_pattern, confidence} -> confidence end, :desc)
    
    case detections do
      [{pattern, confidence} | _] when confidence >= pattern.confidence_threshold ->
        {:ok, pattern.name, confidence}
        
      _ ->
        {:ok, :none}
    end
  end

  @doc """
  Checks if a detected sound should trigger user notification.
  """
  def should_notify?(sound_type, user_preferences \\ %{}) do
    default_notifications = %{
      doorbell: true,
      phone_ring: true,
      smoke_alarm: true,
      baby_cry: true,
      dog_bark: false
    }
    
    Map.get(user_preferences, sound_type, Map.get(default_notifications, sound_type, false))
  end

  # Private Functions

  defp match_pattern(pattern, features) do
    confidence = calculate_pattern_confidence(pattern, features)
    {pattern, confidence}
  end

  defp calculate_pattern_confidence(pattern, features) do
    freq_match = frequency_match(pattern.frequency_range, features.dominant_frequency)
    duration_match = duration_match(pattern.duration_ms, features.duration)
    pattern_match = pattern_type_match(pattern.pattern_type, features)
    
    # Weighted average of matches
    (freq_match * 0.4 + duration_match * 0.3 + pattern_match * 0.3)
  end

  defp frequency_match({min_freq, max_freq}, frequency) do
    if frequency >= min_freq and frequency <= max_freq do
      # Calculate how centered the frequency is in the range
      center = (min_freq + max_freq) / 2
      distance = abs(frequency - center)
      max_distance = (max_freq - min_freq) / 2
      1.0 - (distance / max_distance) * 0.5
    else
      0.0
    end
  end

  defp duration_match({min_dur, max_dur}, duration) when is_number(duration) do
    if duration >= min_dur and duration <= max_dur do
      1.0
    else
      # Partial match for close durations
      if duration < min_dur do
        max(0, 1.0 - (min_dur - duration) / min_dur)
      else
        max(0, 1.0 - (duration - max_dur) / max_dur)
      end
    end
  end
  
  defp duration_match(_, _), do: 0.0

  defp pattern_type_match(:tonal, features) do
    # Tonal sounds have steady frequency
    features.frequency_stability || 0.0
  end

  defp pattern_type_match(:periodic, features) do
    # Periodic sounds repeat at regular intervals
    features.periodicity || 0.0
  end

  defp pattern_type_match(:periodic_high, features) do
    # High-pitched periodic sounds (alarms)
    periodicity = features.periodicity || 0.0
    high_freq = if features.dominant_frequency > 2000, do: 1.0, else: 0.5
    (periodicity + high_freq) / 2
  end

  defp pattern_type_match(:variable_pitch, features) do
    # Variable pitch sounds (crying)
    1.0 - (features.frequency_stability || 1.0)
  end

  defp pattern_type_match(:burst, features) do
    # Short burst sounds (barking)
    if features.duration && features.duration < 1000 do
      1.0 - (features.frequency_stability || 1.0) * 0.5
    else
      0.0
    end
  end

  defp pattern_type_match(_, _), do: 0.5
end