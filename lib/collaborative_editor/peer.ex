defmodule CollaborativeEditor.Peer do
  @moduledoc """
  Represents a peer in the collaborative editing system.
  Each peer maintains its own RGA state and can communicate with other peers
  to propagate changes.
  """
  use GenServer
  alias CollaborativeEditor.RGA
  alias CollaborativeEditor.RGA.Element

  defstruct :id, :rga, vector_clock: %{}, op_buffer: [], peers_pids: []

  @type t :: %__MODULE__{
    id: any(),
    rga: RGA.t(),
    vector_clock: %{any() => integer()},
    op_buffer: [any()],
    peers_pids: [any()]
  }

  #client callbacks

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
  def init(_args) do
    # make request to Registry to get id and list of other peers
      # if no other peers exist, initialize empty doc and vector clock
      # if other peers exist contact another peer to get current doc and vector clock



    {:ok, %{rga: RGA.new(), vector_clock: %{}, op_buffer: [], peers: []}}
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
    broadcast_to_peers(state.peers_pids, {:remote_operation, {state.id, op_to_broadcast, updated_vector_clock}})


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
    broadcast_to_peers(state.peers_pids, {:remote_operation, {state.id, op_to_broadcast, updated_vector_clock}})

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

  @doc """
  Handles a peer crash notification and removes it from the list of
  connected peers and from the vector clock.
  """
  @impl GenServer
  def handle_call({:peer_crash, crashed_peer_pid}, _from, state) do
    updated_pids = List.delete(state.peers_pids, crashed_peer_pid)
    updated_vc = Map.delete(state.vector_clock, crashed_peer_pid)
    {:reply, :ok, %{state | peers_pids: updated_pids, vector_clock: updated_vc}}
  end

  @spec broadcast_to_peers([pid()], message) :: :ok
  defp broadcast_to_peers(peers_pids, message) do
    Enum.each(peers_pids, fn peer_pid ->
      GenServer.cast(peer_pid, message)
    end)
  end
end
