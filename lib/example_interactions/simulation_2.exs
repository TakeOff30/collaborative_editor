Application.ensure_all_started(:collaborative_editor)

{:ok, peer1} = CollaborativeEditor.Peer.start_link(1)
{:ok, peer2} = CollaborativeEditor.Peer.start_link(2)
{:ok, peer3} = CollaborativeEditor.Peer.start_link(3)

#peers insert chars at the same position repeatedly
Enum.each(1..10, fn i ->
    CollaborativeEditor.Peer.insert(peer1, "a#{i}", nil)
    CollaborativeEditor.Peer.insert(peer2, "b#{i}", nil)
    CollaborativeEditor.Peer.insert(peer3, "c#{i}", nil)
end)

Enum.each(11..20, fn i ->
    CollaborativeEditor.Peer.insert(peer3, "c#{i}", nil)
    CollaborativeEditor.Peer.insert(peer1, "a#{i}", nil)
    CollaborativeEditor.Peer.insert(peer2, "b#{i}", nil)
end)

Enum.each(21..30, fn i ->
    CollaborativeEditor.Peer.insert(peer3, "c#{i}", nil)
    CollaborativeEditor.Peer.insert(peer2, "b#{i}", nil)
    CollaborativeEditor.Peer.insert(peer1, "a#{i}", nil)
end)


Process.sleep(1000)

doc1 = CollaborativeEditor.Peer.get_state(peer1) |> then(fn state -> CollaborativeEditor.RGA.to_string(state.rga) end)
doc2 = CollaborativeEditor.Peer.get_state(peer2) |> then(fn state -> CollaborativeEditor.RGA.to_string(state.rga) end)
doc3 = CollaborativeEditor.Peer.get_state(peer3) |> then(fn state -> CollaborativeEditor.RGA.to_string(state.rga) end)

if doc1 == doc2 and doc2 == doc3 do
  CollaborativeEditor.Logger.log("All peers have converged to the same state.")
  CollaborativeEditor.Logger.log("Final document:\n#{doc1}")
else
  CollaborativeEditor.Logger.log("Peers have not converged.")
  CollaborativeEditor.Logger.log("Peer 1 document: #{doc1}")
  CollaborativeEditor.Logger.log("Peer 2 document: #{doc2}")
  CollaborativeEditor.Logger.log("Peer 3 document: #{doc3}")
end

Application.stop(:collaborative_editor)
