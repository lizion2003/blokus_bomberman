defmodule BlokusBombermanWeb.GameLive do
  use BlokusBombermanWeb, :live_view

  alias BlokusBomberman.{Game, Board, Piece}

  @move_interval 70  # milliseconds between moves when key is held
  @power_interval 20  # milliseconds between power updates
  @max_power 100  # Maximum power value
  @animation_duration 500  # milliseconds for throw animation
  @animation_interval 16  # ~60 FPS

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

    # Initialize power gauge state for both players
    power_state = %{
      player1: %{charging: false, power: 0},
      player2: %{charging: false, power: 0}
    }

    {:ok, assign(socket,
      game: game,
      message: "Player 1: Select pieces with 1-5, A/D, R, F | Navigate: W/S | Hold SPACE to charge throw | Press K to clear board",
      keys_pressed: MapSet.new(),
      p1_selection: p1_selection,
      power_state: power_state,
      animating_pieces: []  # List of pieces currently animating
    )}
  end

  @impl true
  def handle_event("keydown", %{"key" => key}, socket) do
    keys_pressed = MapSet.put(socket.assigns.keys_pressed, key)
    p1_selection = socket.assigns.p1_selection
    power_state = socket.assigns.power_state
    game = socket.assigns.game

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

    # Handle spacebar for power charging
    new_power_state = case key do
      " " ->
        # Start charging for Player 1 (we'll add Player 2 later)
        player1_state = power_state.player1
        if not player1_state.charging do
          schedule_power_tick()
          %{power_state | player1: %{player1_state | charging: true}}
        else
          power_state
        end
      _ ->
        power_state
    end

    # Handle K key to clear all pieces (debugging)
    {new_game, message} = case key do
      "k" ->
        {%{game | placed_pieces: []}, "🧹 Board cleared! (Debug mode)"}
      "K" ->
        {%{game | placed_pieces: []}, "🧹 Board cleared! (Debug mode)"}
      _ ->
        {game, socket.assigns.message}
    end

    {:noreply, assign(socket,
      keys_pressed: keys_pressed,
      p1_selection: new_p1_selection,
      power_state: new_power_state,
      game: new_game,
      message: message
    )}
  end

  def handle_event("keyup", %{"key" => key}, socket) do
    keys_pressed = MapSet.delete(socket.assigns.keys_pressed, key)
    power_state = socket.assigns.power_state
    game = socket.assigns.game

    # Handle spacebar release - start animation for throwing the piece
    {new_animating_pieces, new_power_state, message} = case key do
      " " ->
        player1_state = power_state.player1

        if player1_state.power > 0 do
          # Get the selected piece and player position
          {_piece_type, piece_coords} = get_selected_piece(socket.assigns.p1_selection)
          player = game.player1

          # Calculate target position (validate it first)
          target_coords = Game.calculate_placement(game, 1, piece_coords, player1_state.power)

          if target_coords != nil do
            # Start animation
            animation = %{
              player_id: 1,
              piece_coords: piece_coords,
              start_pos: player.position,
              target_coords: target_coords,
              color: player.color,
              progress: 0.0,
              start_time: System.monotonic_time(:millisecond)
            }

            schedule_animation_tick()

            {[animation | socket.assigns.animating_pieces],
             %{power_state | player1: %{charging: false, power: 0}},
             "Player 1 threw piece with #{player1_state.power}% power!"}
          else
            {socket.assigns.animating_pieces,
             %{power_state | player1: %{charging: false, power: 0}},
             "Invalid placement! Try different power or position."}
          end
        else
          {socket.assigns.animating_pieces,
           %{power_state | player1: %{charging: false, power: 0}},
           socket.assigns.message}
        end
      _ ->
        {socket.assigns.animating_pieces, power_state, socket.assigns.message}
    end

    {:noreply, assign(socket,
      keys_pressed: keys_pressed,
      power_state: new_power_state,
      animating_pieces: new_animating_pieces,
      message: message
    )}
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

  @impl true
  def handle_info(:power_tick, socket) do
    # Only process if socket is still connected
    if connected?(socket) do
      power_state = socket.assigns.power_state
      player1_state = power_state.player1

      new_power_state = if player1_state.charging do
        # Increase power, cycling back to 0 if it exceeds max
        new_power = rem(player1_state.power + 2, @max_power + 1)

        # Continue charging
        schedule_power_tick()

        %{power_state | player1: %{player1_state | power: new_power}}
      else
        power_state
      end

      {:noreply, assign(socket, power_state: new_power_state)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:animation_tick, socket) do
    if connected?(socket) do
      current_time = System.monotonic_time(:millisecond)

      # Update all animating pieces
      {completed, still_animating} = socket.assigns.animating_pieces
        |> Enum.map(fn anim ->
          elapsed = current_time - anim.start_time
          progress = min(1.0, elapsed / @animation_duration)
          %{anim | progress: progress}
        end)
        |> Enum.split_with(fn anim -> anim.progress >= 1.0 end)

      # Add completed animations to the game board
      new_game = Enum.reduce(completed, socket.assigns.game, fn anim, game ->
        placed_piece = {anim.player_id, anim.target_coords, anim.color}
        %{game | placed_pieces: [placed_piece | game.placed_pieces]}
      end)

      # Schedule next tick if there are still animating pieces
      if length(still_animating) > 0 do
        schedule_animation_tick()
      end

      {:noreply, assign(socket, game: new_game, animating_pieces: still_animating)}
    else
      {:noreply, socket}
    end
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

  defp schedule_power_tick do
    Process.send_after(self(), :power_tick, @power_interval)
  end

  defp schedule_animation_tick do
    Process.send_after(self(), :animation_tick, @animation_interval)
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
          Player 1 (Blue): W/S Move | 1-5 Size | A/D Select | R Rotate | F Flip | K Clear
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
              <p><strong>SPACE:</strong> Hold to charge throw</p>
              <p><strong>K:</strong> Clear board (debug)</p>
            </div>
          </div>

          <!-- Power Gauge -->
          <div class="bg-gray-800 border-4 border-blue-600 rounded-lg p-4 w-64">
            <h3 class="text-blue-400 font-bold text-lg mb-3">Throw Power</h3>
            <div class="bg-gray-900 border-2 border-gray-700 rounded overflow-hidden h-8 relative">
              <!-- Power fill bar -->
              <div class="h-full bg-gradient-to-r from-green-500 via-yellow-500 to-red-500 transition-all duration-75" style={"width: #{@power_state.player1.power}%"}>
              </div>
              <!-- Power percentage text -->
              <div class="absolute inset-0 flex items-center justify-center text-white font-bold text-sm">
                <%= @power_state.player1.power %>%
              </div>
            </div>
            <div class="mt-2 text-xs text-gray-400 text-center">
              <%= if @power_state.player1.charging do %>
                <span class="text-yellow-400 animate-pulse">⚡ Charging...</span>
              <% else %>
                <span>Hold SPACE to charge</span>
              <% end %>
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

    # Check if this cell has a placed piece
    placed_piece_color = get_placed_piece_color(assigns.game.placed_pieces, {x, y})

    # Check if this cell has an animating piece
    animating_color = get_animating_piece_color(assigns.animating_pieces, {x, y})

    assigns = assigns
      |> assign(:x, x)
      |> assign(:y, y)
      |> assign(:is_p1, {x, y} == p1_pos)
      |> assign(:is_p2, {x, y} == p2_pos)
      |> assign(:on_edge, on_edge)
      |> assign(:placed_color, placed_piece_color)
      |> assign(:animating_color, animating_color)

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

      <% @animating_color -> %>
        <%= if @animating_color == :blue do %>
          <div class="w-8 h-8 border border-blue-300 bg-blue-400 opacity-60 animate-pulse"></div>
        <% else %>
          <div class="w-8 h-8 border border-red-300 bg-red-400 opacity-60 animate-pulse"></div>
        <% end %>

      <% @placed_color -> %>
        <%= if @placed_color == :blue do %>
          <div class="w-8 h-8 border border-blue-300 bg-blue-400 opacity-80"></div>
        <% else %>
          <div class="w-8 h-8 border border-red-300 bg-red-400 opacity-80"></div>
        <% end %>

      <% @on_edge -> %>
        <div class="w-8 h-8 border border-gray-600 bg-gray-700"></div>

      <% true -> %>
        <div class="w-8 h-8 border border-gray-800 bg-gray-900"></div>
    <% end %>
    """
  end

  defp get_placed_piece_color(placed_pieces, coord) do
    Enum.find_value(placed_pieces, fn {_player_id, coords, color} ->
      if coord in coords, do: color, else: nil
    end)
  end

  defp get_animating_piece_color(animating_pieces, coord) do
    Enum.find_value(animating_pieces, fn anim ->
      # Interpolate between start position and target coordinates
      current_coords = interpolate_piece_position(anim)
      if coord in current_coords, do: anim.color, else: nil
    end)
  end

  defp interpolate_piece_position(anim) do
    {start_x, start_y} = anim.start_pos
    progress = anim.progress

    # Calculate the center of target coordinates
    target_center = calculate_center(anim.target_coords)
    {target_x, target_y} = target_center

    # Interpolate the anchor position
    current_x = start_x + (target_x - start_x) * progress
    current_y = start_y + (target_y - start_y) * progress

    # Calculate offset from center to first piece coordinate
    {first_x, first_y} = hd(anim.target_coords)
    offset_x = first_x - target_x
    offset_y = first_y - target_y

    # Apply offset to all piece coordinates
    Enum.map(anim.piece_coords, fn {dx, dy} ->
      x = round(current_x + dx + offset_x)
      y = round(current_y + dy + offset_y)
      {x, y}
    end)
  end

  defp calculate_center(coords) do
    count = length(coords)
    {sum_x, sum_y} = Enum.reduce(coords, {0, 0}, fn {x, y}, {acc_x, acc_y} ->
      {acc_x + x, acc_y + y}
    end)
    {sum_x / count, sum_y / count}
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
