# CollaborativeEditor

To start your Phoenix server:

-   Run `mix setup` to install and setup dependencies
-   Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## RGA Implementation and Complexity Analysis

The core of this collaborative editor is a Conflict-free Replicated Data Type (CRDT) called a Replicated Growable Array (RGA). The choice of the underlying data structure to implement the RGA is critical for performance.

### Data Structure Choice: Map vs. List

This project implements the RGA using an Elixir **Map** to store the document's elements. The map's keys are the unique element IDs (`{clock, peer_id}`), and the values are the `Element` structs themselves.

This approach was chosen over a simple List for performance reasons. While a list might seem more intuitive for a sequence of characters, its performance characteristics are not suitable for this use case.

### Complexity Comparison

Here is a comparison of the time complexities for the core RGA operations, where `N` is the number of elements in the document and `K` is the maximum number of concurrent edits at a single position (typically a very small constant).

| Operation     | Map-based RGA (This Project) | List-based RGA (Naive) |
| :------------ | :--------------------------- | :--------------------- |
| **Insertion** | **O(log N)**                 | **O(N)**               |
| **Deletion**  | **O(log N)**                 | **O(N)**               |
| **ToString**  | **O(N log K)**               | **O(N)**               |

### Analysis

-   **Insertion: `O(log N)`**
    The `insert` operation's efficiency comes from using an Elixir `Map` to store the RGA elements. Elixir maps are implemented as Hash Array Mapped Tries (HAMTs), which provide logarithmic time complexity for insertions. The core of the operation is `Map.put(rga.elements, id, new_element)`. This avoids scanning the entire data structure, making it highly scalable for large documents. A list-based approach would require an `O(N)` scan to find the predecessor, which is significantly slower.

-   **Deletion: `O(log N)`**
    Deletion is also an `O(log N)` operation. It consists of two main steps: finding the element by its ID with `Map.get`, and then updating its `deleted` flag with `Map.put`. Both `Map.get` and `Map.put` are `O(log N)` operations on a HAMT. The total complexity is therefore `O(log N) + O(log N)`, which simplifies to `O(log N)`. This "soft delete" (marking an element as a tombstone) is much faster than finding and removing an element from a list (`O(N)`).

-   **ToString (Reconstruction): `O(N log K)`**
    This complexity is a result of traversing all `N` elements while sorting any concurrent edits (`K`) at each position.
    1.  The `to_string` function first performs an `O(N)` pass to group all non-deleted elements by their predecessor.
    2.  The recursive `build_string` function is then called for each element. Inside this function, `Enum.sort_by` is used to order any concurrent insertions. The number of concurrent insertions at a single position is `K`.
    3.  The complexity of sorting these `K` elements is `O(K log K)`.
    4.  Since this sort happens for each of the `N` elements (in the worst case), the total complexity is `O(N * log K)`. In practice, `K` is usually a very small number (e.g., 2 or 3), so `log K` is nearly constant, making the operation behave very close to linear time (`O(N)`).

The map-based approach provides the best of both worlds: the logical sequence is maintained via `predecessor_id` links within the elements, while the physical storage in a map provides the fast random access required for efficient, conflict-free editing.

## Peer Discovery: The `PeerRegistry` Module

Peer discovery is handled by the `CollaborativeEditor.PeerRegistry` module, which acts as a lightweight, passive lookup service.

### Implementation: Elixir's `Registry`

This module is a thin wrapper around Elixir's built-in `Registry`. The `Registry` is a distributed, fault-tolerant key-value store designed for mapping names to process IDs (PIDs).

### Responsibilities

1.  **Initial Peer Discovery**: When a new `Peer` process joins a session, it queries the `PeerRegistry` exactly once to get a list of all other active peers.
2.  **Registration**: The new `Peer` then registers itself with the `PeerRegistry` using a unique, sortable ID.

### Decentralized Liveness Monitoring

The `PeerRegistry`'s role is intentionally limited to this initial "handshake." It **does not** actively monitor peers or broadcast messages. Instead, once peers have discovered each other:

-   Each `Peer` process directly monitors every other `Peer` process using `Process.monitor/1`.
-   If a peer crashes, the BEAM runtime sends a `:DOWN` message to all monitoring peers.
-   Each peer is then responsible for independently updating its own local list of active peers.

This decentralized approach avoids a single point of failure and leverages OTP's powerful fault-tolerance primitives, ensuring the system remains robust and scalable. The `Registry` automatically cleans up entries for crashed processes, guaranteeing that the initial discovery list is always accurate.

## The `Peer` Module: State, Concurrency, and Causal Order

The `CollaborativeEditor.Peer` module is the heart of the real-time collaboration logic. Each `Peer` is a `GenServer` process that represents a single user's session, managing its own document state and communicating with other peers.

### Core Responsibilities

-   **State Management**: Each peer holds its own copy of the RGA document, a vector clock for tracking causality, a list of connected peers, and a buffer for out-of-order operations.
-   **Operation Handling**: It processes both local user edits and remote operations from other peers.
-   **Communication**: It broadcasts local changes to all other peers and handles incoming messages.

### Peer Initialization and State Synchronization

When a new peer starts (via [`Peer.start_link/1`](lib/collaborative_editor/peer.ex)), its `init/1` function performs a critical sequence:

1.  **Discover Peers**: It calls [`PeerRegistry.get_active_peers/1`](lib/collaborative_editor/peer_registry.ex) to get a map of all other active peers.
2.  **Announce Itself**: It broadcasts a `{:new_peer, ...}` message to all discovered peers, so they can add it to their local `peer_map` and start monitoring it.
3.  **Synchronize State**:
    -   If no other peers exist, it initializes a new, empty document.
    -   If peers do exist, it performs a `GenServer.call` to the first available peer to fetch its entire state ([`rga`](lib/collaborative_editor/peer.ex) and [`vector_clock`](lib/collaborative_editor/peer.ex)). This instantly brings the new peer up-to-date with the current document.
4.  **Monitor Peers**: It calls `Process.monitor/1` on every other peer to receive `:DOWN` messages if one of them crashes.

### Causal Broadcast and Operation Buffering

To prevent conflicts and ensure all peers converge to the same state, the system must guarantee that operations are applied in a correct causal order. This is achieved through vector clocks and an operation buffer.

1.  **Broadcasting an Operation**: When a peer makes a local change ([`insert`](lib/collaborative_editor/peer.ex) or [`delete`](lib/collaborative_editor/peer.ex)), it increments its own clock in its vector clock and broadcasts the operation along with its new vector clock to all other peers.

2.  **Receiving an Operation**: When a peer receives a remote operation, it doesn't apply it immediately. Instead, it calls [`can_apply?/2`](lib/collaborative_editor/peer.ex), which checks two conditions:

    -   The operation's clock from the sender is exactly one greater than the last known clock for that sender.
    -   The sender's vector clock does not contain any knowledge that the receiving peer is missing.

3.  **Buffering**: If [`can_apply?`](lib/collaborative_editor/peer.ex) returns `false`, it means a causally preceding operation has not yet arrived. The incoming operation is added to the [`op_buffer`](lib/collaborative_editor/peer.ex).

4.  **Processing the Buffer**: After successfully applying any operation, the peer runs [`process_buffer/1`](lib/collaborative_editor/peer.ex). This function recursively iterates through the buffer, applying any operations that now meet the causal delivery criteria thanks to the updated vector clock. This ensures that buffered operations are eventually applied in the correct order.

### Communication Complexity: O(N)

The communication model used by the `Peer` module is a full-mesh broadcast. Every peer maintains a direct connection to every other peer in the session. This has direct implications for the communication complexity, where `N` is the total number of peers.

-   **Operation Broadcast**: When a peer generates a new operation (an insertion or deletion), it broadcasts the operation to all other `N-1` peers. This results in **O(N)** messages for a single edit.
-   **Peer Joining**: When a new peer joins, it announces its presence to all `N-1` existing peers, resulting in **O(N)** messages.
-   **Peer Leaving/Crashing**: When a peer disconnects, the underlying BEAM runtime sends a `:DOWN` message to all `N-1` peers that were monitoring it, again resulting in **O(N)** messages.

### Editor LiveView - Server communication

-   When visiting an editor page (e.g., `/editor/1`), the browser makes a standard HTTP request. The Phoenix server renders the initial HTML page and sends it back.
-   The browser then establishes a persistent **WebSocket** connection to the `EditorLive` LiveView on the server and defines `Hooks` that listen for events on the textarea [`Hooks.Editor`](assets/js/app.js). The insertions are parsed and sent to the server (peer process).
-   The Peer process applies the logic described above: broadcasts the modifications, applies them locally and sends an update via **PubSub** to its connected `EditorLive`.
