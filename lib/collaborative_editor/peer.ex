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


  #client callbacks

  @spec start_link(integer()) :: GenServer.on_start()
  def start_link(id) do
    GenServer.start_link(__MODULE__, %{id: id})
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

  #server callbacks

  @impl GenServer
  @spec init(%{id: integer()}) :: {:ok, t()}
  def init(args) do

    peers = PeerRegistry.get_active_peers(args.id)
    Logger.log("Peer #{args.id} announces presence")
    broadcast_to_peers(peers, {:new_peer, args.id, self()})

    PeerRegistry.register_peer(args.id, self())

    peer_state =
      if map_size(peers) == 0 do
        IO.puts("No other peers found. Initializing new document.")
        %__MODULE__{
          id: args.id,
          rga: RGA.new(),
          vector_clock: %{args.id => 0},
          op_buffer: [],
          peer_map: %{}
        }
      else
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
  @spec handle_call(:get_state, GenServer.from(), t()) :: {:reply, t(), t()}
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl GenServer
  @spec handle_cast({:insert, String.t(), op_id() | nil}, t()) :: {:noreply, t()}
  def handle_cast({:insert, char, predecessor_id}, state) do
    updated_rga = RGA.insert(state.rga, char, predecessor_id, {state.vector_clock[state.id] + 1, state.id})
    updated_vector_clock = Map.put(state.vector_clock, state.id, state.vector_clock[state.id] + 1)
    op_to_broadcast = {:insert, char, predecessor_id, {updated_vector_clock[state.id], state.id}}
    Logger.log("#{state.id} inserts a character")
    broadcast_to_peers(state.peer_map, {:remote_operation, {state.id, op_to_broadcast, updated_vector_clock}})

    {:noreply, %{state | rga: updated_rga, vector_clock: updated_vector_clock}}
  end

  @impl GenServer
  @spec handle_cast({:delete, op_id()}, t()) :: {:noreply, t()}
  def handle_cast({:delete, id}, state) do
    updated_rga = RGA.delete(state.rga, id)
    updated_vector_clock = Map.put(state.vector_clock, state.id, state.vector_clock[state.id] + 1)
    op_to_broadcast = {:delete, id}
    Logger.log("#{state.id} deletes a character")
    broadcast_to_peers(state.peer_map, {:remote_operation, {state.id, op_to_broadcast, updated_vector_clock}})

    {:noreply, %{state | rga: updated_rga, vector_clock: updated_vector_clock}}
  end

  @impl GenServer
  @spec handle_cast({:remote_operation, remote_op_tuple()}, t()) :: {:noreply, t()}
  def handle_cast({:remote_operation, {sender_id, _op, _sender_vc} = op_tuple}, state) do

    if can_apply?(op_tuple, state.vector_clock) do
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
          fn to_apply, acc_state -> apply_remote_operation(to_apply, acc_state) end)
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
    updated_rga =
      case op do
        {:insert, char, predecessor_id, elem_id} ->
          RGA.insert(state.rga, char, predecessor_id, elem_id)
        {:delete, elem_id} ->
          RGA.delete(state.rga, elem_id)
        _ -> state.rga
      end
    updated_vc =
      Map.merge(state.vector_clock, sender_vc, fn _k, v1, v2 -> max(v1, v2) end)

    %{state | vector_clock: updated_vc, rga: updated_rga}
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
        Logger.log("#{peer_id_to_remove} has crashed or disconnected. Removing from #{state.id} state")
        updated_pids = Map.delete(state.peer_map, peer_id_to_remove)
        {:noreply, %{state | peer_map: updated_pids}}
    end
  end

  defp broadcast_to_peers(peers, {_, sender_id, _} = message) do
    Logger.log("#{sender_id} starts broadcasting")
    Map.values(peers)
    |> Enum.each(fn peer_pid ->
      Logger.log("#{sender_id} sends broadcast message to #{inspect(peer_pid)}")
      GenServer.cast(peer_pid, message)
    end)

    :ok
  end

  defp broadcast_to_peers(peers, {_, {sender_id, _, _}} = message) do
    Logger.log("#{sender_id} starts broadcasting")
    Map.values(peers)
    |> Enum.each(fn peer_pid ->
      Logger.log("#{sender_id} sends broadcast message to #{inspect(peer_pid)}")
      GenServer.cast(peer_pid, message)
    end)

    :ok
  end
end
