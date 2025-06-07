defmodule VoxDialogWeb.VoiceSessionLive do
 use VoxDialogWeb, :live_view
 require Logger

 @impl true
 def mount(_params, _session, socket) do
   session_id = generate_session_id()
   user_id = get_user_id(socket)
   
   if connected?(socket) do
     {:ok, _pid} = VoxDialog.VoiceProcessing.SessionSupervisor.start_session(session_id, user_id)
     
     Phoenix.PubSub.subscribe(VoxDialog.PubSub, "voice_session:#{session_id}")
     Phoenix.PubSub.subscribe(VoxDialog.PubSub, "transcription_results")
   end
   
   available_backends = if connected?(socket) do
     VoxDialog.SpeechRecognition.available_backends()
   else
     []
   end
   
   current_backend = if connected?(socket) do
     case VoxDialog.SpeechRecognition.get_backend_info() do
       {:ok, info} -> info
       _ -> nil
     end
   else
     nil
   end

   available_models = if connected?(socket) do
     case VoxDialog.SpeechRecognition.WhisperFaster.get_available_models() do
       {:ok, models} -> models
       _ -> ["tiny", "base", "small", "medium", "large"]
     end
   else
     []
   end
   
   {:ok, assign(socket,
     session_id: session_id,
     user_id: user_id,
     recording_state: :idle,
     conversation_history: [],
     audio_level: 0.0,
     detected_sounds: [],
     available_backends: available_backends,
     current_backend: current_backend,
     backend_switching: false,
     available_whisper_models: available_models,
     selected_model: "tiny"
   )}
 end

 @impl true
 def render(assigns) do
   ~H"""
   <div class="voice-session-container">
     <div class="backend-controls mb-4">
       <h3 class="text-lg font-semibold mb-2">Speech Recognition Backend</h3>
       <%= if @current_backend do %>
         <div class="current-backend mb-2">
           <span class="text-sm text-gray-600">Current: </span>
           <span class="font-medium"><%= @current_backend.name %></span>
           <%= if @current_backend[:description] do %>
             <span class="text-xs text-gray-500 ml-2">- <%= @current_backend.description %></span>
           <% end %>
         </div>
       <% end %>
       
       <%= if length(@available_backends) > 1 do %>
         <div class="backend-selector">
           <label for="backend-select" class="text-sm text-gray-600">Switch Backend:</label>
           <select 
             id="backend-select" 
             phx-change="switch_backend" 
             name="backend"
             disabled={@backend_switching}
             class="ml-2 px-2 py-1 border border-gray-300 rounded text-sm"
           >
             <%= for backend <- @available_backends do %>
               <option 
                 value={backend} 
                 selected={@current_backend && @current_backend.backend == backend}
               >
                 <%= String.capitalize(to_string(backend)) %>
               </option>
             <% end %>
           </select>
           <%= if @backend_switching do %>
             <span class="ml-2 text-sm text-blue-600">Switching...</span>
           <% end %>
         </div>
       <% end %>

       <div class="model-selector mt-2">
         <label for="model-select" class="text-sm text-gray-600">Model:</label>
         <select 
           id="model-select" 
           phx-change="change_model" 
           name="model"
           class="ml-2 px-2 py-1 border border-gray-300 rounded text-sm"
         >
           <%= for model <- @available_whisper_models do %>
             <option 
               value={model} 
               selected={@selected_model == model}
             >
               <%= model %>
             </option>
           <% end %>
         </select>
       </div>
     </div>
     
     <div class="session-header">
       <h1 class="text-2xl font-bold">VoxDialog Voice Session</h1>
       <p class="text-sm text-gray-600">Session ID: <%= @session_id %></p>
     </div>
     
     <div class="audio-controls mt-8">
       <div class="recording-status mb-4">
         <div class="flex items-center">
           <div class={[
             "recording-indicator",
             @recording_state == :recording && "recording-active"
           ]}>
           </div>
           <span class="ml-2">
             <%= recording_status_text(@recording_state) %>
           </span>
         </div>
         
         <div class="audio-level-meter mt-2">
           <div class="audio-level-bar" style={"width: #{@audio_level * 100}%"}></div>
         </div>
       </div>
       
       <button
         phx-click="toggle_recording"
         class={[
           "recording-button",
           @recording_state == :recording && "recording-button-active"
         ]}
       >
         <%= if @recording_state == :recording, do: "Stop Recording", else: "Start Recording" %>
       </button>
     </div>
     
     <div class="conversation-display mt-8">
       <h2 class="text-xl font-semibold mb-4">Conversation</h2>
       <div class="conversation-messages">
         <%= for message <- @conversation_history do %>
           <div class={"message message-#{message.type}"}>
             <span class="message-time"><%= format_time(message.timestamp) %></span>
             <span class="message-content"><%= message.content %></span>
           </div>
         <% end %>
       </div>
     </div>
     
     <%= if length(@detected_sounds) > 0 do %>
       <div class="environmental-sounds mt-8">
         <h2 class="text-xl font-semibold mb-4">Detected Sounds</h2>
         <div class="sound-alerts">
           <%= for sound <- @detected_sounds do %>
             <div class="sound-alert">
               <span class="sound-type"><%= humanize_sound(sound.type) %></span>
               <span class="sound-time"><%= format_time(sound.timestamp) %></span>
             </div>
           <% end %>
         </div>
       </div>
     <% end %>
     
     <div id="audio-processor" phx-hook="AudioProcessor" data-session-id={@session_id}></div>
   </div>
   
   <style>
     .voice-session-container {
       max-width: 800px;
       margin: 0 auto;
       padding: 2rem;
     }
     
     .recording-indicator {
       width: 12px;
       height: 12px;
       border-radius: 50%;
       background-color: #ccc;
     }
     
     .recording-indicator.recording-active {
       background-color: #ef4444;
       animation: pulse 1.5s infinite;
     }
     
     @keyframes pulse {
       0% { opacity: 1; }
       50% { opacity: 0.5; }
       100% { opacity: 1; }
     }
     
     .audio-level-meter {
       width: 100%;
       height: 4px;
       background-color: #e5e7eb;
       border-radius: 2px;
       overflow: hidden;
     }
     
     .audio-level-bar {
       height: 100%;
       background-color: #10b981;
       transition: width 0.1s ease;
     }
     
     .recording-button {
       padding: 0.75rem 2rem;
       font-size: 1.125rem;
       font-weight: 600;
       color: white;
       background-color: #3b82f6;
       border-radius: 0.5rem;
       transition: background-color 0.2s;
     }
     
     .recording-button:hover {
       background-color: #2563eb;
     }
     
     .recording-button-active {
       background-color: #ef4444;
     }
     
     .recording-button-active:hover {
       background-color: #dc2626;
     }
     
     .conversation-messages {
       max-height: 400px;
       overflow-y: auto;
       border: 1px solid #e5e7eb;
       border-radius: 0.5rem;
       padding: 1rem;
     }
     
     .message {
       margin-bottom: 0.75rem;
       padding: 0.5rem;
       border-radius: 0.25rem;
     }
     
     .message-user {
       background-color: #dbeafe;
       text-align: right;
     }
     
     .message-assistant {
       background-color: #f3f4f6;
     }
     
     .message-time {
       font-size: 0.75rem;
       color: #6b7280;
       margin-right: 0.5rem;
     }
     
     .sound-alert {
       padding: 0.5rem 1rem;
       background-color: #fef3c7;
       border: 1px solid #fbbf24;
       border-radius: 0.25rem;
       margin-bottom: 0.5rem;
       display: flex;
       justify-content: space-between;
     }
   </style>
   """
 end

 @impl true
 def handle_event("toggle_recording", _params, socket) do
   case socket.assigns.recording_state do
     :idle ->
       {:noreply, 
        socket
        |> assign(recording_state: :recording)
        |> push_event("start_recording", %{})}
       
     :recording ->
       {:noreply, 
        socket
        |> assign(recording_state: :idle)
        |> push_event("stop_recording", %{})}
   end
 end

 @impl true
 def handle_event("switch_backend", %{"backend" => backend_str}, socket) do
   backend_type = String.to_atom(backend_str)
   
   if backend_type in socket.assigns.available_backends do
     {:noreply, 
      socket
      |> assign(backend_switching: true)
      |> start_async(:switch_backend, fn -> 
        VoxDialog.SpeechRecognition.switch_backend(backend_type)
      end)}
   else
     {:noreply, put_flash(socket, :error, "Backend not available: #{backend_str}")}
   end
 end

 @impl true
 def handle_event("change_model", %{"model" => model}, socket) do
   if model in socket.assigns.available_whisper_models do
     {:noreply, 
      socket
      |> assign(selected_model: model)
      |> start_async(:change_model, fn -> 
        Logger.info("Model change requested to: #{model}")
        :ok
      end)}
   else
     {:noreply, put_flash(socket, :error, "Invalid model selected")}
   end
 end

 @impl true
 def handle_event("audio_data", %{"data" => audio_data, "duration" => duration}, socket) do
   Logger.info("Received audio data: duration=#{duration}ms, data_length=#{String.length(audio_data)}")
   
   case save_audio_clip(socket, audio_data, duration) do
     {:ok, audio_clip} ->
       VoxDialog.VoiceProcessing.SessionServer.process_audio_chunk(
         socket.assigns.session_id,
         decode_audio_data(audio_data)
       )
       
       message = %{
         type: :system,
         content: "Audio clip saved (#{format_duration(duration)})",
         timestamp: DateTime.utc_now(),
         clip_id: audio_clip.clip_id
       }
       
       {:noreply, update(socket, :conversation_history, &(&1 ++ [message]))}
       
     {:error, _changeset} ->
       message = %{
         type: :system,
         content: "Failed to save audio clip",
         timestamp: DateTime.utc_now()
       }
       
       {:noreply, update(socket, :conversation_history, &(&1 ++ [message]))}
   end
 end

 @impl true
 def handle_event("audio_data", %{"data" => audio_data}, socket) do
   handle_event("audio_data", %{"data" => audio_data, "duration" => nil}, socket)
 end

 @impl true
 def handle_event("audio_level", %{"level" => level}, socket) do
   {:noreply, assign(socket, audio_level: level)}
 end

 @impl true
 def handle_async(:switch_backend, {:ok, result}, socket) do
   case result do
     :ok ->
       case VoxDialog.SpeechRecognition.get_backend_info() do
         {:ok, info} ->
           {:noreply, 
            socket
            |> assign(backend_switching: false, current_backend: info)
            |> put_flash(:info, "Successfully switched to #{info.name}")}
         _ ->
           {:noreply, 
            socket
            |> assign(backend_switching: false)
            |> put_flash(:info, "Backend switched successfully")}
       end
     {:error, reason} ->
       {:noreply, 
        socket
        |> assign(backend_switching: false)
        |> put_flash(:error, "Failed to switch backend: #{inspect(reason)}")}
   end
 end

 @impl true
 def handle_async(:switch_backend, {:exit, reason}, socket) do
   {:noreply, 
    socket
    |> assign(backend_switching: false)
    |> put_flash(:error, "Backend switch failed: #{inspect(reason)}")}
 end

 @impl true
 def handle_async(:change_model, {:ok, _result}, socket) do
   {:noreply, put_flash(socket, :info, "Model change logged")}
 end

 @impl true
 def handle_async(:change_model, {:exit, reason}, socket) do
   {:noreply, put_flash(socket, :error, "Model change failed: #{inspect(reason)}")}
 end

 @impl true
 def handle_info({:voice_activity_detected, :user_speech, data}, socket) do
   message = %{
     type: :user,
     content: "User speaking...",
     timestamp: DateTime.utc_now(),
     confidence: data.confidence
   }
   
   {:noreply, update(socket, :conversation_history, &(&1 ++ [message]))}
 end

 @impl true
 def handle_info({:voice_activity_detected, :environmental_sound, data}, socket) do
   sound = %{
     type: data.type,
     timestamp: DateTime.utc_now()
   }
   
   {:noreply, update(socket, :detected_sounds, &(&1 ++ [sound]))}
 end

 @impl true
 def handle_info({:transcription_result, text}, socket) do
   updated_history = update_last_user_message(socket.assigns.conversation_history, text)
   {:noreply, assign(socket, conversation_history: updated_history)}
 end

 @impl true
 def handle_info({:assistant_response, response}, socket) do
   message = %{
     type: :assistant,
     content: response,
     timestamp: DateTime.utc_now()
   }
   
   {:noreply, update(socket, :conversation_history, &(&1 ++ [message]))}
 end

 @impl true
 def handle_info({:transcription_complete, clip_id, transcription}, socket) do
   message = %{
     type: :user,
     content: transcription,
     timestamp: DateTime.utc_now(),
     clip_id: clip_id
   }
   
   Logger.info("Transcription completed for clip #{clip_id}: #{transcription}")
   
   {:noreply, update(socket, :conversation_history, &(&1 ++ [message]))}
 end

 defp generate_session_id do
   :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
 end

 defp get_user_id(_socket) do
   "test_user_123"
 end

 defp recording_status_text(:idle), do: "Ready to record"
 defp recording_status_text(:recording), do: "Recording..."
 defp recording_status_text(:processing), do: "Processing..."

 defp format_time(datetime) do
   Calendar.strftime(datetime, "%H:%M:%S")
 end

 defp humanize_sound(sound_type) do
   sound_type
   |> Atom.to_string()
   |> String.replace("_", " ")
   |> String.capitalize()
 end

 defp decode_audio_data(base64_data) do
   {:ok, binary} = Base.decode64(base64_data)
   
   for <<sample::16-signed-native <- binary>>, do: sample / 32768.0
 end

 defp save_audio_clip(socket, base64_audio_data, duration) do
   Logger.info("save_audio_clip called with duration=#{duration}, data_length=#{String.length(base64_audio_data)}")
   
   session = get_or_create_voice_session(socket.assigns.session_id, socket.assigns.user_id)
   Logger.info("Voice session: #{inspect(session)}")
   
   case Base.decode64(base64_audio_data) do
     {:ok, binary_audio_data} ->
       Logger.info("Successfully decoded base64 audio data, size: #{byte_size(binary_audio_data)} bytes")
       
       result = VoxDialog.Voice.create_audio_clip(%{
         session_id: session.id,
         user_id: socket.assigns.user_id,
         audio_data: binary_audio_data,
         duration_ms: duration,
         format: "webm"
       })
       
       case result do
         {:ok, clip} ->
           Logger.info("Successfully saved audio clip: #{clip.clip_id}")
           
           VoxDialog.SpeechRecognition.TranscriptionWorker.queue_transcription(clip)
           
           result
         {:error, changeset} ->
           Logger.error("Failed to save audio clip: #{inspect(changeset.errors)}")
           result
       end
       
     :error ->
       Logger.error("Failed to decode base64 audio data")
       {:error, :invalid_audio_data}
   end
 end

 defp get_or_create_voice_session(session_id, user_id) do
   case VoxDialog.Voice.get_voice_session_by_session_id(session_id) do
     nil ->
       {:ok, session} = VoxDialog.Voice.create_voice_session(%{
         session_id: session_id,
         user_id: user_id
       })
       session
       
     session ->
       session
   end
 end

 defp format_duration(nil), do: "unknown duration"
 defp format_duration(duration_ms) when is_integer(duration_ms) do
   seconds = duration_ms / 1000
   "#{:erlang.float_to_binary(seconds, [{:decimals, 1}])}s"
 end
 defp format_duration(_), do: "unknown duration"

 defp update_last_user_message(history, text) do
   case Enum.reverse(history) do
     [%{type: :user} = last | rest] ->
       updated = %{last | content: text}
       Enum.reverse([updated | rest])
       
     _ ->
       history
   end
 end
end
