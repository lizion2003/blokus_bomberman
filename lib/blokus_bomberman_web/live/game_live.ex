defmodule BlokusBombermanWeb.GameLive do
  use BlokusBombermanWeb, :live_view

  alias BlokusBomberman.{Game, Board, Piece}

  @move_interval 70  # milliseconds between moves when key is held

  @impl true
  def mount(_params, _session, socket) do
    game = Game.new()

    if connected?(socket) do
      schedule_tick()
    end

    # Initialize Player 1's piece selection state
    p1_selection = %{
      size_tab: 1,  # Currently selected size (1-5)
      piece_index: 0,  # Index within the size group
      rotation: 0,  # Number of 90° rotations (0-3)
      flipped: false  # Whether piece is flipped
    }

    {:ok, assign(socket,
      game: game,
      message: "Player 1: Select pieces with 1-5, A/D, R, F | Navigate: W/S",
      keys_pressed: MapSet.new(),
      p1_selection: p1_selection
    )}
  end

  @impl true
  def handle_event("keydown", %{"key" => key}, socket) do
    keys_pressed = MapSet.put(socket.assigns.keys_pressed, key)
    p1_selection = socket.assigns.p1_selection

    # Handle Player 1 piece selection controls
    new_p1_selection = case key do
      # Size tab selection (1-5)
      "1" -> %{p1_selection | size_tab: 1, piece_index: 0}
      "2" -> %{p1_selection | size_tab: 2, piece_index: 0}
      "3" -> %{p1_selection | size_tab: 3, piece_index: 0}
      "4" -> %{p1_selection | size_tab: 4, piece_index: 0}
      "5" -> %{p1_selection | size_tab: 5, piece_index: 0}

      # Navigate between pieces in group (A/D)
      "a" -> navigate_piece(p1_selection, -1)
      "A" -> navigate_piece(p1_selection, -1)
      "d" -> navigate_piece(p1_selection, 1)
      "D" -> navigate_piece(p1_selection, 1)

      # Rotate piece (R)
      "r" -> %{p1_selection | rotation: rem(p1_selection.rotation + 1, 4)}
      "R" -> %{p1_selection | rotation: rem(p1_selection.rotation + 1, 4)}

      # Flip piece (F)
      "f" -> %{p1_selection | flipped: !p1_selection.flipped}
      "F" -> %{p1_selection | flipped: !p1_selection.flipped}

      _ -> p1_selection
    end

    {:noreply, assign(socket, keys_pressed: keys_pressed, p1_selection: new_p1_selection)}
  end

  def handle_event("keyup", %{"key" => key}, socket) do
    keys_pressed = MapSet.delete(socket.assigns.keys_pressed, key)
    {:noreply, assign(socket, keys_pressed: keys_pressed)}
  end

  defp navigate_piece(selection, direction) do
    pieces = Piece.pieces_by_size(selection.size_tab)
    max_index = length(pieces) - 1
    new_index = selection.piece_index + direction

    # Wrap around
    new_index = cond do
      new_index < 0 -> max_index
      new_index > max_index -> 0
      true -> new_index
    end

    %{selection | piece_index: new_index}
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

  defp get_selected_piece(selection) do
    pieces = Piece.pieces_by_size(selection.size_tab)

    if Enum.empty?(pieces) do
      {nil, []}
    else
      piece_type = Enum.at(pieces, selection.piece_index)
      coords = Piece.get_shape(piece_type)

      # Apply transformations
      coords = if selection.flipped, do: Piece.flip_horizontal(coords), else: coords
      coords = Enum.reduce(1..selection.rotation, coords, fn _, acc -> Piece.rotate(acc) end)

      {piece_type, coords}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center p-4 bg-gray-900 min-h-screen" phx-window-keydown="keydown" phx-window-keyup="keyup">
      <h1 class="text-4xl font-bold mb-4 text-white">Blokus Bomberman</h1>
      <p class="text-lg mb-6 text-gray-300"><%= @message %></p>

      <div class="flex gap-8 mb-6">
        <div class="px-4 py-2 rounded bg-blue-600 text-white font-bold">
          Player 1 (Blue): W/S Move | 1-5 Size | A/D Select | R Rotate | F Flip
        </div>
        <div class="px-4 py-2 rounded bg-red-600 text-white font-bold">
          Player 2 (Red): ↑ / ↓
        </div>
      </div>

      <!-- Main Game Area with Piece Selector and Board -->
      <div class="flex gap-6">
        <!-- Player 1 Piece Selector (Left) -->
        <div class="flex flex-col gap-4">
          <div class="bg-gray-800 border-4 border-blue-600 rounded-lg p-4 w-64">
            <h3 class="text-blue-400 font-bold text-lg mb-3">Player 1 - Piece Selection</h3>

            <!-- Size Tabs -->
            <div class="flex gap-1 mb-4">
              <%= for size <- Piece.all_sizes() do %>
                <button class={"px-3 py-1 rounded text-sm font-bold #{if size == @p1_selection.size_tab, do: "bg-blue-600 text-white", else: "bg-gray-700 text-gray-400"}"}>
                  <%= size %>
                </button>
              <% end %>
            </div>

            <!-- Current Piece Info -->
            <div class="mb-3 text-gray-300 text-sm">
              <p>Size: <%= @p1_selection.size_tab %> blocks</p>
              <p>Piece: <%= @p1_selection.piece_index + 1 %> / <%= length(Piece.pieces_by_size(@p1_selection.size_tab)) %></p>
              <p>Rotation: <%= @p1_selection.rotation * 90 %>°</p>
              <p>Flipped: <%= if @p1_selection.flipped, do: "Yes", else: "No" %></p>
            </div>

            <!-- Piece Preview -->
            <div class="bg-gray-900 border-2 border-gray-700 rounded p-4 flex items-center justify-center" style="min-height: 150px;">
              <%= render_piece_preview(assigns, @p1_selection) %>
            </div>

            <!-- Controls Help -->
            <div class="mt-4 text-xs text-gray-400">
              <p><strong>1-5:</strong> Switch size</p>
              <p><strong>A/D:</strong> Prev/Next piece</p>
              <p><strong>R:</strong> Rotate</p>
              <p><strong>F:</strong> Flip</p>
            </div>
          </div>
        </div>

        <!-- Game Board (Center) -->
        <div class="border-4 border-gray-700 bg-gray-800 shadow-2xl">
          <div class="grid gap-0" style={"grid-template-columns: repeat(#{Board.size()}, 2rem);"}>
            <%= for y <- 0..(Board.size() - 1) do %>
              <%= for x <- 0..(Board.size() - 1) do %>
                <%= render_cell(assigns, {x, y}) %>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>

      <div class="mt-6 text-gray-400 text-sm">
        <p>💡 Select and transform pieces, then throw them onto the board!</p>
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

  defp render_piece_preview(assigns, selection) do
    {piece_type, coords} = get_selected_piece(selection)

    if piece_type == nil or Enum.empty?(coords) do
      assigns = assign(assigns, :empty, true)
      ~H"""
      <div class="text-gray-500 text-sm">No piece available</div>
      """
    else
      {width, height} = Piece.get_bounds(coords)

      # Calculate cell size based on piece dimensions
      max_dim = max(width, height)
      cell_size = cond do
        max_dim <= 2 -> "2rem"
        max_dim <= 3 -> "1.5rem"
        max_dim <= 4 -> "1.2rem"
        true -> "1rem"
      end

      assigns = assigns
        |> assign(:coords, coords)
        |> assign(:width, width)
        |> assign(:height, height)
        |> assign(:cell_size, cell_size)

      ~H"""
      <div class="grid gap-0" style={"grid-template-columns: repeat(#{@width}, #{@cell_size});"}>
        <%= for y <- 0..(@height - 1) do %>
          <%= for x <- 0..(@width - 1) do %>
            <%= if {x, y} in @coords do %>
              <div class={"border border-blue-400 bg-blue-500"} style={"width: #{@cell_size}; height: #{@cell_size};"}></div>
            <% else %>
              <div class="bg-transparent" style={"width: #{@cell_size}; height: #{@cell_size};"}></div>
            <% end %>
          <% end %>
        <% end %>
      </div>
      """
    end
  end
end
