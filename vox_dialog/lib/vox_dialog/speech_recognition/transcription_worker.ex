defmodule VoxDialog.SpeechRecognition.TranscriptionWorker do
  @moduledoc """
  GenServer worker that processes audio clips for transcription in the background.
  Handles queuing, retry logic, and progress tracking.
  """
  
  use GenServer
  require Logger
  
  alias VoxDialog.SpeechRecognition

  @process_interval_ms 5000  # Check for new clips every 5 seconds
  @max_concurrent_jobs 3     # Maximum concurrent transcription jobs

  defstruct [:pending_queue, :active_jobs, :processed_count, :failed_count]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Adds an audio clip to the transcription queue.
  """
  def queue_transcription(audio_clip) do
    GenServer.cast(__MODULE__, {:queue_clip, audio_clip})
  end

  @doc """
  Gets the current worker status.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Processes pending clips immediately (for manual triggering).
  """
  def process_now do
    GenServer.cast(__MODULE__, :process_now)
  end

  # GenServer Callbacks

  @impl true
  def init([]) do
    # Schedule periodic processing
    schedule_processing()
    
    state = %__MODULE__{
      pending_queue: :queue.new(),
      active_jobs: %{},
      processed_count: 0,
      failed_count: 0
    }
    
    Logger.info("TranscriptionWorker started")
    {:ok, state}
  end

  @impl true
  def handle_cast({:queue_clip, audio_clip}, state) do
    Logger.info("Queuing clip #{audio_clip.clip_id} for transcription")
    
    updated_queue = :queue.in(audio_clip, state.pending_queue)
    new_state = %{state | pending_queue: updated_queue}
    
    # Try to process immediately if we have capacity
    {:noreply, maybe_process_clips(new_state)}
  end

  @impl true
  def handle_cast(:process_now, state) do
    {:noreply, maybe_process_clips(state)}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      pending_count: :queue.len(state.pending_queue),
      active_jobs: map_size(state.active_jobs),
      processed_count: state.processed_count,
      failed_count: state.failed_count,
      active_clip_ids: Map.values(state.active_jobs) |> Enum.map(& &1.clip_id)
    }
    
    {:reply, status, state}
  end

  @impl true
  def handle_info(:process_clips, state) do
    # Schedule next processing
    schedule_processing()
    
    # Process pending clips
    {:noreply, maybe_process_clips(state)}
  end

  @impl true
  def handle_info({:transcription_complete, clip_id, result}, state) do
    case Map.pop(state.active_jobs, clip_id) do
      {nil, _} ->
        Logger.warning("Received completion for unknown clip: #{clip_id}")
        {:noreply, state}
        
      {_clip, updated_jobs} ->
        case result do
          {:ok, transcription} ->
            Logger.info("Transcription completed for clip #{clip_id}: #{String.slice(transcription, 0, 50)}...")
            
            # Broadcast transcription result
            Phoenix.PubSub.broadcast(
              VoxDialog.PubSub,
              "transcription_results",
              {:transcription_complete, clip_id, transcription}
            )
            
            new_state = %{state | 
              active_jobs: updated_jobs,
              processed_count: state.processed_count + 1
            }
            
            {:noreply, maybe_process_clips(new_state)}
            
          {:error, reason} ->
            Logger.error("Transcription failed for clip #{clip_id}: #{inspect(reason)}")
            
            new_state = %{state | 
              active_jobs: updated_jobs,
              failed_count: state.failed_count + 1
            }
            
            {:noreply, maybe_process_clips(new_state)}
        end
    end
  end

  # Private Functions

  defp schedule_processing do
    Process.send_after(self(), :process_clips, @process_interval_ms)
  end

  defp maybe_process_clips(state) do
    if map_size(state.active_jobs) < @max_concurrent_jobs and not :queue.is_empty(state.pending_queue) do
      case :queue.out(state.pending_queue) do
        {{:value, clip}, remaining_queue} ->
          # Start transcription job
          worker_pid = self()
          
          _task = Task.start(fn ->
            result = SpeechRecognition.transcribe_audio_clip(clip)
            send(worker_pid, {:transcription_complete, clip.clip_id, result})
          end)
          
          updated_jobs = Map.put(state.active_jobs, clip.clip_id, clip)
          updated_state = %{state | 
            pending_queue: remaining_queue,
            active_jobs: updated_jobs
          }
          
          Logger.info("Started transcription job for clip #{clip.clip_id}")
          
          # Try to process more clips if we still have capacity
          maybe_process_clips(updated_state)
          
        {:empty, _} ->
          state
      end
    else
      state
    end
  end
end