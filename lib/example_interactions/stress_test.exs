Application.ensure_all_started(:collaborative_editor)

num_peers = 3
num_rounds = 100

peers =
  for i <- 1..num_peers, into: [] do
    {:ok, peer} = CollaborativeEditor.Peer.start_link(i)
    peer
  end

Enum.each(1..num_rounds, fn i ->
  Enum.each(peers, fn peer ->
    state = CollaborativeEditor.Peer.get_state(peer)
    doc_list = CollaborativeEditor.RGA.to_list(state.rga)
    doc_length = Enum.count(doc_list)

    action =
      if doc_length == 0 do
        :insert
      else
        Enum.random([:insert, :delete])
      end

    case action do
      :insert ->
        # insert a random character at a random position
        predecessor_id =
          if doc_length == 0 do
            nil
          else
            pos = :rand.uniform(doc_length)
            Enum.at(doc_list, pos - 1).id
          end

        char_to_insert = ?a..?z |> Enum.random() |> to_string()

        CollaborativeEditor.Logger.log(
          "Round ##{i}: Peer #{state.id} inserting '#{char_to_insert}'"
        )

        CollaborativeEditor.Peer.insert(peer, char_to_insert, predecessor_id)

      :delete ->
        # delete a character from a random position
        element_to_delete = Enum.random(doc_list)

        CollaborativeEditor.Logger.log(
          "Round ##{i}: Peer #{state.id} deleting '#{element_to_delete.char}'"
        )

        CollaborativeEditor.Peer.delete(peer, element_to_delete.id)
    end
  end)
end)

Process.sleep(1000)

docs =
  Enum.map(peers, fn peer ->
    CollaborativeEditor.Peer.get_state(peer)
    |> then(fn state -> {state.id, CollaborativeEditor.RGA.to_string(state.rga)} end)
  end)

# Verify convergence.
first_doc = elem(Enum.at(docs, 0), 1)
all_converged? = Enum.all?(docs, fn {_peer_id, doc} -> doc == first_doc end)

if all_converged? do
  CollaborativeEditor.Logger.log("All peers have converged to the same state.")
  CollaborativeEditor.Logger.log("Final document:\n#{first_doc}")
else
  CollaborativeEditor.Logger.log("Peers have not converged.")
end

Application.stop(:collaborative_editor)
