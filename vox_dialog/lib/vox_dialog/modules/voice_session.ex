defmodule VoxDialog.Modules.VoiceSession do
  @moduledoc """
  Voice Session module implementation.
  Provides real-time audio streaming and conversation management.
  """
  
  @behaviour VoxDialog.ModuleSystem
  
  require Logger
  
  @impl true
  def info do
    %{
      id: "voice_session",
      name: "Voice Session",
      version: "1.0.0",
      interface: %{
        input: "audio/stream",
        output: "audio/stream"
      }
    }
  end
  
  @impl true
  def initialize(opts) do
    session_id = Map.get(opts, :session_id, generate_session_id())
    user_id = Map.get(opts, :user_id, "anonymous")
    
    # Start voice processing session
    case VoxDialog.VoiceProcessing.SessionSupervisor.start_session(session_id, user_id) do
      {:ok, pid} ->
        {:ok, %{
          session_id: session_id,
          user_id: user_id,
          session_pid: pid,
          conversation: []
        }}
      error ->
        error
    end
  end
  
  @impl true
  def process(audio_chunk, state) when is_binary(audio_chunk) do
    # Forward audio to session server
    VoxDialog.VoiceProcessing.SessionServer.process_audio_chunk(
      state.session_id,
      decode_audio_chunk(audio_chunk)
    )
    
    # Return the same audio for now (echo)
    # In a real implementation, this would return processed audio
    {:ok, audio_chunk, state}
  end
  
  @impl true
  def shutdown(state) do
    Logger.info("Voice Session module shutting down: #{state.session_id}")
    
    # Stop the session
    if state[:session_pid] do
      GenServer.stop(state.session_pid, :normal)
    end
    
    :ok
  end
  
  # Private functions
  
  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
  
  defp decode_audio_chunk(chunk) when is_binary(chunk) do
    # Decode audio chunk (assuming base64 encoded PCM)
    case Base.decode64(chunk) do
      {:ok, decoded} ->
        # Convert to audio samples
        for <<sample::16-signed-native <- decoded>>, do: sample / 32768.0
      :error ->
        []
    end
  end
end