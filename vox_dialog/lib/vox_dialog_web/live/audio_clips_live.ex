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
      playing_clip: nil,
      filter_type: "all",
      audio_controls: %{
        playback_speed: 1.0,
        pitch_adjustment: 1.0
      }
    )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="audio-clips-container">
      <div class="header">
        <h1 class="text-3xl font-bold">Audio Library</h1>
        <p class="text-gray-600 mt-2">View and manage your recorded audio clips and TTS generations</p>
      </div>
      
      <!-- Filter Controls -->
      <div class="filter-controls mt-6 mb-4">
        <div class="flex items-center gap-4">
          <label class="text-sm font-medium text-gray-700">Filter by type:</label>
          <select 
            phx-change="filter_change" 
            name="filter_type"
            value={@filter_type}
            class="px-3 py-2 border border-gray-300 rounded-md text-sm focus:ring-blue-500 focus:border-blue-500"
          >
            <option value="all" selected={@filter_type == "all"}>All Audio</option>
            <option value="recording" selected={@filter_type == "recording"}>Voice Recordings</option>
            <option value="tts" selected={@filter_type == "tts"}>TTS Generated</option>
          </select>
          
          <span class="text-sm text-gray-500">
            Showing <%= length(filtered_clips(@audio_clips, @filter_type)) %> of <%= length(@audio_clips) %> clips
          </span>
        </div>
      </div>
      
      <div class="stats-bar mt-4 mb-6">
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
      
      <div class={["clips-grid", @selected_clip && "with-details"]}>
        <div class="clips-table">
          <table class="clips-data-table">
            <thead>
              <tr>
                <th class="col-type">Type</th>
                <th class="col-id">Clip ID</th>
                <th class="col-duration">Duration</th>
                <th class="col-recorded">Recorded</th>
                <th class="col-status">Status</th>
                <th class="col-content">Content</th>
                <th class="col-actions">Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= for clip <- filtered_clips(@audio_clips, @filter_type) do %>
                <tr class={[
                  "border-b hover:bg-gray-50 cursor-pointer",
                  @selected_clip && @selected_clip.id == clip.id && "bg-blue-50"
                ]} phx-click="select_clip" phx-value-clip_id={clip.clip_id}>
                  <td class="col-type">
                    <div class="flex items-center">
                      <%= if clip.audio_type == "tts" do %>
                        <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-purple-100 text-purple-800">
                          🎤 TTS
                        </span>
                      <% else %>
                        <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                          🎙️ Recording
                        </span>
                      <% end %>
                    </div>
                  </td>
                  <td class="col-id">
                    <span class="font-mono text-sm"><%= String.slice(clip.clip_id, 0, 8) %>...</span>
                  </td>
                  <td class="col-duration">
                    <%= format_duration(clip.duration_ms) %>
                  </td>
                  <td class="col-recorded">
                    <%= format_datetime(clip.recorded_at) %>
                  </td>
                  <td class="col-status">
                    <span class={[
                      "px-2 py-1 rounded text-xs",
                      status_color(clip.transcription_status)
                    ]}>
                      <%= String.capitalize(clip.transcription_status) %>
                    </span>
                  </td>
                  <td class="col-content">
                    <%= if clip.audio_type == "tts" and clip.source_text do %>
                      <div class="text-sm">
                        <div class="text-gray-700 overflow-hidden">
                          <%= String.slice(clip.source_text, 0, 50) %><%= if String.length(clip.source_text || "") > 50, do: "..." %>
                        </div>
                        <%= if clip.accent do %>
                          <div class="text-xs text-gray-500 mt-1">
                            Accent: <%= String.capitalize(clip.accent) %>
                          </div>
                        <% end %>
                      </div>
                    <% else %>
                      <%= if clip.transcribed_text do %>
                        <span class="text-sm text-gray-700 overflow-hidden">
                          <%= String.slice(clip.transcribed_text, 0, 50) %><%= if String.length(clip.transcribed_text || "") > 50, do: "..." %>
                        </span>
                      <% else %>
                        <span class="text-gray-400 text-sm">Not transcribed</span>
                      <% end %>
                    <% end %>
                  </td>
                  <td class="col-actions">
                    <div class="flex flex-wrap gap-1">
                      <button
                        phx-click="play_clip"
                        phx-value-clip_id={clip.clip_id}
                        class={[
                          "px-2 py-1 rounded text-xs font-medium",
                          (@playing_clip && @playing_clip.id == clip.id) && "bg-red-500 text-white" || "bg-green-500 text-white"
                        ]}
                      >
                        <%= if @playing_clip && @playing_clip.id == clip.id do %>Stop<% else %>Play<% end %>
                      </button>
                      <button
                        phx-click="delete_clip"
                        phx-value-clip_id={clip.clip_id}
                        data-confirm="Are you sure you want to delete this audio clip?"
                        class="px-2 py-1 bg-red-500 text-white rounded text-xs font-medium hover:bg-red-600"
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
            <div class="flex items-center justify-between mb-4">
              <h3 class="text-lg font-semibold">Clip Details</h3>
              <div class="flex items-center">
                <%= if @selected_clip.audio_type == "tts" do %>
                  <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-purple-100 text-purple-800">
                    🎤 TTS Generated
                  </span>
                <% else %>
                  <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                    🎙️ Voice Recording
                  </span>
                <% end %>
              </div>
            </div>
            
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
              <label class="detail-label">Created:</label>
              <span><%= format_datetime(@selected_clip.recorded_at) %></span>
            </div>
            
            <!-- TTS-specific information -->
            <%= if @selected_clip.audio_type == "tts" do %>
              <%= if @selected_clip.source_text do %>
                <div class="detail-group">
                  <label class="detail-label">Original Text:</label>
                  <div class="transcription-text">
                    <%= @selected_clip.source_text %>
                  </div>
                </div>
              <% end %>
              
              <%= if @selected_clip.accent do %>
                <div class="detail-group">
                  <label class="detail-label">Accent:</label>
                  <span class="capitalize"><%= @selected_clip.accent %></span>
                </div>
              <% end %>
              
              <%= if @selected_clip.voice_settings && map_size(@selected_clip.voice_settings) > 0 do %>
                <div class="detail-group">
                  <label class="detail-label">Voice Settings:</label>
                  <div class="text-sm space-y-1">
                    <%= if @selected_clip.voice_settings["pitch"] do %>
                      <div>Pitch: <%= @selected_clip.voice_settings["pitch"] %></div>
                    <% end %>
                    <%= if @selected_clip.voice_settings["speed"] do %>
                      <div>Speed: <%= @selected_clip.voice_settings["speed"] %></div>
                    <% end %>
                    <%= if @selected_clip.voice_settings["tone"] do %>
                      <div>Tone: <%= @selected_clip.voice_settings["tone"] %></div>
                    <% end %>
                  </div>
                </div>
              <% end %>
            <% end %>
            
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
            
            <!-- Enhanced Audio Player -->
            <div class="audio-player mt-6">
              <h4 class="text-md font-medium mb-3">Audio Player</h4>
              
              <!-- Playback Controls -->
              <div class="playback-controls mb-4 p-4 bg-gray-50 rounded-lg">
                <div class="grid grid-cols-2 gap-4">
                  <!-- Playback Speed -->
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">
                      Playback Speed: <%= @audio_controls.playback_speed %>x
                    </label>
                    <input
                      type="range"
                      min="0.25"
                      max="2.0"
                      step="0.25"
                      value={@audio_controls.playback_speed}
                      phx-change="update_audio_controls"
                      name="playback_speed"
                      class="w-full"
                    />
                    <div class="flex justify-between text-xs text-gray-500 mt-1">
                      <span>0.25x</span>
                      <span>1x</span>
                      <span>2x</span>
                    </div>
                  </div>
                  
                  <!-- Pitch Adjustment -->
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">
                      Pitch: <%= @audio_controls.pitch_adjustment %>x
                    </label>
                    <input
                      type="range"
                      min="0.5"
                      max="1.5"
                      step="0.1"
                      value={@audio_controls.pitch_adjustment}
                      phx-change="update_audio_controls"
                      name="pitch_adjustment"
                      class="w-full"
                    />
                    <div class="flex justify-between text-xs text-gray-500 mt-1">
                      <span>Lower</span>
                      <span>Normal</span>
                      <span>Higher</span>
                    </div>
                  </div>
                </div>
                
                <!-- Reset Controls -->
                <div class="mt-3 text-center">
                  <button
                    phx-click="reset_audio_controls"
                    class="px-3 py-1 text-sm bg-gray-200 text-gray-700 rounded hover:bg-gray-300"
                  >
                    Reset to Default
                  </button>
                </div>
              </div>
              
              <!-- Audio Element -->
              <audio 
                id={"audio-player-#{@selected_clip.id}"}
                controls 
                class="w-full"
                src={get_audio_data_url(@selected_clip)}
                phx-update="ignore"
                phx-hook="AudioControls"
                data-speed={@audio_controls.playback_speed}
                data-pitch={@audio_controls.pitch_adjustment}
              >
                Your browser does not support the audio element.
              </audio>
              
              <!-- Download and Action Buttons -->
              <div class="flex gap-2 mt-4">
                <a
                  href={get_audio_data_url(@selected_clip)}
                  download={"#{@selected_clip.clip_id}.#{@selected_clip.format}"}
                  class="px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 transition-colors text-sm"
                >
                  📥 Download
                </a>
                
                <%= if @selected_clip.audio_type == "tts" do %>
                  <.link 
                    navigate={~p"/tts?text=#{URI.encode(@selected_clip.source_text || "")}&accent=#{@selected_clip.accent || "midwest"}"}
                    class="px-4 py-2 bg-purple-600 text-white rounded hover:bg-purple-700 transition-colors text-sm"
                  >
                    🎤 Regenerate TTS
                  </.link>
                <% end %>
                
                <button
                  phx-click="delete_clip"
                  phx-value-clip_id={@selected_clip.clip_id}
                  data-confirm="Are you sure you want to delete this audio clip?"
                  class="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700 transition-colors text-sm"
                >
                  🗑️ Delete
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    
    <style>
      .audio-clips-container {
        width: 100%;
        padding: 2rem;
      }
      
      .stats-bar {
        display: flex;
        gap: 2rem;
        padding: 1rem;
        background: #f8f9fa;
        border-radius: 0.5rem;
        margin-bottom: 1.5rem;
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
        grid-template-columns: 1fr;
        gap: 2rem;
        width: 100%;
      }
      
      .clips-grid.with-details {
        grid-template-columns: minmax(0, 1fr) 450px;
      }
      
      .clips-table {
        background: white;
        border-radius: 0.5rem;
        border: 1px solid #e5e7eb;
        overflow-x: auto;
        width: 100%;
      }
      
      .clips-data-table {
        width: 100%;
        table-layout: fixed;
        border-collapse: collapse;
      }
      
      .clips-data-table thead {
        background-color: #f9fafb;
      }
      
      .clips-data-table th {
        padding: 0.75rem 1rem;
        text-align: left;
        font-weight: 600;
        color: #374151;
        border-bottom: 1px solid #e5e7eb;
      }
      
      .clips-data-table td {
        padding: 0.75rem 1rem;
        vertical-align: middle;
      }
      
      /* Column widths for better distribution */
      .col-type { width: 10%; min-width: 100px; }
      .col-id { width: 15%; min-width: 120px; }
      .col-duration { width: 10%; min-width: 80px; }
      .col-recorded { width: 15%; min-width: 140px; }
      .col-status { width: 10%; min-width: 100px; }
      .col-content { width: 25%; min-width: 200px; }
      .col-actions { width: 15%; min-width: 140px; }
      
      .clip-details {
        background: white;
        border-radius: 0.5rem;
        border: 1px solid #e5e7eb;
        padding: 1.5rem;
        height: fit-content;
        position: sticky;
        top: 2rem;
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
        word-wrap: break-word;
      }
      
      /* Responsive adjustments */
      @media (max-width: 1400px) {
        .clips-grid.with-details {
          grid-template-columns: minmax(0, 1fr) 400px;
        }
      }
      
      @media (max-width: 1200px) {
        .clips-grid.with-details {
          grid-template-columns: 1fr;
        }
        
        .clip-details {
          position: static;
        }
      }
      
      @media (max-width: 768px) {
        .clips-data-table {
          font-size: 0.875rem;
        }
        
        .clips-data-table th,
        .clips-data-table td {
          padding: 0.5rem;
        }
        
        .col-id { display: none; }
        .col-recorded { display: none; }
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
  
  @impl true
  def handle_event("filter_change", %{"filter_type" => filter_type}, socket) do
    {:noreply, assign(socket, filter_type: filter_type)}
  end
  
  @impl true
  def handle_event("update_audio_controls", params, socket) do
    current_controls = socket.assigns.audio_controls
    
    new_controls = 
      current_controls
      |> maybe_update_float(params, "playback_speed")
      |> maybe_update_float(params, "pitch_adjustment")
    
    {:noreply, assign(socket, audio_controls: new_controls)}
  end
  
  @impl true
  def handle_event("reset_audio_controls", _params, socket) do
    default_controls = %{
      playback_speed: 1.0,
      pitch_adjustment: 1.0
    }
    {:noreply, assign(socket, audio_controls: default_controls)}
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
  
  defp filtered_clips(clips, "all"), do: clips
  defp filtered_clips(clips, filter_type) do
    Enum.filter(clips, fn clip ->
      (clip.audio_type || "recording") == filter_type
    end)
  end
  
  defp maybe_update_float(settings, params, key) do
    case Map.get(params, key) do
      nil -> settings
      value -> 
        case Float.parse(value) do
          {float_val, _} -> Map.put(settings, String.to_atom(key), float_val)
          :error -> settings
        end
    end
  end
end