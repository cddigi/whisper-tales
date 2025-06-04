defmodule VoxDialog.VoiceProcessing.SessionSupervisor do
  @moduledoc """
  Supervisor for managing voice processing sessions.
  Each user session operates within its own supervised process to ensure fault tolerance.
  """
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a new voice processing session for a user.
  """
  def start_session(session_id, user_id) do
    spec = {VoxDialog.VoiceProcessing.SessionServer, {session_id, user_id}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Stops a voice processing session.
  """
  def stop_session(session_pid) do
    DynamicSupervisor.terminate_child(__MODULE__, session_pid)
  end
end