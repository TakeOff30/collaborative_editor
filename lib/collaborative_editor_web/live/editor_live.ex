defmodule CollaborativeEditorWeb.EditorLive do
  use CollaborativeEditorWeb, :live_view
  alias CollaborativeEditor.Peer
  alias CollaborativeEditor.RGA

  @impl true
  def mount(%{"peer_id" => peer_id}, _session, socket) do
    peer_id = String.to_integer(peer_id)
    case Peer.start_link(peer_id) do
      {:ok, peer_pid} ->
        if connected?(socket),
          do: Phoenix.PubSub.subscribe(CollaborativeEditor.PubSub, "doc_update#{peer_id}")

        Phoenix.PubSub.broadcast(CollaborativeEditor.PubSub, "peers", {:peer_update})
        peer_state = Peer.get_state(peer_pid)
        document = RGA.to_string(peer_state.rga)

        socket =
          assign(socket,
            peer_id: peer_id,
            peer_pid: peer_pid,
            document: document
          )

        {:ok, socket}
      {:error, {:already_started, _pid}} ->
        IO.puts("Already taken")
        {:ok,
          socket
          |> put_flash(:error, "Peer slot ##{peer_id} is already taken.")
          |> redirect(to: ~p"/")
        }
    end
  end

  @impl true
  def terminate(_reason, socket) do
    GenServer.stop(socket.assigns.peer_pid)
    Phoenix.PubSub.broadcast(CollaborativeEditor.PubSub, "peers", {:peer_update})
    :ok
  end

  @impl true
  def handle_event() do

  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-col items-center w-full min-h-screen bg-base-200">
        <div class="w-full max-w-4xl p-8">
          <div class="flex justify-between items-center mb-6">
            <h1 class="text-3xl font-bold">Live Editor (Peer #<%= @peer_id %>)</h1>
            <.link href={~p"/"} class="btn btn-ghost">
              &larr; Back to Menu
            </.link>
          </div>
          <div class="bg-base-100 rounded-box shadow-xl">
            <textarea
              id={"editor-#{@peer_id}"}
              class="w-full h-96 p-4 border-transparent rounded-md bg-base-100 font-mono focus:outline-none focus:ring-2 focus:ring-primary"
              phx-change="change"
              phx-target={@peer_id}
            ><%= @document %></textarea>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
