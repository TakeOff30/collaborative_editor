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

-   **Insertion & Deletion:** The map-based implementation is exponentially faster. To insert or delete an element, the RGA algorithm needs to find an element by its unique ID. With a map, this lookup is an `O(log N)` operation. With a list, the entire list would have to be scanned from the beginning, resulting in an `O(N)` operation. For a large document, this difference is critical for real-time performance.

-   **ToString (Reconstruction):** The complexity of reconstructing the document string is effectively linear (`O(N)`) in both cases. However, since `insert` and `delete` are the most frequent operations during active collaboration, optimizing them is the highest priority.

The map-based approach provides the best of both worlds: the logical sequence is maintained via `predecessor_id` links within the elements, while the physical storage in a map provides the fast random access required for efficient, conflict-free editing.

## Learn more

-   Official website: https://www.phoenixframework.org/
-   Guides: https://hexdocs.pm/phoenix/overview.html
-   Docs: https://hexdocs.pm/phoenix
-   Forum: https://elixirforum.com/c/phoenix-forum
-   Source: https://github.com/phoenixframework/phoenix
