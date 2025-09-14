defmodule CollaborativeEditor.Peer do
  @moduledoc """
  Represents a peer in the collaborative editing system.
  Each peer maintains its own RGA state and can communicate with other peers
  to propagate changes.
  """
  use GenServer
  alias CollaborativeEditor.RGA
  alias CollaborativeEditor.RGA.Element
  alias CollaborativeEditor.PeerRegistry

  defstruct :id, :rga, vector_clock: %{}, op_buffer: [], peer_map: %{}

  @type t :: %__MODULE__{
    id: integer(),
    rga: RGA.t(),
    vector_clock: %{any() => integer()},
    op_buffer: [any()],
    peer_map: %{any() => pid()}
  }

  #client callbacks

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(id) do
    GenServer.start_link(__MODULE__, %{id: id})
  end

  @spec insert(pid(), String.t(), {integer, any()} | nil) :: :ok
  def insert(peer_pid, char, predecessor_id) do
    GenServer.cast(peer_pid, {:insert, char, predecessor_id})
  end

  @spec delete(pid(), {integer, any()}) :: :ok
  def delete(peer_pid, id) do
    GenServer.cast(peer_pid, {:delete, id})
  end

  @spec get_state(pid()) :: t()
  def get_state(peer_pid) do
    GenServer.call(peer_pid, :get_state)
  end

  #server callbacks

  @impl GenServer
  def init(args) do

    peers = PeerRegistry.get_active_peers(args.id)

    broadcast_to_peers(peers, {:new_peer, args.id, self()})

    PeerRegistry.register_peer(args.id, self())

    peer_state =
      case peers do
        map_size(peers) == 0 ->
          IO.puts("No other peers found. Initializing new document.")
          %__MODULE__{
            id: args.id,
            rga: RGA.new(),
            vector_clock: %{args.id => 0},
            op_buffer: [],
            peer_map: %{}
          }
        _ ->
          IO.puts("Found existing peers: #{inspect(Map.keys(peers))}. Contacting one to sync state.")
          updated_state =
            peers
            |> Map.values()
            |> Enum.at(0)
            |> GenServer.call(:get_state)
          %__MODULE__{
            id: args.id,
            rga: updated_state.rga,
            vector_clock: Map.put(updated_state.vector_clock, args.id, 0),
            op_buffer: [],
            peer_map: peers
          }
      end

    # monitor the other peers to detect crashes
    Map.values(peer_state.peer_map)
    |> Enum.each(fn pid ->
      Process.monitor(pid)
    end)

    {:ok, peer_state}
  end


  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end


  @doc """
  Performs an insertion operation:
  - Updates the local RGA state.
  - Updates the local vector clock.
  - Broadcasts the insertion operation to all connected peers.
  """
  @impl GenServer
  def handle_cast({:insert, char, predecessor_id}, state) do
    updated_rga = RGA.insert(state.rga, char, predecessor_id, %Element{id: {state.vector_clock[state.id] + 1, state.id}})
    updated_vector_clock = Map.put(state.vector_clock, state.id, state.vector_clock[state.id] + 1)
    op_to_broadcast = {:insert, char, predecessor_id, {updated_vector_clock[state.id], state.id}}
    broadcast_to_peers(state.peer_map, {:remote_operation, {state.id, op_to_broadcast, updated_vector_clock}})


    {:noreply, %{state | rga: updated_rga, vector_clock: updated_vector_clock}}
  end

  @doc """
  Performs a deletion operation:
  - Updates the local RGA state.
  - Updates the local vector clock.
  - Broadcasts the deletion operation to all connected peers.
  """
  @impl GenServer
  def handle_cast({:delete, id}, state) do
    updated_rga = RGA.delete(state.rga, id)
    updated_vector_clock = Map.put(state.vector_clock, state.id, state.vector_clock[state.id] + 1)
    op_to_broadcast = {:delete, id}
    broadcast_to_peers(state.peer_map, {:remote_operation, {state.id, op_to_broadcast, updated_vector_clock}})

    {:noreply, %{state | rga: updated_rga, vector_clock: updated_vector_clock}}
  end

  @doc """
  Handles a remote operation received from another peer:
  - Applies the operation to the local RGA state.
  - Merges the sender's vector clock with the local vector clock.
  """
  @impl GenServer
  def handle_cast({:remote_operation, {sender_id, op, sender_vc}}, state) do
    case op do
      {:insert, char, predecessor_id, id} ->
        updated_rga = RGA.insert(state.rga, char, predecessor_id, id)
        updated_vector_clock = Map.merge(state.vector_clock, sender_vc, fn _k, v1, v2 -> max(v1, v2) end)
        {:noreply, %{state | rga: updated_rga, vector_clock: updated_vector_clock}}

      {:delete, id} ->
        updated_rga = RGA.delete(state.rga, id)
        updated_vector_clock = Map.merge(state.vector_clock, sender_vc, fn _k, v1, v2 -> max(v1, v2) end)
        {:noreply, %{state | rga: updated_rga, vector_clock: updated_vector_clock}}

      _ ->
        IO.puts("Unknown operation received: #{inspect(op)}")
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast({:new_peer, new_peer_id, new_peer_pid}, state) do
    Process.monitor(new_peer_pid)
    updated_peers = Map.put(state.peer_map, new_peer_id, new_peer_pid)
    updated_vc = Map.put(state.vector_clock, new_peer_id, 0)
    {:noreply, %{state | peer_map: updated_peers, vector_clock: updated_vc}}
  end

  @doc """
  Handles a peer crash notification and removes it from the list of
  connected peers and from the vector clock.
  """
  @impl GenServer
  def handle_info({:DOWN, _ref, _process, crashed_peer_pid, _reason}, state) do
    crashed_peer_id = Enum.find(state.peer_map, fn {_id, pid} -> pid == crashed_peer_pid end)

    case crashed_peer_id do
      nil ->
        {:noreply, state}
      {peer_id_to_remove, _pid} ->
        IO.puts("Peer #{peer_id_to_remove} has crashed or disconnected.")
        updated_pids = Map.delete(state.peer_map, peer_id_to_remove)
        {:noreply, %{state | peer_map: updated_pids, vector_clock: updated_vc}}
    end
  end

  @doc """
  Broadcasts a message to all connected peers.
  """
  @spec broadcast_to_peers(%{any() => pid()}, message) :: :ok
  defp broadcast_to_peers(peers, message) do
    Map.values(peers)
    |> Enum.each(fn peer_pid ->
      GenServer.cast(peer_pid, message)
    end)

    :ok
  end
end
