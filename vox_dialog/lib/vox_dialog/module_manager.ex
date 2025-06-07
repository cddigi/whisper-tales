defmodule VoxDialog.ModuleManager do
  @moduledoc """
  Manages the lifecycle of loaded modules in the system.
  Handles loading, unloading, and communication between modules.
  """
  
  use GenServer
  require Logger
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def load_module(module_id, opts \\ %{}) do
    GenServer.call(__MODULE__, {:load_module, module_id, opts})
  end
  
  def unload_module(module_id) do
    GenServer.call(__MODULE__, {:unload_module, module_id})
  end
  
  def list_loaded_modules do
    GenServer.call(__MODULE__, :list_loaded_modules)
  end
  
  def module_status(module_id) do
    GenServer.call(__MODULE__, {:module_status, module_id})
  end
  
  def send_to_module(module_id, input) do
    GenServer.call(__MODULE__, {:send_to_module, module_id, input})
  end
  
  def pipe_modules(source_module_id, target_module_id) do
    GenServer.call(__MODULE__, {:pipe_modules, source_module_id, target_module_id})
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    state = %{
      loaded_modules: %{},
      module_states: %{},
      module_pipes: %{}
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:load_module, module_id, opts}, _from, state) do
    case get_module_implementation(module_id) do
      nil ->
        {:reply, {:error, :module_not_found}, state}
      
<<<<<<< ours
      module ->
        case module.initialize(opts) do
||||||| ancestor
      module ->
        # Add backend configuration for STT module
        enhanced_opts = case module_id do
          "stt" ->
            # Handle backend_type parameter
            backend_type = case Map.get(opts, :backend_type) do
              backend when is_binary(backend) -> String.to_atom(backend)
              backend when is_atom(backend) -> backend
              _ -> nil
            end
            
            if backend_type do
              Map.put(opts, :backend_type, backend_type)
            else
              opts
            end
          _ ->
            opts
        end
        
        case module.initialize(enhanced_opts) do
=======
      module_impl ->
        # Add backend configuration for STT module
        enhanced_opts = case module_id do
          "stt" ->
            # Handle backend_type parameter
            backend_type = case Map.get(opts, :backend_type) do
              backend when is_binary(backend) -> String.to_atom(backend)
              backend when is_atom(backend) -> backend
              _ -> nil
            end
            
            if backend_type do
              Map.put(opts, :backend_type, backend_type)
            else
              opts
            end
          _ ->
            opts
        end
        
        case apply(module_impl, :initialize, [enhanced_opts]) do
>>>>>>> theirs
          {:ok, module_state} ->
            Logger.info("Loaded module: #{module_id}")
            
            new_state = state
            |> put_in([:loaded_modules, module_id], module_impl)
            |> put_in([:module_states, module_id], module_state)
            
            # Broadcast module loaded event
            Phoenix.PubSub.broadcast(
              VoxDialog.PubSub,
              "module_status",
              {:module_loaded, module_id}
            )
            
            {:reply, :ok, new_state}
          
          {:error, reason} ->
            Logger.error("Failed to load module #{module_id}: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end
    end
  end
  
  @impl true
  def handle_call({:unload_module, module_id}, _from, state) do
    case Map.get(state.loaded_modules, module_id) do
      nil ->
        {:reply, {:error, :module_not_loaded}, state}
      
      module ->
        module_state = Map.get(state.module_states, module_id)
        :ok = module.shutdown(module_state)
        
        Logger.info("Unloaded module: #{module_id}")
        
        new_state = state
        |> update_in([:loaded_modules], &Map.delete(&1, module_id))
        |> update_in([:module_states], &Map.delete(&1, module_id))
        |> update_in([:module_pipes], &remove_module_pipes(&1, module_id))
        
        # Broadcast module unloaded event
        Phoenix.PubSub.broadcast(
          VoxDialog.PubSub,
          "module_status",
          {:module_unloaded, module_id}
        )
        
        {:reply, :ok, new_state}
    end
  end
  
  @impl true
  def handle_call(:list_loaded_modules, _from, state) do
    modules = Map.keys(state.loaded_modules)
    {:reply, modules, state}
  end
  
  @impl true
  def handle_call({:module_status, module_id}, _from, state) do
    status = if Map.has_key?(state.loaded_modules, module_id) do
      :loaded
    else
      :not_loaded
    end
    
    {:reply, status, state}
  end
  
  @impl true
  def handle_call({:send_to_module, module_id, input}, _from, state) do
    case Map.get(state.loaded_modules, module_id) do
      nil ->
        {:reply, {:error, :module_not_loaded}, state}
      
      module ->
        module_state = Map.get(state.module_states, module_id)
        
        case module.process(input, module_state) do
          {:ok, output, new_module_state} ->
            new_state = put_in(state, [:module_states, module_id], new_module_state)
            
            # Check if this module is piped to another
            case Map.get(state.module_pipes, module_id) do
              nil ->
                {:reply, {:ok, output}, new_state}
              
              target_module_id ->
                # Forward output to target module
                handle_call({:send_to_module, target_module_id, output}, self(), new_state)
            end
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end
  
  @impl true
  def handle_call({:pipe_modules, source_id, target_id}, _from, state) do
    # Verify both modules are loaded
    source_module = Map.get(state.loaded_modules, source_id)
    target_module = Map.get(state.loaded_modules, target_id)
    
    cond do
      source_module == nil ->
        {:reply, {:error, {:source_not_loaded, source_id}}, state}
      
      target_module == nil ->
        {:reply, {:error, {:target_not_loaded, target_id}}, state}
      
      not VoxDialog.ModuleSystem.modules_compatible?(source_module, target_module) ->
        {:reply, {:error, :incompatible_modules}, state}
      
      true ->
        new_state = put_in(state, [:module_pipes, source_id], target_id)
        Logger.info("Piped module #{source_id} to #{target_id}")
        {:reply, :ok, new_state}
    end
  end
  
  # Private functions
  
  defp get_module_implementation(module_id) do
    case module_id do
      "stt" -> VoxDialog.Modules.STT
      "tts" -> VoxDialog.Modules.TTS
      "voice_session" -> VoxDialog.Modules.VoiceSession
      "audio_library" -> VoxDialog.Modules.AudioLibrary
      _ -> nil
    end
  end
  
  defp remove_module_pipes(pipes, module_id) do
    pipes
    |> Enum.reject(fn {source, target} -> source == module_id or target == module_id end)
    |> Map.new()
  end
end