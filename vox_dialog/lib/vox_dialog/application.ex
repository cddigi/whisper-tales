defmodule VoxDialog.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      VoxDialogWeb.Telemetry,
      VoxDialog.Repo,
      {DNSCluster, query: Application.get_env(:vox_dialog, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: VoxDialog.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: VoxDialog.Finch},
      # Registry for voice processing sessions
      {Registry, keys: :unique, name: VoxDialog.SessionRegistry},
      # Voice processing session supervisor
      VoxDialog.VoiceProcessing.SessionSupervisor,
      # Whisper model server (loads configurable backend asynchronously)
      VoxDialog.SpeechRecognition.WhisperServer,
      # Chatterbox TTS server (checks server availability asynchronously)
      VoxDialog.SpeechSynthesis.ChatterboxServer,
      # Speech recognition transcription worker
      VoxDialog.SpeechRecognition.TranscriptionWorker,
      # Module manager for dynamic module loading/unloading
      VoxDialog.ModuleManager,
      # Start to serve requests, typically the last entry
      VoxDialogWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: VoxDialog.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    VoxDialogWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
