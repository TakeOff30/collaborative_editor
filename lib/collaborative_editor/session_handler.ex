defmodule CollaborativeEditor.SessionHandler do
  use GenServer

  # client callbacks
  def start_link(opts) do
    GenServer.start_link(__MODULE__, %{}, opts)
  end

  def set_active_peer(peer_id, user_id) do
    GenServer.call(__MODULE__, {:set_active, peer_id, user_id})
  end

  def deactivate_peer(peer_id) do
    GenServer.call(__MODULE__, {:deactivate, peer_id})
  end

  def is_peer_active?(peer_id) do
    GenServer.call(__MODULE__, {:is_active, peer_id})
  end

  def get_user_by_peer(peer_id) do
    GenServer.call(__MODULE__, {:get_user, peer_id})
  end

  def reset_state() do
    GenServer.call(__MODULE__, :reset_state)
  end

  # server callbacks
  @impl true
  def init(args) do
    {:ok, args}
  end

  @impl true
  def handle_call({:set_active, peer_id, user_id}, _from, state) do
    new_state = Map.put(state, peer_id, user_id)
    {:reply, new_state, new_state}
  end

  @impl true
  def handle_call({:deactivate, peer_id}, _from, state) do
    new_state = Map.delete(state, peer_id)
    {:reply, new_state, new_state}
  end

  @impl true
  def handle_call({:is_active, peer_id}, _from, state) do
    user_id = Map.get(state, peer_id)

    if user_id == nil do
      {:reply, false, state}
    else
      {:reply, true, state}
    end
  end

  @impl true
  def handle_call({:get_user, peer_id}, _from, state) do
    {:reply, Map.get(state, peer_id), state}
  end

  @impl true
  def handle_call(:reset_state, _from, _state) do
    {:reply, :ok, %{}}
  end
end
