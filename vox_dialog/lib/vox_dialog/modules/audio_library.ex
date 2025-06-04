defmodule VoxDialog.Modules.AudioLibrary do
  @moduledoc """
  Audio Library module implementation.
  Manages storage and retrieval of audio clips.
  """
  
  @behaviour VoxDialog.ModuleSystem
  
  require Logger
  
  @impl true
  def info do
    %{
      id: "audio_library",
      name: "Audio Library",
      version: "1.0.0",
      interface: %{
        input: "audio/*",
        output: "audio/*"
      }
    }
  end
  
  @impl true
  def initialize(opts) do
    user_id = Map.get(opts, :user_id, "anonymous")
    
    state = %{
      user_id: user_id,
      clips: VoxDialog.Voice.list_audio_clips_for_user(user_id)
    }
    
    {:ok, state}
  end
  
  @impl true
  def process({:list_clips}, state) do
    # Refresh clips list
    clips = VoxDialog.Voice.list_audio_clips_for_user(state.user_id)
    new_state = %{state | clips: clips}
    
    {:ok, clips, new_state}
  end
  
  @impl true
  def process({:get_clip, clip_id}, state) do
    case VoxDialog.Voice.get_audio_clip_by_clip_id(clip_id) do
      nil ->
        {:error, :not_found}
      clip ->
        {:ok, clip, state}
    end
  end
  
  @impl true
  def process({:save_clip, audio_data, metadata}, state) when is_binary(audio_data) do
    clip_attrs = Map.merge(%{
      user_id: state.user_id,
      audio_data: audio_data,
      format: Map.get(metadata, :format, "webm"),
      duration_ms: Map.get(metadata, :duration_ms)
    }, metadata)
    
    case VoxDialog.Voice.create_audio_clip(clip_attrs) do
      {:ok, clip} ->
        # Update state with new clip
        new_state = %{state | clips: [clip | state.clips]}
        {:ok, clip, new_state}
      error ->
        error
    end
  end
  
  @impl true
  def process({:delete_clip, clip_id}, state) do
    case VoxDialog.Voice.get_audio_clip_by_clip_id(clip_id) do
      nil ->
        {:error, :not_found}
      clip ->
        case VoxDialog.Voice.delete_audio_clip(clip) do
          {:ok, _} ->
            # Remove from state
            new_clips = Enum.reject(state.clips, & &1.clip_id == clip_id)
            new_state = %{state | clips: new_clips}
            {:ok, :deleted, new_state}
          error ->
            error
        end
    end
  end
  
  @impl true
  def shutdown(_state) do
    Logger.info("Audio Library module shutting down")
    :ok
  end
end