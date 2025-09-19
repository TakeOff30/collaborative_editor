defmodule CollaborativeEditor.PeerRegistry do
    @moduledoc """
        Wrapper around Elixir Registry that keeps a list of active peers on the network.
        It allows a new peer to get a list of existing peers to connect to.
        It unregisters peers on termination or crash.
    """
    @registry_name __MODULE__

    @spec get_active_peers(any()) :: map()
    def get_active_peers(caller_id) do
        Registry.select(@registry_name, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
        |> Enum.filter(fn {id, _pid} -> id != caller_id end)
        |> Map.new()
    end
end
