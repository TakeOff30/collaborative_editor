defmodule CollaborativeEditorWeb.MenuLive do
  use CollaborativeEditorWeb, :live_view
  alias CollaborativeEditor.PeerRegistry

  @total_slots 5

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(CollaborativeEditor.PubSub, "peers")

    socket =
      socket
      |> assign(:taken_slots, fetch_active_peers())
      |> assign(:slots, 1..@total_slots)
    {:ok, socket}
  end

  @impl true
  def handle_info({:peer_update}, socket) do
    {:noreply, assign(socket, :taken_slots, fetch_active_peers())}
  end

  defp fetch_active_peers() do
    PeerRegistry.get_active_peers(:menu)
    |> Map.keys()
    |> MapSet.new()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-col justify-center items-center min-h-screen bg-base-200">
        <div class="w-full max-w-md p-8 space-y-4 bg-base-100 rounded-box shadow-xl">
          <h1 class="text-2xl font-bold text-center">Choose a Peer Slot</h1>
          <div class="space-y-2">
            <%= for slot <- @slots do %>
              <div class="flex justify-between items-center p-3 border rounded-lg">
                <span class="font-mono text-lg">Peer Slot #<%= slot %></span>
                <%= if slot in @taken_slots do %>
                  <span class="px-3 py-1 text-sm font-semibold bg-error text-error-content rounded-full">
                    Taken
                  </span>
                <% else %>
                  <.link
                    navigate={~p"/editor/#{slot}"}
                    class="btn btn-sm btn-primary"
                  >
                    Join
                  </.link>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
