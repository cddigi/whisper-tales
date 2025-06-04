defmodule VoxDialog.VoiceProcessing.AudioBuffer do
  @moduledoc """
  Implements intelligent audio buffering using circular buffer patterns.
  Prevents memory leaks during extended conversations while maintaining
  sufficient history for contextual analysis.
  """
  use GenServer
  require Logger

  defstruct [:max_size, :buffer, :total_samples, :sample_rate]

  @default_max_size 480_000  # 30 seconds at 16kHz
  @default_sample_rate 16_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def add_samples(pid, samples) do
    GenServer.cast(pid, {:add_samples, samples})
  end

  def get_buffer(pid, duration_ms \\ nil) do
    GenServer.call(pid, {:get_buffer, duration_ms})
  end

  def clear(pid) do
    GenServer.cast(pid, :clear)
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      max_size: opts[:max_size] || @default_max_size,
      buffer: :queue.new(),
      total_samples: 0,
      sample_rate: opts[:sample_rate] || @default_sample_rate
    }
    
    {:ok, state}
  end

  @impl true
  def handle_cast({:add_samples, samples}, state) do
    # Add new samples to the buffer
    updated_buffer = :queue.in(samples, state.buffer)
    new_total = state.total_samples + length(samples)
    
    # Trim buffer if it exceeds max size
    {trimmed_buffer, trimmed_total} = 
      trim_buffer(updated_buffer, new_total, state.max_size)
    
    {:noreply, %{state | buffer: trimmed_buffer, total_samples: trimmed_total}}
  end

  @impl true
  def handle_cast(:clear, state) do
    {:noreply, %{state | buffer: :queue.new(), total_samples: 0}}
  end

  @impl true
  def handle_call({:get_buffer, duration_ms}, _from, state) do
    samples = case duration_ms do
      nil -> 
        # Return all samples
        flatten_buffer(state.buffer)
        
      ms when is_integer(ms) ->
        # Return last N milliseconds of samples
        sample_count = round(ms * state.sample_rate / 1000)
        get_last_n_samples(state.buffer, sample_count)
    end
    
    {:reply, samples, state}
  end

  # Private Functions

  defp trim_buffer(buffer, total_samples, max_size) when total_samples <= max_size do
    {buffer, total_samples}
  end

  defp trim_buffer(buffer, total_samples, max_size) do
    samples_to_remove = total_samples - max_size
    trim_from_front(buffer, total_samples, samples_to_remove)
  end

  defp trim_from_front(buffer, total_samples, 0), do: {buffer, total_samples}
  
  defp trim_from_front(buffer, total_samples, samples_to_remove) do
    case :queue.out(buffer) do
      {{:value, chunk}, rest} ->
        chunk_size = length(chunk)
        if chunk_size <= samples_to_remove do
          # Remove entire chunk
          trim_from_front(rest, total_samples - chunk_size, samples_to_remove - chunk_size)
        else
          # Partial chunk removal
          trimmed_chunk = Enum.drop(chunk, samples_to_remove)
          updated_buffer = :queue.in_r(trimmed_chunk, rest)
          {updated_buffer, total_samples - samples_to_remove}
        end
        
      {:empty, _} ->
        {:queue.new(), 0}
    end
  end

  defp flatten_buffer(buffer) do
    :queue.to_list(buffer)
    |> List.flatten()
  end

  defp get_last_n_samples(buffer, n) do
    all_samples = flatten_buffer(buffer)
    Enum.take(all_samples, -n)
  end
end