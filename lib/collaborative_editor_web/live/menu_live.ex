defmodule CollaborativeEditorWeb.MenuLive do
  use CollaborativeEditorWeb, :live_view
  alias CollaborativeEditor.PeerRegistry

  @total_slots 5

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:taken_slots, fetch_active_peers())
      |> assign(:slots, 1..@total_slots)
    {:ok, socket}
  end

  defp fetch_active_peers() do
    PeerRegistry.get_active_peers(:menu)
    |> Map.keys()
    |> MapSet.new()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-8 space-y-4">
      <h1 class="text-2xl font-bold">Choose a Peer Slot</h1>
      <div class="space-y-2">
        <%= for slot <- @slots do %>
          <div class="flex justify-between items-center p-3 border rounded">
            <span class="font-mono">Peer Slot #<%= slot %></span>
            <%= if slot in @taken_slots do %>
              <span class="px-2 py-1 text-xs font-semibold bg-red-100 text-red-700 rounded">
                Taken
              </span>
            <% else %>
              <.link
                navigate={~p"/editor/#{slot}"}
                class="px-2 py-1 text-xs font-semibold bg-green-100 text-green-700 rounded hover:bg-green-200"
              >
                Join
              </.link>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
