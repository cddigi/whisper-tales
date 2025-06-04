defmodule VoxDialog.VoiceProcessing.SessionServer do
  @moduledoc """
  Primary VoxDialog GenServer that maintains conversation state and coordinates voice activity detection.
  Handles audio stream initialization, maintains conversation context using ETS tables,
  and manages the lifecycle of voice processing operations.
  """
  use GenServer
  require Logger

  defstruct [:session_id, :user_id, :conversation_context, :audio_processor_pid, :state]

  def start_link({session_id, user_id}) do
    GenServer.start_link(__MODULE__, {session_id, user_id}, name: via_tuple(session_id))
  end

  @impl true
  def init({session_id, user_id}) do
    Logger.info("Starting voice session #{session_id} for user #{user_id}")
    
    # Create ETS table for conversation context
    :ets.new(:"session_#{session_id}", [:named_table, :public, :ordered_set])
    
    # Start audio processor for this session
    {:ok, audio_processor_pid} = VoxDialog.VoiceProcessing.AudioProcessor.start_link(session_id)
    
    state = %__MODULE__{
      session_id: session_id,
      user_id: user_id,
      conversation_context: [],
      audio_processor_pid: audio_processor_pid,
      state: :idle
    }
    
    {:ok, state}
  end

  # Client API

  def process_audio_chunk(session_id, audio_data) do
    GenServer.cast(via_tuple(session_id), {:process_audio, audio_data})
  end

  def get_conversation_context(session_id) do
    GenServer.call(via_tuple(session_id), :get_context)
  end

  def update_conversation_context(session_id, context) do
    GenServer.cast(via_tuple(session_id), {:update_context, context})
  end

  # Server Callbacks

  @impl true
  def handle_cast({:process_audio, audio_data}, state) do
    # Forward audio data to the audio processor
    VoxDialog.VoiceProcessing.AudioProcessor.process_chunk(state.audio_processor_pid, audio_data)
    {:noreply, %{state | state: :processing}}
  end

  @impl true
  def handle_cast({:update_context, context}, state) do
    # Update ETS table with new context
    :ets.insert(:"session_#{state.session_id}", {DateTime.utc_now(), context})
    {:noreply, %{state | conversation_context: [context | state.conversation_context]}}
  end

  @impl true
  def handle_call(:get_context, _from, state) do
    {:reply, state.conversation_context, state}
  end

  @impl true
  def handle_info({:voice_activity_detected, activity_type, data}, state) do
    Logger.info("Voice activity detected: #{activity_type}")
    
    case activity_type do
      :user_speech ->
        # Handle user speech
        handle_user_speech(data, state)
        
      :environmental_sound ->
        # Handle environmental sounds that need user attention
        handle_environmental_sound(data, state)
        
      _ ->
        Logger.debug("Ignoring activity type: #{activity_type}")
    end
    
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Terminating session #{state.session_id}: #{inspect(reason)}")
    # Clean up ETS table
    :ets.delete(:"session_#{state.session_id}")
    :ok
  end

  # Private Functions

  defp via_tuple(session_id) do
    {:via, Registry, {VoxDialog.SessionRegistry, session_id}}
  end

  defp handle_user_speech(_speech_data, state) do
    # Process user speech and update conversation context
    Logger.debug("Processing user speech for session #{state.session_id}")
    # This would integrate with speech recognition
  end

  defp handle_environmental_sound(_sound_data, state) do
    # Process environmental sounds and notify if necessary
    Logger.debug("Processing environmental sound for session #{state.session_id}")
    # This would trigger notifications for important sounds
  end
end