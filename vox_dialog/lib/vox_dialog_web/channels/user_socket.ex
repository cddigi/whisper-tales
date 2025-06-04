defmodule VoxDialogWeb.UserSocket do
  use Phoenix.Socket

  # Channels
  channel "voice:*", VoxDialogWeb.VoiceChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    # In a real application, you would authenticate the user here
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end