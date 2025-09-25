defmodule CollaborativeEditor.Peer do
  @moduledoc """
  Represents a peer in the collaborative editing system.
  Each peer maintains its own RGA state and can communicate with other peers
  to propagate changes.
  """
  use GenServer
  alias CollaborativeEditor.RGA
  alias CollaborativeEditor.PeerRegistry
  alias CollaborativeEditor.Logger

  defstruct id: nil, rga: nil, vector_clock: %{}, op_buffer: [], peer_map: %{}

  @type t :: %__MODULE__{
          id: integer(),
          rga: RGA.t(),
          vector_clock: vector_clock(),
          op_buffer: [any()],
          peer_map: %{any() => pid()}
        }
  @typep peer_id :: any()
  @typep op_id :: {integer, peer_id()}
  @typep insert_op :: {:insert, String.t(), op_id() | nil, op_id()}
  @typep delete_op :: {:delete, op_id()}
  @typep operation :: insert_op() | delete_op()
  @typep vector_clock :: %{peer_id() => integer()}
  @typep remote_op_tuple :: {peer_id(), operation(), vector_clock()}

  # client callbacks

  @spec start_link(integer()) :: GenServer.on_start()
  def start_link(id) do
    GenServer.start_link(__MODULE__, %{id: id},
      name: {:via, Registry, {CollaborativeEditor.PeerRegistry, id}}
    )
  end

  @spec insert(pid(), String.t(), op_id() | nil) :: :ok
  def insert(peer_pid, char, predecessor_id) do
    GenServer.cast(peer_pid, {:insert, char, predecessor_id})
  end

  @spec delete(pid(), op_id()) :: :ok
  def delete(peer_pid, id) do
    GenServer.cast(peer_pid, {:delete, id})
  end

  @spec get_state(pid()) :: t()
  def get_state(peer_pid) do
    GenServer.call(peer_pid, :get_state)
  end

  @spec id_at_position(pid(), integer()) :: op_id() | nil
  def id_at_position(peer_pid, position) do
    GenServer.call(peer_pid, {:id_at_position, position})
  end

  # server callbacks

  @impl GenServer
  @spec init(%{id: integer()}) :: {:ok, t()}
  def init(args) do
    peers = PeerRegistry.get_active_peers(args.id)
    Logger.log("Peer #{args.id} announces presence")

    # announce presence to other peers so they can start monitoring
    broadcast_to_peers(peers, {:new_peer, args.id, self()})

    initial_state = %__MODULE__{
      id: args.id,
      rga: RGA.new(),
      vector_clock: %{args.id => 0},
      op_buffer: [],
      peer_map: peers
    }

    # sync state asynchronously, avoids deadlocking during initialization
    # of more peers concurrently which end up awaiting for each other's
    # response to call.
    if map_size(peers) > 0 do
      send(self(), :sync_state)
    end

    # monitor the other peers to detect crashes
    Map.values(peers)
    |> Enum.each(fn pid ->
      Process.monitor(pid)
    end)

    {:ok, initial_state}
  end

  @impl GenServer
  @spec handle_call(:get_state, GenServer.from(), t()) :: {:reply, t(), t()}
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl GenServer
  def handle_call({:id_at_position, position}, _from, state) do
    element_id = RGA.id_at_position(state.rga, position)
    {:reply, element_id, state}
  end

  @impl GenServer
  @spec handle_cast({:insert, String.t(), op_id() | nil}, t()) :: {:noreply, t()}
  def handle_cast({:insert, char, predecessor_id}, state) do
    new_id = {state.vector_clock[state.id] + 1, state.id}
    updated_rga = RGA.insert(state.rga, char, predecessor_id, new_id)
    updated_vector_clock = Map.put(state.vector_clock, state.id, state.vector_clock[state.id] + 1)
    op_to_broadcast = {:insert, char, predecessor_id, new_id}
    Logger.log("#{state.id} inserts a character")

    broadcast_to_peers(
      state.peer_map,
      {:remote_operation, {state.id, op_to_broadcast, updated_vector_clock}}
    )

    new_state = %{state | rga: updated_rga, vector_clock: updated_vector_clock}

    # find the position in which the char has been ultimately inserted
    final_position = RGA.position_of_id(new_state.rga, new_id)
    broadcast_document_update(new_state, final_position)

    IO.puts(inspect(RGA.to_string(new_state.rga)))
    {:noreply, new_state}
  end

  @impl GenServer
  @spec handle_cast({:delete, op_id()}, t()) :: {:noreply, t()}
  def handle_cast({:delete, id}, state) do
    updated_rga = RGA.delete(state.rga, id)
    updated_vector_clock = Map.put(state.vector_clock, state.id, state.vector_clock[state.id] + 1)
    op_to_broadcast = {:delete, id}
    Logger.log("#{state.id} deletes a character")

    broadcast_to_peers(
      state.peer_map,
      {:remote_operation, {state.id, op_to_broadcast, updated_vector_clock}}
    )

    new_state = %{state | rga: updated_rga, vector_clock: updated_vector_clock}
    broadcast_document_update(new_state, nil)

    {:noreply, new_state}
  end

  @impl GenServer
  @spec handle_cast({:remote_operation, remote_op_tuple()}, t()) :: {:noreply, t()}
  def handle_cast({:remote_operation, {sender_id, _op, _sender_vc} = op_tuple}, state) do
    if can_apply?(op_tuple, state.vector_clock) do
      IO.puts(inspect(op_tuple))
      updated_state = apply_remote_operation(op_tuple, state)
      final_state = process_buffer(updated_state)
      {:noreply, final_state}
    else
      Logger.log("#{state.id} buffered an operation from #{sender_id}")
      updated_buffer = [op_tuple | state.op_buffer]
      {:noreply, %{state | op_buffer: updated_buffer}}
    end
  end

  @impl GenServer
  @spec handle_cast({:new_peer, peer_id(), pid()}, t()) :: {:noreply, t()}
  def handle_cast({:new_peer, new_peer_id, new_peer_pid}, state) do
    Process.monitor(new_peer_pid)
    updated_peers = Map.put(state.peer_map, new_peer_id, new_peer_pid)
    updated_vc = Map.put_new(state.vector_clock, new_peer_id, 0)
    {:noreply, %{state | peer_map: updated_peers, vector_clock: updated_vc}}
  end

  @doc """
  Handles a peer crash notification and removes it from the list of
  connected peers and from the vector clock.
  """
  @impl GenServer
  @spec handle_info({:DOWN, reference(), :process, pid(), any()}, t()) :: {:noreply, t()}
  def handle_info({:DOWN, _ref, :process, crashed_peer_pid, _reason}, state) do
    crashed_peer_id = Enum.find(state.peer_map, fn {_id, pid} -> pid == crashed_peer_pid end)

    case crashed_peer_id do
      nil ->
        {:noreply, state}

      {peer_id_to_remove, _pid} ->
        Logger.log(
          "#{peer_id_to_remove} has crashed or disconnected. Removing from #{state.id} state"
        )

        updated_pids = Map.delete(state.peer_map, peer_id_to_remove)
        {:noreply, %{state | peer_map: updated_pids}}
    end
  end

  @impl GenServer
  def handle_info(:sync_state, state) do
    IO.puts(
      "Found existing peers: #{inspect(Map.keys(state.peer_map))}. Contacting one to sync state."
    )

    synced_state =
      state.peer_map
      |> Map.values()
      |> Enum.at(0)
      |> GenServer.call(:get_state)

    new_state = %{
      state
      | rga: synced_state.rga,
        vector_clock: Map.put(synced_state.vector_clock, state.id, 0)
    }

    {:noreply, new_state}
  end

  @spec process_buffer(t()) :: t()
  defp process_buffer(state) do
    {ready_to_apply, buffered} =
      Enum.split_with(state.op_buffer, fn operation ->
        can_apply?(operation, state.vector_clock)
      end)

    if Enum.empty?(ready_to_apply) do
      state
    else
      new_state =
        Enum.reduce(
          ready_to_apply,
          %{state | op_buffer: buffered},
          fn to_apply, acc_state -> apply_remote_operation(to_apply, acc_state) end
        )

      process_buffer(new_state)
    end
  end

  @spec can_apply?(remote_op_tuple(), vector_clock()) :: boolean()
  defp can_apply?({sender_id, _op, sender_vc}, local_vc) do
    is_adq_sender_clock =
      sender_vc[sender_id] == (local_vc[sender_id] || 0) + 1

    clocks_to_check = Map.delete(sender_vc, sender_id)

    respects_causality =
      Enum.all?(clocks_to_check, fn {peer_id, peer_clock} ->
        peer_clock <= (local_vc[peer_id] || 0)
      end)

    is_adq_sender_clock and respects_causality
  end

  @spec apply_remote_operation(remote_op_tuple(), t()) :: t()
  defp apply_remote_operation({_sender_id, op, sender_vc}, state) do
    # based on the type of operation, apply it, update rga and compute new vc
    {updated_rga, final_position} =
      case op do
        {:insert, char, predecessor_id, elem_id} ->
          rga = RGA.insert(state.rga, char, predecessor_id, elem_id)
          pos = RGA.position_of_id(rga, elem_id)
          {rga, pos}

        {:delete, elem_id} ->
          {RGA.delete(state.rga, elem_id), nil}

        _ ->
          {state.rga, nil}
      end

    updated_vc =
      Map.merge(state.vector_clock, sender_vc, fn _k, v1, v2 -> max(v1, v2) end)

    new_state = %{state | vector_clock: updated_vc, rga: updated_rga}
    broadcast_document_update(new_state, final_position)
    new_state
  end

  defp broadcast_to_peers(peers, message) do
    sender_id =
      case message do
        {:new_peer, id, _} -> id
        {:remote_operation, {id, _, _}} -> id
      end

    Logger.log("#{sender_id} starts broadcasting")

    Map.values(peers)
    |> Enum.each(fn peer_pid ->
      Logger.log("#{sender_id} sends broadcast message to #{inspect(peer_pid)}")
      GenServer.cast(peer_pid, message)
    end)

    :ok
  end

  defp broadcast_document_update(state, cursor_pos) do
    new_document_string = RGA.to_string(state.rga)

    Phoenix.PubSub.broadcast(
      CollaborativeEditor.PubSub,
      "doc_update#{state.id}",
      {:doc_update, new_document_string, cursor_pos}
    )
  end
end
