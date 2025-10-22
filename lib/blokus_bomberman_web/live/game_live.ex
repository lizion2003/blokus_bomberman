defmodule BlokusBombermanWeb.GameLive do
  use BlokusBombermanWeb, :live_view

  alias BlokusBomberman.{Game, Board}

  @move_interval 70  # milliseconds between moves when key is held

  @impl true
  def mount(_params, _session, socket) do
    game = Game.new()

    if connected?(socket) do
      schedule_tick()
    end

    {:ok, assign(socket,
      game: game,
      message: "Navigate the perimeter! Player 1: W/S | Player 2: Up/Down arrows",
      keys_pressed: MapSet.new()
    )}
  end

  @impl true
  def handle_event("keydown", %{"key" => key}, socket) do
    keys_pressed = MapSet.put(socket.assigns.keys_pressed, key)
    {:noreply, assign(socket, keys_pressed: keys_pressed)}
  end

  def handle_event("keyup", %{"key" => key}, socket) do
    keys_pressed = MapSet.delete(socket.assigns.keys_pressed, key)
    {:noreply, assign(socket, keys_pressed: keys_pressed)}
  end

  @impl true
  def handle_info(:tick, socket) do
    game = socket.assigns.game
    keys = socket.assigns.keys_pressed

    # Process both players' movements simultaneously
    new_game = game
      |> maybe_move_player(1, keys, ["w", "W"], ["s", "S"])
      |> maybe_move_player(2, keys, ["ArrowUp"], ["ArrowDown"])

    schedule_tick()
    {:noreply, assign(socket, game: new_game)}
  end

  defp maybe_move_player(game, player_id, keys, up_keys, down_keys) do
    cond do
      Enum.any?(up_keys, &MapSet.member?(keys, &1)) ->
        Game.move_player(game, player_id, :up)
      Enum.any?(down_keys, &MapSet.member?(keys, &1)) ->
        Game.move_player(game, player_id, :down)
      true ->
        game
    end
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @move_interval)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center p-4 bg-gray-900 min-h-screen" phx-window-keydown="keydown" phx-window-keyup="keyup">
      <h1 class="text-4xl font-bold mb-4 text-white">Blokus Bomberman</h1>
      <p class="text-lg mb-6 text-gray-300"><%= @message %></p>

      <div class="flex gap-8 mb-6">
        <div class="px-4 py-2 rounded bg-blue-600 text-white font-bold">
          Player 1 (Blue): W / S
        </div>
        <div class="px-4 py-2 rounded bg-red-600 text-white font-bold">
          Player 2 (Red): ↑ / ↓
        </div>
      </div>

      <!-- Game Board -->
      <div class="border-4 border-gray-700 bg-gray-800 shadow-2xl">
        <div class="grid gap-0" style={"grid-template-columns: repeat(#{Board.size()}, 2rem);"}>
          <%= for y <- 0..(Board.size() - 1) do %>
            <%= for x <- 0..(Board.size() - 1) do %>
              <%= render_cell(assigns, {x, y}) %>
            <% end %>
          <% end %>
        </div>
      </div>

      <div class="mt-6 text-gray-400 text-sm">
        <p>💡 Use W/S or ↑/↓ to navigate clockwise/counter-clockwise around the perimeter</p>
        <p>Avatars automatically wrap around all four edges - don't collide!</p>
      </div>
    </div>
    """
  end

  defp render_cell(assigns, {x, y}) do
    p1_pos = assigns.game.player1.position
    p2_pos = assigns.game.player2.position
    on_edge = Board.on_edge?({x, y})

    assigns = assigns
      |> assign(:x, x)
      |> assign(:y, y)
      |> assign(:is_p1, {x, y} == p1_pos)
      |> assign(:is_p2, {x, y} == p2_pos)
      |> assign(:on_edge, on_edge)

    ~H"""
    <%= cond do %>
      <% @is_p1 -> %>
        <div class="w-8 h-8 border border-blue-400 bg-blue-500 flex items-center justify-center text-white font-bold">
          1
        </div>

      <% @is_p2 -> %>
        <div class="w-8 h-8 border border-red-400 bg-red-500 flex items-center justify-center text-white font-bold">
          2
        </div>

      <% @on_edge -> %>
        <div class="w-8 h-8 border border-gray-600 bg-gray-700"></div>

      <% true -> %>
        <div class="w-8 h-8 border border-gray-800 bg-gray-900"></div>
    <% end %>
    """
  end
end
