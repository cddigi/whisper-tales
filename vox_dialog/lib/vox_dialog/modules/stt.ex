defmodule VoxDialog.Modules.STT do
 @moduledoc """
 Speech-to-Text module implementation.
 Converts audio input to text output using configurable Whisper backends.
 """
 
 @behaviour VoxDialog.ModuleSystem
 
 require Logger
 
 @impl true
 def info do
   %{
     id: "stt",
     name: "Speech-to-Text",
     version: "1.0.0",
     interface: %{
       input: "audio/webm",
       output: "text/plain"
     }
   }
 end
 
 @impl true
 def initialize(opts) do
   case VoxDialog.SpeechRecognition.WhisperServer.check_availability() do
     :ok -> 
       backend_type = Map.get(opts, :backend_type)
       
       state = %{
         status: :ready,
         backend_type: backend_type,
         preferred_backend: backend_type
       }
       
       if backend_type do
         case VoxDialog.SpeechRecognition.switch_backend(backend_type) do
           :ok -> 
             Logger.info("STT module initialized with #{backend_type} backend")
             {:ok, state}
           {:error, reason} ->
             Logger.warning("Failed to switch to preferred backend #{backend_type}: #{inspect(reason)}")
             {:ok, %{state | backend_type: nil}}
         end
       else
         {:ok, state}
       end
       
     {:error, reason} ->
       {:error, {:initialization_failed, reason}}
   end
 end
 
 @impl true
 def process(audio_data, state) when is_binary(audio_data) do
   Logger.info("STT module processing audio data of size: #{byte_size(audio_data)}")
   
   if state.preferred_backend && state.preferred_backend != state.backend_type do
     case VoxDialog.SpeechRecognition.switch_backend(state.preferred_backend) do
       :ok -> 
         Logger.debug("Switched to preferred backend: #{state.preferred_backend}")
       {:error, reason} ->
         Logger.warning("Failed to switch to preferred backend: #{inspect(reason)}")
     end
   end
   
   clip_id = VoxDialog.Voice.AudioClip.generate_clip_id()
   
   case save_and_transcribe(audio_data, clip_id) do
     {:ok, transcription} ->
       new_state = Map.put(state, :last_transcription, transcription)
       {:ok, transcription, new_state}
     {:error, reason} ->
       Logger.error("STT processing failed: #{inspect(reason)}")
       {:error, reason}
   end
 end
 
 @impl true
 def shutdown(_state) do
   Logger.info("STT module shutting down")
   :ok
 end
 
 defp save_and_transcribe(audio_data, clip_id) do
   session = %{
     id: System.unique_integer([:positive]),
     session_id: "stt_module_#{clip_id}"
   }
   
   clip_attrs = %{
     session_id: session.id,
     user_id: "stt_module",
     audio_data: audio_data,
     format: "webm",
     clip_id: clip_id
   }
   
   case VoxDialog.Voice.create_audio_clip(clip_attrs) do
     {:ok, clip} ->
       case VoxDialog.SpeechRecognition.WhisperServer.transcribe_audio(clip) do
         {:ok, transcription} ->
           {:ok, transcription}
         error ->
           error
       end
     {:error, reason} ->
       {:error, {:save_failed, reason}}
   end
 end
end
