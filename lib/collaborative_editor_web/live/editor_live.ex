defmodule CollaborativeEditorWeb.EditorLive do
  alias CollaborativeEditor.PeerRegistry
  use CollaborativeEditorWeb, :live_view
  alias CollaborativeEditor.Peer
  alias CollaborativeEditor.RGA
  alias CollaborativeEditor.SessionHandler

  @impl true
  def mount(%{"peer_id" => peer_id}, session, socket) do
    peer_id = String.to_integer(peer_id)
    user_id = session["user_id"]
    active_user_for_peer = SessionHandler.get_user_by_peer(peer_id)

    # the logic here below allows one single user to be active on a peer slot

    # any user that tries to access the editor liveview
    # while it is occupied gets redirected to main menu
    cond do
      active_user_for_peer != nil and active_user_for_peer != user_id ->
        {:ok,
         socket
         |> assign(peer_id: peer_id)
         |> put_flash(:error, "Peer slot ##{peer_id} is already taken.")
         |> redirect(to: ~p"/")}

      true ->
        Phoenix.PubSub.subscribe(CollaborativeEditor.PubSub, "doc_update#{peer_id}")
        Phoenix.PubSub.subscribe(CollaborativeEditor.PubSub, "network_activity")
        Phoenix.PubSub.subscribe(CollaborativeEditor.PubSub, "peers")

        if connected?(socket),
          do: Phoenix.PubSub.subscribe(CollaborativeEditor.PubSub, "doc_update#{peer_id}")

        case Peer.start_link(peer_id) do
          {:ok, peer_pid} ->
            SessionHandler.set_active_peer(peer_id, user_id)
            Phoenix.PubSub.broadcast(CollaborativeEditor.PubSub, "peers", {:peer_update})
            document = RGA.to_string(Peer.get_state(peer_pid).rga)

            peers =
              PeerRegistry.get_all_active_peers()
              |> Map.keys()
              |> Enum.sort()

            {:ok,
             assign(socket,
               peer_id: peer_id,
               peer_pid: peer_pid,
               document: document,
               user_id: user_id,
               peers: peers
             )}

          {:error, {:already_started, peer_pid}} ->
            document = RGA.to_string(Peer.get_state(peer_pid).rga)
            peers = PeerRegistry.get_all_active_peers() |> Map.keys() |> Enum.sort()

            {:ok,
             assign(socket,
               peer_id: peer_id,
               peer_pid: peer_pid,
               document: document,
               user_id: user_id,
               peers: peers
             )}
        end
    end
  end

  @impl true
  def terminate(_reason, socket) do
    SessionHandler.deactivate_peer(socket.assigns.peer_id)
    GenServer.stop(socket.assigns.peer_pid)
    Phoenix.PubSub.broadcast(CollaborativeEditor.PubSub, "peers", {:peer_update})
    :ok
  end

  @impl true
  def handle_event("text_operation", %{"type" => "insert", "at" => at, "char" => char}, socket) do
    peer_pid = socket.assigns.peer_pid
    # The `at` position is the cursor position *after* the insert.
    # The predecessor is the character at the position *before* the insert.
    predecessor_id = Peer.id_at_position(peer_pid, at - 1)
    Peer.insert(peer_pid, char, predecessor_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("text_operation", %{"type" => "delete", "at" => at}, socket) do
    peer_pid = socket.assigns.peer_pid
    # The `at` position is the cursor position where the deletion happened.
    # We need to delete the character that was at that position.
    id_to_delete = Peer.id_at_position(peer_pid, at)
    if id_to_delete, do: Peer.delete(peer_pid, id_to_delete)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:peer_update}, socket) do
    peers =
      PeerRegistry.get_all_active_peers()
      |> Map.keys()
      |> Enum.sort()

    {:noreply, assign(socket, :peers, peers)}
  end

  @impl true
  def handle_info({:message, data}, socket) do
    {:noreply, push_event(socket, "new_message", data)}
  end

  @impl true
  def handle_info({:doc_update, new_document, cursor_pos}, socket) do
    {:noreply,
     push_event(socket, "doc_update", %{document: new_document, cursor_pos: cursor_pos})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-row w-full h-[calc(100vh-4rem)] bg-base-200 p-8 gap-8">
        <div class="w-1/2 h-full flex flex-col bg-base-100 rounded-box shadow-xl p-6">
          <div class="flex justify-between items-center mb-4 flex-shrink-0">
            <h1 class="text-3xl font-bold">Live Editor (Peer #<%= @peer_id %>)</h1>
            <.link href={~p"/"} class="btn btn-ghost">
              &larr; Back to Menu
            </.link>
          </div>
          <div class="flex-grow h-full">
            <textarea
              id={"editor-#{@peer_id}"}
              class="w-full h-full p-4 border-transparent rounded-md bg-base-100 font-mono focus:outline-none focus:ring-2 focus:ring-primary resize-none"
              phx-hook="Editor"
              data-document={@document}
              phx-update="ignore"
            >
            </textarea>
          </div>
        </div>

        <div class="w-1/2 h-full flex flex-col bg-base-100 rounded-box shadow-xl p-6 gap-6">
          <div class="flex-shrink-0">
            <h2 class="text-2xl font-bold mb-4">Network Visualization</h2>
            <div
              id="graph-visualization"
              class="w-full h-80 border border-base-300 rounded-md"
              phx-hook="NetworkVisualization"
              data-peers={Jason.encode!(@peers)}
              phx-update="ignore"
            >
            </div>
          </div>

          <div class="flex-grow flex flex-col min-h-0">
            <h2 class="text-2xl font-bold mb-4">Operation Log</h2>
            <div
              id="operation-logger"
              class="w-full h-full bg-base-200 rounded p-4 overflow-y-auto font-mono text-sm"
              phx-hook="OperationLogger"
              phx-update="ignore"
            >
              <p class="text-base-content/70">Waiting for network activity...</p>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
