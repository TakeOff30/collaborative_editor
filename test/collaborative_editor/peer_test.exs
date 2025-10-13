defmodule CollaborativeEditor.PeerTest do
  use ExUnit.Case, async: true
  alias CollaborativeEditor.Peer
  alias CollaborativeEditor.RGA

  setup do
    :ok
  end

  test "a peer can be initialized" do
    {:ok, peer} = Peer.start_link(1)
    state = Peer.get_state(peer)
    assert state.id == 1
    assert state.rga != nil
    assert state.vector_clock == %{1 => 0}
  end

  test "a new peer synchronizes its state with an existing peer" do
    {:ok, peer1} = Peer.start_link(1)
    Peer.insert(peer1, "a", nil)
    Peer.insert(peer1, "b", {1, 1})

    {:ok, peer2} = Peer.start_link(2)
    state1 = Peer.get_state(peer1)
    state2 = Peer.get_state(peer2)

    assert RGA.to_string(state2.rga) == RGA.to_string(state1.rga)
    assert state2.vector_clock == Map.put(state1.vector_clock, 2, 0)
  end

  test "a peer can insert and delete characters locally" do
    {:ok, peer} = Peer.start_link(1)
    Peer.insert(peer, "a", nil)
    state = Peer.get_state(peer)
    assert RGA.to_string(state.rga) == "a"

    Peer.insert(peer, "b", {1, 1})
    state = Peer.get_state(peer)
    assert RGA.to_string(state.rga) == "ab"

    Peer.delete(peer, {1, 1})
    state = Peer.get_state(peer)
    assert RGA.to_string(state.rga) == "b"
  end

  test "peers converge after concurrent insertions" do
    {:ok, peer1} = Peer.start_link(1)
    {:ok, peer2} = Peer.start_link(2)

    Peer.insert(peer1, "a", nil)
    :timer.sleep(100)
    Peer.insert(peer2, "b", nil)
    :timer.sleep(100)

    state1 = Peer.get_state(peer1)
    state2 = Peer.get_state(peer2)

    assert RGA.to_string(state1.rga) == RGA.to_string(state2.rga)
  end

  test "peers converge after concurrent deletions" do
    {:ok, peer1} = Peer.start_link(1)
    {:ok, peer2} = Peer.start_link(2)

    Peer.insert(peer1, "a", nil)
    Peer.insert(peer1, "b", {1, 1})
    :timer.sleep(100)

    state1 = Peer.get_state(peer1)
    state2 = Peer.get_state(peer2)
    assert RGA.to_string(state1.rga) == "ab"
    assert RGA.to_string(state2.rga) == "ab"

    Peer.delete(peer1, {1, 1})
    :timer.sleep(100)
    Peer.delete(peer2, {2, 1})
    :timer.sleep(100)

    state1 = Peer.get_state(peer1)
    state2 = Peer.get_state(peer2)

    assert RGA.to_string(state1.rga) == RGA.to_string(state2.rga)
  end

  test "peers converge after a mix of concurrent insertions and deletions" do
    {:ok, peer1} = Peer.start_link(1)
    {:ok, peer2} = Peer.start_link(2)

    Peer.insert(peer1, "a", nil)
    Peer.insert(peer1, "b", {1, 1})
    :timer.sleep(100)

    state1 = Peer.get_state(peer1)
    state2 = Peer.get_state(peer2)
    assert RGA.to_string(state1.rga) == "ab"
    assert RGA.to_string(state2.rga) == "ab"

    Peer.delete(peer1, {1, 1})
    :timer.sleep(100)
    Peer.insert(peer2, "c", {2, 1})
    :timer.sleep(100)

    state1 = Peer.get_state(peer1)
    state2 = Peer.get_state(peer2)

    assert RGA.to_string(state1.rga) == RGA.to_string(state2.rga)
  end

  test "a peer is removed from the peer map when it crashes" do
    {:ok, peer1} = Peer.start_link(1)
    {:ok, peer2} = Peer.start_link(2)

    state1 = Peer.get_state(peer1)
    assert Map.has_key?(state1.peer_map, 2)

    GenServer.stop(peer2)
    :timer.sleep(100)

    state1 = Peer.get_state(peer1)
    refute Map.has_key?(state1.peer_map, 2)
  end
end
