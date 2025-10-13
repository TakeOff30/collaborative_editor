# example interaction between peers that reaches convergence
# output log file in lib/collaborative_editor/logger/peer_communication.log

Application.ensure_all_started(:collaborative_editor)


{:ok, peer1} = CollaborativeEditor.Peer.start_link(1)
{:ok, peer2} = CollaborativeEditor.Peer.start_link(2)

# peer 1 inserts subsequent chars
:ok = CollaborativeEditor.Peer.insert(peer1, "a", nil)
:ok = CollaborativeEditor.Peer.insert(peer1, "b", {1,1})
:ok = CollaborativeEditor.Peer.insert(peer1, "c", {2,1})
:ok = CollaborativeEditor.Peer.insert(peer1, "d", {3,1})
:ok = CollaborativeEditor.Peer.insert(peer1, "e", {4,1})
:ok = CollaborativeEditor.Peer.insert(peer1, "f", {5,1})

# peer 2 inserts subsequent chars starting from the middle of the
# streak of characters inserted by peer 1
:ok = CollaborativeEditor.Peer.insert(peer2, "g", {3,1})
:ok = CollaborativeEditor.Peer.insert(peer2, "h", {1,2})
:ok = CollaborativeEditor.Peer.insert(peer2, "f", {2,2})

# by how the recursive function to_list that reconstructs the RGA
# is structured, here the chars inserted by char 2 will be shifted
# and positioned at the end of the document.

# the reason why this is happening is because the function recuresevly
# rebuilds the list of predecessors and when it steps at the character
# "c" with id {2,1}, it retrieves its successors and orders them, obtaining
# [("d", {3,1}), ("g", {3,1})] because the logical clock of "d" > "g".
# At this point the function recurevely builds the successor of "d",
# concatenats them and later builds the list for "g".

# on the UX side this is kind of negative: if the peer 2 want to insert
# text at the half of the sentence of peer 1 it will need to delete the
# chars coming after its insertion and rewrite it

# this can be solved by adopting a more robust version of RGA


:timer.sleep(1000)

doc1 = CollaborativeEditor.Peer.get_state(peer1) |> then(fn state -> CollaborativeEditor.RGA.to_string(state.rga) end)
doc2 = CollaborativeEditor.Peer.get_state(peer2) |> then(fn state -> CollaborativeEditor.RGA.to_string(state.rga) end)

if doc1 == doc2 and doc2 == doc3 do
  CollaborativeEditor.Logger.log("All peers have converged to the same state.")
  CollaborativeEditor.Logger.log("Final document: #{doc1}")
else
  CollaborativeEditor.Logger.log("Peers have not converged.")
  CollaborativeEditor.Logger.log("Peer 1 document: #{doc1}")
  CollaborativeEditor.Logger.log("Peer 2 document: #{doc2}")
end

Application.stop(:collaborative_editor)
