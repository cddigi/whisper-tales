defmodule VoxDialogWeb.AudioClipsLive do
  @moduledoc """
  LiveView for displaying and managing audio clips.
  """
  use VoxDialogWeb, :live_view
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    user_id = get_user_id(socket)
    
    if connected?(socket) do
      # Subscribe to audio clip updates and transcription results
      Phoenix.PubSub.subscribe(VoxDialog.PubSub, "audio_clips:#{user_id}")
      Phoenix.PubSub.subscribe(VoxDialog.PubSub, "transcription_results")
    end
    
    audio_clips = VoxDialog.Voice.list_audio_clips_for_user(user_id)
    
    {:ok, assign(socket,
      user_id: user_id,
      audio_clips: audio_clips,
      selected_clip: nil,
      playing_clip: nil
    )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="audio-clips-container">
      <div class="header">
        <h1 class="text-3xl font-bold">Audio Clips</h1>
        <p class="text-gray-600 mt-2">View and manage your recorded audio clips</p>
      </div>
      
      <div class="stats-bar mt-8 mb-6">
        <div class="stat">
          <span class="stat-number"><%= length(@audio_clips) %></span>
          <span class="stat-label">Total Clips</span>
        </div>
        <div class="stat">
          <span class="stat-number"><%= total_duration(@audio_clips) %></span>
          <span class="stat-label">Total Duration</span>
        </div>
        <div class="stat">
          <span class="stat-number"><%= transcribed_count(@audio_clips) %></span>
          <span class="stat-label">Transcribed</span>
        </div>
      </div>
      
      <div class="clips-grid">
        <div class="clips-table">
          <table class="w-full">
            <thead>
              <tr class="border-b">
                <th class="text-left p-3">Clip ID</th>
                <th class="text-left p-3">Duration</th>
                <th class="text-left p-3">Recorded</th>
                <th class="text-left p-3">Status</th>
                <th class="text-left p-3">Transcription</th>
                <th class="text-left p-3">Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= for clip <- @audio_clips do %>
                <tr class={[
                  "border-b hover:bg-gray-50 cursor-pointer",
                  @selected_clip && @selected_clip.id == clip.id && "bg-blue-50"
                ]} phx-click="select_clip" phx-value-clip_id={clip.clip_id}>
                  <td class="p-3">
                    <span class="font-mono text-sm"><%= String.slice(clip.clip_id, 0, 8) %>...</span>
                  </td>
                  <td class="p-3">
                    <%= format_duration(clip.duration_ms) %>
                  </td>
                  <td class="p-3">
                    <%= format_datetime(clip.recorded_at) %>
                  </td>
                  <td class="p-3">
                    <span class={[
                      "px-2 py-1 rounded text-xs",
                      status_color(clip.transcription_status)
                    ]}>
                      <%= String.capitalize(clip.transcription_status) %>
                    </span>
                  </td>
                  <td class="p-3">
                    <%= if clip.transcribed_text do %>
                      <span class="text-sm text-gray-700">
                        <%= String.slice(clip.transcribed_text, 0, 50) %><%= if String.length(clip.transcribed_text || "") > 50, do: "..." %>
                      </span>
                    <% else %>
                      <span class="text-gray-400 text-sm">Not transcribed</span>
                    <% end %>
                  </td>
                  <td class="p-3">
                    <div class="flex space-x-2">
                      <button
                        phx-click="play_clip"
                        phx-value-clip_id={clip.clip_id}
                        class={[
                          "px-3 py-1 rounded text-sm",
                          (@playing_clip && @playing_clip.id == clip.id) && "bg-red-500 text-white" || "bg-green-500 text-white"
                        ]}
                      >
                        <%= if @playing_clip && @playing_clip.id == clip.id do %>Stop<% else %>Play<% end %>
                      </button>
                      <button
                        phx-click="delete_clip"
                        phx-value-clip_id={clip.clip_id}
                        data-confirm="Are you sure you want to delete this audio clip?"
                        class="px-3 py-1 bg-red-500 text-white rounded text-sm hover:bg-red-600"
                      >
                        Delete
                      </button>
                    </div>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
          
          <%= if length(@audio_clips) == 0 do %>
            <div class="text-center py-12">
              <p class="text-gray-500 text-lg">No audio clips found</p>
              <p class="text-gray-400 mt-2">Start recording to see your clips here</p>
              <.link navigate="/voice" class="mt-4 inline-block bg-blue-500 text-white px-6 py-2 rounded hover:bg-blue-600">
                Go to Voice Session
              </.link>
            </div>
          <% end %>
        </div>
        
        <%= if @selected_clip do %>
          <div class="clip-details">
            <h3 class="text-lg font-semibold mb-4">Clip Details</h3>
            
            <div class="detail-group">
              <label class="detail-label">Clip ID:</label>
              <span class="font-mono text-sm"><%= @selected_clip.clip_id %></span>
            </div>
            
            <div class="detail-group">
              <label class="detail-label">Duration:</label>
              <span><%= format_duration(@selected_clip.duration_ms) %></span>
            </div>
            
            <div class="detail-group">
              <label class="detail-label">File Size:</label>
              <span><%= format_file_size(@selected_clip.file_size) %></span>
            </div>
            
            <div class="detail-group">
              <label class="detail-label">Format:</label>
              <span><%= String.upcase(@selected_clip.format) %></span>
            </div>
            
            <div class="detail-group">
              <label class="detail-label">Recorded:</label>
              <span><%= format_datetime(@selected_clip.recorded_at) %></span>
            </div>
            
            <%= if @selected_clip.transcribed_text do %>
              <div class="detail-group">
                <label class="detail-label">Transcription:</label>
                <div class="transcription-text">
                  <%= @selected_clip.transcribed_text %>
                </div>
              </div>
            <% end %>
            
            <%= if @selected_clip.ai_response do %>
              <div class="detail-group">
                <label class="detail-label">AI Response:</label>
                <div class="ai-response-text">
                  <%= @selected_clip.ai_response %>
                </div>
              </div>
            <% end %>
            
            <div class="audio-player mt-6">
              <audio 
                id={"audio-player-#{@selected_clip.id}"}
                controls 
                class="w-full"
                src={get_audio_data_url(@selected_clip)}
              >
                Your browser does not support the audio element.
              </audio>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    
    <style>
      .audio-clips-container {
        max-width: 1200px;
        margin: 0 auto;
        padding: 2rem;
      }
      
      .stats-bar {
        display: flex;
        gap: 2rem;
        padding: 1rem;
        background: #f8f9fa;
        border-radius: 0.5rem;
      }
      
      .stat {
        text-align: center;
      }
      
      .stat-number {
        display: block;
        font-size: 1.5rem;
        font-weight: bold;
        color: #1f2937;
      }
      
      .stat-label {
        display: block;
        font-size: 0.875rem;
        color: #6b7280;
      }
      
      .clips-grid {
        display: grid;
        grid-template-columns: 1fr 400px;
        gap: 2rem;
      }
      
      .clips-table {
        background: white;
        border-radius: 0.5rem;
        border: 1px solid #e5e7eb;
        overflow: hidden;
      }
      
      .clip-details {
        background: white;
        border-radius: 0.5rem;
        border: 1px solid #e5e7eb;
        padding: 1.5rem;
        height: fit-content;
      }
      
      .detail-group {
        margin-bottom: 1rem;
      }
      
      .detail-label {
        display: block;
        font-weight: 600;
        color: #374151;
        margin-bottom: 0.25rem;
      }
      
      .transcription-text, .ai-response-text {
        background: #f9fafb;
        padding: 0.75rem;
        border-radius: 0.25rem;
        border: 1px solid #e5e7eb;
        max-height: 120px;
        overflow-y: auto;
      }
      
      @media (max-width: 1024px) {
        .clips-grid {
          grid-template-columns: 1fr;
        }
      }
    </style>
    """
  end

  @impl true
  def handle_event("select_clip", %{"clip_id" => clip_id}, socket) do
    clip = VoxDialog.Voice.get_audio_clip_by_clip_id(clip_id)
    {:noreply, assign(socket, selected_clip: clip)}
  end

  @impl true
  def handle_event("play_clip", %{"clip_id" => clip_id}, socket) do
    clip = VoxDialog.Voice.get_audio_clip_by_clip_id(clip_id)
    
    if socket.assigns.playing_clip && socket.assigns.playing_clip.id == clip.id do
      # Stop playing
      {:noreply, assign(socket, playing_clip: nil)}
    else
      # Start playing
      {:noreply, assign(socket, playing_clip: clip)}
    end
  end

  @impl true
  def handle_info({:transcription_complete, clip_id, _transcription}, socket) do
    # Refresh the audio clips list to show updated transcription
    audio_clips = VoxDialog.Voice.list_audio_clips_for_user(socket.assigns.user_id)
    
    # Update selected clip if it was the one transcribed
    selected_clip = if socket.assigns.selected_clip && socket.assigns.selected_clip.clip_id == clip_id do
      VoxDialog.Voice.get_audio_clip_by_clip_id(clip_id)
    else
      socket.assigns.selected_clip
    end
    
    {:noreply, assign(socket, audio_clips: audio_clips, selected_clip: selected_clip)}
  end

  @impl true
  def handle_event("delete_clip", %{"clip_id" => clip_id}, socket) do
    case VoxDialog.Voice.get_audio_clip_by_clip_id(clip_id) do
      nil ->
        {:noreply, socket}
        
      clip ->
        case VoxDialog.Voice.delete_audio_clip(clip) do
          {:ok, _} ->
            # Remove from list and clear selection if needed
            updated_clips = Enum.reject(socket.assigns.audio_clips, &(&1.id == clip.id))
            selected_clip = if socket.assigns.selected_clip && socket.assigns.selected_clip.id == clip.id do
              nil
            else
              socket.assigns.selected_clip
            end
            
            {:noreply, assign(socket, audio_clips: updated_clips, selected_clip: selected_clip)}
            
          {:error, _} ->
            {:noreply, socket}
        end
    end
  end

  # Private Functions

  defp get_user_id(_socket) do
    # In a real app, this would get the authenticated user ID
    # For now, use a fixed user ID for testing
    "test_user_123"
  end

  defp format_duration(nil), do: "Unknown"
  defp format_duration(duration_ms) when is_integer(duration_ms) do
    seconds = duration_ms / 1000
    minutes = div(trunc(seconds), 60)
    remaining_seconds = rem(trunc(seconds), 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(remaining_seconds), 2, "0")}"
  end

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end

  defp format_file_size(nil), do: "Unknown"
  defp format_file_size(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 1)} KB"
      true -> "#{bytes} B"
    end
  end

  defp status_color("pending"), do: "bg-yellow-100 text-yellow-800"
  defp status_color("processing"), do: "bg-blue-100 text-blue-800"
  defp status_color("completed"), do: "bg-green-100 text-green-800"
  defp status_color("failed"), do: "bg-red-100 text-red-800"
  defp status_color(_), do: "bg-gray-100 text-gray-800"

  defp total_duration(clips) do
    total_ms = clips
    |> Enum.map(& &1.duration_ms || 0)
    |> Enum.sum()
    
    format_duration(total_ms)
  end

  defp transcribed_count(clips) do
    clips
    |> Enum.count(& &1.transcription_status == "completed")
  end

  defp get_audio_data_url(clip) do
    VoxDialog.Voice.AudioClip.get_audio_data_url(clip)
  end
end