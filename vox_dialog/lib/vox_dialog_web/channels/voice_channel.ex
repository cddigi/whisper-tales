defmodule VoxDialogWeb.VoiceChannel do
  @moduledoc """
  Phoenix Channel for managing audio data transmission using WebSocket connections.
  Handles voice input streams and response output with proper audio buffering and flow control.
  """
  use VoxDialogWeb, :channel
  require Logger

  @impl true
  def join("voice:" <> session_id, _params, socket) do
    # Verify session exists
    case Registry.lookup(VoxDialog.SessionRegistry, session_id) do
      [{_pid, _}] ->
        send(self(), :after_join)
        {:ok, assign(socket, :session_id, session_id)}
        
      [] ->
        {:error, %{reason: "Session not found"}}
    end
  end

  @impl true
  def handle_in("audio_chunk", %{"data" => audio_data}, socket) do
    session_id = socket.assigns.session_id
    
    # Decode and process audio chunk
    case decode_audio_chunk(audio_data) do
      {:ok, samples} ->
        VoxDialog.VoiceProcessing.SessionServer.process_audio_chunk(session_id, samples)
        {:noreply, socket}
        
      {:error, reason} ->
        Logger.error("Failed to decode audio chunk: #{inspect(reason)}")
        {:reply, {:error, %{reason: "Invalid audio data"}}, socket}
    end
  end

  @impl true
  def handle_in("start_recording", _params, socket) do
    broadcast_to_session(socket, "recording_started", %{})
    {:noreply, socket}
  end

  @impl true
  def handle_in("stop_recording", _params, socket) do
    broadcast_to_session(socket, "recording_stopped", %{})
    {:noreply, socket}
  end

  @impl true
  def handle_in("ping", _params, socket) do
    {:reply, {:ok, %{timestamp: System.system_time(:millisecond)}}, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    # Subscribe to session events
    Phoenix.PubSub.subscribe(VoxDialog.PubSub, "session:#{socket.assigns.session_id}")
    {:noreply, socket}
  end

  @impl true
  def handle_info({:audio_response, audio_data}, socket) do
    # Send audio response back to client
    push(socket, "audio_response", %{data: encode_audio_data(audio_data)})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:transcription, text}, socket) do
    # Send transcription to client
    push(socket, "transcription", %{text: text})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:environmental_sound, sound_type}, socket) do
    # Notify client about detected environmental sound
    push(socket, "environmental_sound", %{type: sound_type})
    {:noreply, socket}
  end

  # Private Functions

  defp decode_audio_chunk(base64_data) do
    case Base.decode64(base64_data) do
      {:ok, binary_data} ->
        # Convert binary to float samples (assuming 16-bit PCM)
        samples = for <<sample::16-signed-native <- binary_data>>, do: sample / 32768.0
        {:ok, samples}
        
      :error ->
        {:error, :invalid_base64}
    end
  end

  defp encode_audio_data(samples) when is_list(samples) do
    # Convert float samples to 16-bit PCM
    binary_data = 
      samples
      |> Enum.map(&round(&1 * 32768))
      |> Enum.map(&<<&1::16-signed-native>>)
      |> Enum.join()
    
    Base.encode64(binary_data)
  end

  defp broadcast_to_session(socket, event, payload) do
    Phoenix.PubSub.broadcast(
      VoxDialog.PubSub,
      "session:#{socket.assigns.session_id}",
      {event, payload}
    )
  end
end