defmodule VoxDialog.ModuleSystem do
  @moduledoc """
  Module system implementation following Grace Hopper's vision of interchangeable modules.
  Each module must implement a standard interface for input/output compatibility.
  """
  
  @doc """
  Behavior that all VoxDialog modules must implement.
  """
  @callback info() :: %{
    id: String.t(),
    name: String.t(),
    version: String.t(),
    interface: %{
      input: String.t(),
      output: String.t()
    }
  }
  
  @callback initialize(opts :: map()) :: {:ok, state :: any()} | {:error, reason :: any()}
  @callback process(input :: any(), state :: any()) :: {:ok, output :: any(), new_state :: any()} | {:error, reason :: any()}
  @callback shutdown(state :: any()) :: :ok
  
  @doc """
  Registry for available modules in the system.
  """
  def list_available_modules do
    [
      VoxDialog.Modules.STT,
      VoxDialog.Modules.TTS,
      VoxDialog.Modules.VoiceSession,
      VoxDialog.Modules.AudioLibrary
    ]
    |> Enum.map(& &1.info())
  end
  
  @doc """
  Check if two modules are compatible (output of one matches input of another).
  """
  def modules_compatible?(source_module, target_module) do
    source_output = source_module.info().interface.output
    target_input = target_module.info().interface.input
    
    types_compatible?(source_output, target_input)
  end
  
  defp types_compatible?(type1, type2) do
    # Handle wildcard matching
    cond do
      type1 == type2 -> true
      String.contains?(type1, "*") or String.contains?(type2, "*") ->
        wildcard_match?(type1, type2)
      true -> false
    end
  end
  
  defp wildcard_match?(pattern, type) do
    regex_pattern = pattern
    |> String.replace("*", ".*")
    |> Regex.compile!()
    
    Regex.match?(regex_pattern, type)
  end
end