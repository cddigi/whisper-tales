defmodule VoxDialogWeb.TTSLive do
  @moduledoc """
  LiveView module for Text-to-Speech generation.
  Provides interface for generating speech from text with accent selection.
  """
  use VoxDialogWeb, :live_view
  require Logger
  
  alias VoxDialog.Voice.AudioClip
  alias VoxDialog.SpeechSynthesis.ChatterboxServer
  
  @accents [
    {"American Midwest", "midwest"},
    {"American Southern", "southern"},
    {"British (RP)", "british"},
    {"Australian", "australian"},
    {"Canadian", "canadian"},
    {"New York", "newyork"},
    {"California", "california"},
    {"Texas", "texas"}
  ]
  
  @impl true
  def mount(params, _session, socket) do
    session_id = generate_session_id()
    user_id = get_user_id(socket)
    
    # Parse URL parameters for regenerating TTS
    text_input = Map.get(params, "text", "")
    selected_accent = Map.get(params, "accent", "midwest")
    
    {:ok, assign(socket,
      session_id: session_id,
      user_id: user_id,
      text_input: text_input,
      selected_accent: selected_accent,
      generation_status: :idle,
      accents: @accents,
      last_generated_clip: nil,
      voice_settings: %{
        pitch: 1.0,
        speed: 1.0,
        tone: "neutral"
      }
    )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="tts-container max-w-4xl mx-auto p-6">
      <div class="header mb-8">
        <h1 class="text-3xl font-bold text-gray-900">Text-to-Speech Generator</h1>
        <p class="text-gray-600 mt-2">Generate high-quality speech from text using Chatterbox TTS</p>
      </div>
      
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
        <!-- Input Section -->
        <div class="input-section">
          <form phx-submit="generate_speech" class="space-y-6">
            <!-- Text Input -->
            <div>
              <label for="text_input" class="block text-sm font-medium text-gray-700 mb-2">
                Text to Convert
              </label>
              <textarea
                id="text_input"
                name="text_input"
                phx-change="update_text"
                value={@text_input}
                rows="8"
                maxlength="2000"
                placeholder="Enter the text you want to convert to speech..."
                class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500"
              ></textarea>
              <div class="text-right text-sm mt-1">
                <span class={[
                  if(String.length(@text_input) > 800, do: "text-orange-600", else: "text-gray-500")
                ]}>
                  <%= String.length(@text_input) %>/2000 characters
                </span>
                <%= if String.length(@text_input) > 800 do %>
                  <div class="text-xs text-orange-600 mt-1">
                    ⚠️ Long text will be processed in chunks (may take longer)
                  </div>
                <% end %>
              </div>
            </div>
            
            <!-- Accent Selection -->
            <div>
              <label for="accent" class="block text-sm font-medium text-gray-700 mb-2">
                Accent/Region
              </label>
              <select
                id="accent"
                name="accent"
                phx-change="update_accent"
                class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500"
              >
                <%= for {label, value} <- @accents do %>
                  <option value={value} selected={@selected_accent == value}>
                    <%= label %>
                  </option>
                <% end %>
              </select>
            </div>
            
            <!-- Voice Settings -->
            <div class="voice-settings space-y-4">
              <h3 class="text-lg font-medium text-gray-700">Voice Settings</h3>
              
              <!-- Pitch -->
              <div>
                <label for="pitch" class="block text-sm font-medium text-gray-700 mb-1">
                  Pitch: <%= @voice_settings.pitch %>
                </label>
                <input
                  type="range"
                  id="pitch"
                  name="pitch"
                  min="0.5"
                  max="2.0"
                  step="0.1"
                  value={@voice_settings.pitch}
                  phx-change="update_voice_settings"
                  class="w-full"
                />
              </div>
              
              <!-- Speed -->
              <div>
                <label for="speed" class="block text-sm font-medium text-gray-700 mb-1">
                  Speed: <%= @voice_settings.speed %>
                </label>
                <input
                  type="range"
                  id="speed"
                  name="speed"
                  min="0.5"
                  max="2.0"
                  step="0.1"
                  value={@voice_settings.speed}
                  phx-change="update_voice_settings"
                  class="w-full"
                />
              </div>
              
              <!-- Tone -->
              <div>
                <label for="tone" class="block text-sm font-medium text-gray-700 mb-2">
                  Tone
                </label>
                <select
                  id="tone"
                  name="tone"
                  phx-change="update_voice_settings"
                  class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500"
                >
                  <option value="neutral" selected={@voice_settings.tone == "neutral"}>Neutral</option>
                  <option value="happy" selected={@voice_settings.tone == "happy"}>Happy</option>
                  <option value="serious" selected={@voice_settings.tone == "serious"}>Serious</option>
                  <option value="calm" selected={@voice_settings.tone == "calm"}>Calm</option>
                  <option value="excited" selected={@voice_settings.tone == "excited"}>Excited</option>
                </select>
              </div>
            </div>
            
            <!-- Generate Button -->
            <button
              type="submit"
              disabled={@generation_status == :generating or String.length(@text_input) == 0}
              class={[
                "w-full py-3 px-4 rounded-md font-medium transition-colors",
                if(@generation_status == :generating or String.length(@text_input) == 0,
                  do: "bg-gray-300 text-gray-500 cursor-not-allowed",
                  else: "bg-blue-600 text-white hover:bg-blue-700"
                )
              ]}
            >
              <%= case @generation_status do %>
                <% :generating -> %>
                  <span class="flex items-center justify-center">
                    <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                    <%= if String.length(@text_input) > 800 do %>
                      Generating Speech (Long Text)...
                    <% else %>
                      Generating Speech...
                    <% end %>
                  </span>
                <% _ -> %>
                  Generate Speech
              <% end %>
            </button>
          </form>
        </div>
        
        <!-- Preview Section -->
        <div class="preview-section">
          <h3 class="text-lg font-medium text-gray-700 mb-4">Preview</h3>
          
          <%= if @last_generated_clip do %>
            <div class="audio-preview bg-gray-50 rounded-lg p-6">
              <div class="mb-4">
                <p class="text-sm text-gray-600 mb-2">Generated Text:</p>
                <div class="bg-white p-3 rounded border text-sm">
                  <%= @last_generated_clip.source_text %>
                </div>
              </div>
              
              <div class="mb-4">
                <p class="text-sm text-gray-600 mb-2">Settings:</p>
                <div class="text-sm space-y-1">
                  <p><span class="font-medium">Accent:</span> <%= accent_label(@last_generated_clip.accent, @accents) %></p>
                  <p><span class="font-medium">Pitch:</span> <%= @last_generated_clip.voice_settings["pitch"] || 1.0 %></p>
                  <p><span class="font-medium">Speed:</span> <%= @last_generated_clip.voice_settings["speed"] || 1.0 %></p>
                  <p><span class="font-medium">Tone:</span> <%= @last_generated_clip.voice_settings["tone"] || "neutral" %></p>
                </div>
              </div>
              
              <!-- Audio Player -->
              <div class="audio-player">
                <audio controls class="w-full">
                  <source src={AudioClip.get_audio_data_url(@last_generated_clip)} type="audio/wav">
                  Your browser does not support the audio element.
                </audio>
              </div>
              
              <!-- Action Buttons -->
              <div class="flex gap-2 mt-4">
                <button
                  phx-click="save_clip"
                  phx-value-clip_id={@last_generated_clip.clip_id}
                  class="px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 transition-colors"
                >
                  Save to Library
                </button>
                <button
                  phx-click="regenerate"
                  class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors"
                >
                  Regenerate
                </button>
              </div>
            </div>
          <% else %>
            <div class="empty-preview bg-gray-50 rounded-lg p-12 text-center">
              <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 4V2a1 1 0 011-1h8a1 1 0 011 1v2h4a1 1 0 110 2h-1v14a2 2 0 01-2 2H6a2 2 0 01-2-2V6H3a1 1 0 110-2h4zM9 6h6v11a1 1 0 01-1 1H10a1 1 0 01-1-1V6z"/>
              </svg>
              <p class="text-gray-500 mt-2">Enter text and click "Generate Speech" to preview</p>
            </div>
          <% end %>
        </div>
      </div>
      
      <!-- Status Messages -->
      <%= if @generation_status == :error do %>
        <div class="mt-6 bg-red-50 border border-red-200 rounded-md p-4">
          <div class="flex">
            <svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
            </svg>
            <div class="ml-3">
              <h3 class="text-sm font-medium text-red-800">Generation Failed</h3>
              <p class="text-sm text-red-700 mt-1">
                There was an error generating the speech. 
                <%= if String.length(@text_input) > 800 do %>
                  For long text, try breaking it into smaller sections.
                <% else %>
                  Please try again or try a shorter text.
                <% end %>
              </p>
            </div>
          </div>
        </div>
      <% end %>
      
      <%= if @generation_status == :generating and String.length(@text_input) > 800 do %>
        <div class="mt-6 bg-blue-50 border border-blue-200 rounded-md p-4">
          <div class="flex">
            <svg class="animate-spin h-5 w-5 text-blue-400" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            <div class="ml-3">
              <h3 class="text-sm font-medium text-blue-800">Processing Long Text</h3>
              <p class="text-sm text-blue-700 mt-1">
                Your text is being processed in chunks for optimal quality. This may take 2-5 minutes depending on length.
              </p>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
  
  @impl true
  def handle_event("update_text", %{"text_input" => text}, socket) do
    {:noreply, assign(socket, text_input: text)}
  end
  
  @impl true
  def handle_event("update_accent", %{"accent" => accent}, socket) do
    {:noreply, assign(socket, selected_accent: accent)}
  end
  
  @impl true
  def handle_event("update_voice_settings", params, socket) do
    current_settings = socket.assigns.voice_settings
    
    new_settings = 
      current_settings
      |> maybe_update_float(params, "pitch")
      |> maybe_update_float(params, "speed")
      |> maybe_update_string(params, "tone")
    
    {:noreply, assign(socket, voice_settings: new_settings)}
  end
  
  @impl true
  def handle_event("generate_speech", %{"text_input" => text}, socket) do
    if String.length(text) > 0 do
      # Extract assigns to avoid copying socket to async process
      assigns = %{
        session_id: socket.assigns.session_id,
        user_id: socket.assigns.user_id,
        selected_accent: socket.assigns.selected_accent,
        voice_settings: socket.assigns.voice_settings
      }
      
      {:noreply, 
       socket
       |> assign(generation_status: :generating)
       |> start_async(:generate_tts, fn -> generate_tts(assigns, text) end)}
    else
      {:noreply, socket}
    end
  end
  
  @impl true
  def handle_event("save_clip", %{"clip_id" => _clip_id}, socket) do
    Logger.info("Save clip button clicked")
    if socket.assigns.last_generated_clip do
      clip = socket.assigns.last_generated_clip
      Logger.info("Found clip to save: #{clip.clip_id}")
      
      # Create a voice session for this clip if it doesn't exist
      session_string = clip.session_id
      Logger.info("Looking for voice session: #{session_string}")
      {db_session_id, _} = case VoxDialog.Voice.get_voice_session_by_session_id(session_string) do
        nil ->
          Logger.info("Creating new voice session")
          # Create voice session
          case VoxDialog.Voice.create_voice_session(%{
            session_id: session_string,
            user_id: clip.user_id,
            started_at: DateTime.utc_now()
          }) do
            {:ok, session} -> 
              Logger.info("Created session with ID: #{session.id}")
              {session.id, session}
            {:error, reason} -> 
              Logger.error("Failed to create session: #{inspect(reason)}")
              {nil, nil}
          end
        session ->
          Logger.info("Found existing session with ID: #{session.id}")
          {session.id, session}
      end
      
      if db_session_id do
        # Save the clip to the database
        # Note: create_audio_clip automatically sets recorded_at, clip_id, and file_size
        clip_attrs = %{
          session_id: db_session_id,
          user_id: clip.user_id,
          audio_data: clip.audio_data,
          duration_ms: clip.duration_ms,
          format: clip.format,
          sample_rate: clip.sample_rate,
          transcription_status: "completed",
          transcribed_text: clip.transcribed_text,
          audio_type: "tts",
          source_text: clip.source_text,
          accent: clip.accent,
          voice_settings: %{
            "pitch" => clip.voice_settings.pitch,
            "speed" => clip.voice_settings.speed,
            "tone" => clip.voice_settings.tone
          }
        }
        
        Logger.info("Attempting to save clip with session_id: #{db_session_id}")
        case VoxDialog.Voice.create_audio_clip(clip_attrs) do
          {:ok, saved_clip} ->
            Logger.info("Successfully saved clip: #{saved_clip.clip_id}")
            {:noreply, put_flash(socket, :info, "Audio clip saved to library successfully!")}
          {:error, changeset} ->
            Logger.error("Failed to save clip: #{inspect(changeset.errors)}")
            {:noreply, put_flash(socket, :error, "Failed to save audio clip to library. Check logs for details.")}
        end
      else
        {:noreply, put_flash(socket, :error, "Failed to create voice session for the clip.")}
      end
    else
      {:noreply, put_flash(socket, :error, "No audio clip to save.")}
    end
  end
  
  @impl true
  def handle_event("regenerate", _params, socket) do
    text = socket.assigns.text_input
    if String.length(text) > 0 do
      # Extract assigns to avoid copying socket to async process
      assigns = %{
        session_id: socket.assigns.session_id,
        user_id: socket.assigns.user_id,
        selected_accent: socket.assigns.selected_accent,
        voice_settings: socket.assigns.voice_settings
      }
      
      {:noreply, 
       socket
       |> assign(generation_status: :generating)
       |> start_async(:generate_tts, fn -> generate_tts(assigns, text) end)}
    else
      {:noreply, socket}
    end
  end
  
  @impl true
  def handle_async(:generate_tts, {:ok, result}, socket) do
    case result do
      {:ok, audio_clip} ->
        {:noreply, 
         socket
         |> assign(generation_status: :idle, last_generated_clip: audio_clip)
         |> put_flash(:info, "Speech generated successfully!")}
      
      {:error, reason} ->
        Logger.error("TTS generation failed: #{inspect(reason)}")
        {:noreply, 
         socket
         |> assign(generation_status: :error)
         |> put_flash(:error, "Failed to generate speech. Please try again.")}
    end
  end
  
  @impl true
  def handle_async(:generate_tts, {:exit, reason}, socket) do
    Logger.error("TTS generation crashed: #{inspect(reason)}")
    {:noreply, 
     socket
     |> assign(generation_status: :error)
     |> put_flash(:error, "Speech generation timed out or crashed. Please try again.")}
  end
  
  # Private Functions
  
  defp generate_tts(assigns, text) do
    # Prepare TTS options
    options = %{
      "accent" => assigns.selected_accent,
      "voice_settings" => %{
        "pitch" => assigns.voice_settings.pitch,
        "speed" => assigns.voice_settings.speed,
        "tone" => assigns.voice_settings.tone
      }
    }
    
    case ChatterboxServer.synthesize(text, options) do
      {:ok, audio_data} ->
        # Create temporary audio clip (not saved to DB yet)
        clip_id = AudioClip.generate_clip_id()
        
        # Calculate audio duration (approximation for WAV files)
        # WAV format: 24kHz sample rate, 16-bit samples, mono
        sample_rate = 24000
        bytes_per_sample = 2  # 16-bit = 2 bytes
        audio_data_size = byte_size(audio_data)
        
        # Subtract WAV header size (typically 44 bytes)
        audio_samples = max(0, audio_data_size - 44) / bytes_per_sample
        duration_ms = round((audio_samples / sample_rate) * 1000)
        
        audio_clip = %AudioClip{
          clip_id: clip_id,
          session_id: assigns.session_id,
          user_id: assigns.user_id,
          audio_data: audio_data,
          duration_ms: duration_ms,
          format: "wav",
          sample_rate: sample_rate,
          audio_type: "tts",
          source_text: text,
          accent: assigns.selected_accent,
          voice_settings: assigns.voice_settings,
          recorded_at: DateTime.utc_now(),
          file_size: byte_size(audio_data),
          transcription_status: "completed",
          transcribed_text: text
        }
        
        {:ok, audio_clip}
      
      {:error, reason} ->
        {:error, reason}
    end
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
  
  defp maybe_update_string(settings, params, key) do
    case Map.get(params, key) do
      nil -> settings
      value -> Map.put(settings, String.to_atom(key), value)
    end
  end
  
  defp accent_label(accent_value, accents) do
    case Enum.find(accents, fn {_label, value} -> value == accent_value end) do
      {label, _} -> label
      nil -> accent_value
    end
  end
  
  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
  
  defp get_user_id(_socket) do
    # Generate a session-based user ID for now
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end