# example interaction between peers that reaches convergence
# output log file in lib/collaborative_editor/logger/peer_communication.log

Application.ensure_all_started(:collaborative_editor)


{:ok, peer1} = CollaborativeEditor.Peer.start_link(1)
{:ok, peer2} = CollaborativeEditor.Peer.start_link(2)
{:ok, peer3} = CollaborativeEditor.Peer.start_link(3)

:ok = CollaborativeEditor.Peer.insert(peer1, "a", nil)
:ok = CollaborativeEditor.Peer.insert(peer2, "b", {1,1})
:ok = CollaborativeEditor.Peer.insert(peer3, "c", {1,2})
:ok = CollaborativeEditor.Peer.delete(peer1, {1,1})

:timer.sleep(1000)

doc1 = CollaborativeEditor.Peer.get_state(peer1) |> then(&CollaborativeEditor.RGA.to_string(&1.rga))
doc2 = CollaborativeEditor.Peer.get_state(peer2) |> then(&CollaborativeEditor.RGA.to_string(&1.rga))
doc3 = CollaborativeEditor.Peer.get_state(peer3) |> then(&CollaborativeEditor.RGA.to_string(&1.rga))

if doc1 == doc2 and doc2 == doc3 do
  CollaborativeEditor.Logger.log("All peers have converged to the same state.")
  CollaborativeEditor.Logger.log("Final document: #{doc1}")
else
  CollaborativeEditor.Logger.log("Peers have not converged.")
  CollaborativeEditor.Logger.log("Peer 1 document: #{doc1}")
  CollaborativeEditor.Logger.log("Peer 2 document: #{doc2}")
  CollaborativeEditor.Logger.log("Peer 3 document: #{doc3}")
end

Application.stop(:collaborative_editor)
