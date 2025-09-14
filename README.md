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
