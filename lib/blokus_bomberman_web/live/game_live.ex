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
      animating_pieces: [],  # List of pieces currently animating
      dissolving_pieces: [],  # List of invalid pieces dissolving
      preview_landing: nil,  # Preview of where piece will land (for debugging)
      power_projection: nil  # {player_id, target_coords} showing where piece will land while charging
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
      # Size group cycling (Q/E to cycle through 3 groups: 1-2-3, 4, 5)
      "q" ->
        new_size = if p1_selection.size_tab > 1, do: p1_selection.size_tab - 1, else: 3
        %{p1_selection | size_tab: new_size, piece_index: 0}
      "Q" ->
        new_size = if p1_selection.size_tab > 1, do: p1_selection.size_tab - 1, else: 3
        %{p1_selection | size_tab: new_size, piece_index: 0}
      "e" ->
        new_size = if p1_selection.size_tab < 3, do: p1_selection.size_tab + 1, else: 1
        %{p1_selection | size_tab: new_size, piece_index: 0}
      "E" ->
        new_size = if p1_selection.size_tab < 3, do: p1_selection.size_tab + 1, else: 1
        %{p1_selection | size_tab: new_size, piece_index: 0}

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
    {new_animating_pieces, new_power_state, new_preview, message} = case key do
      " " ->
        player1_state = power_state.player1

        if player1_state.power > 0 do
          # Get the selected piece and player position
          {_piece_type, piece_coords} = get_selected_piece(socket.assigns.p1_selection)
          player = game.player1

          # Calculate target position and check validity
          {target_coords, is_valid} = Game.calculate_placement_with_validity(game, 1, piece_coords, player1_state.power)

          # Always animate, but mark if placement is valid or not
          animation = %{
            player_id: 1,
            piece_coords: piece_coords,
            start_pos: player.position,
            target_coords: target_coords,
            color: player.color,
            progress: 0.0,
            start_time: System.monotonic_time(:millisecond),
            is_valid: is_valid  # Mark if this will be a valid placement
          }

          schedule_animation_tick()

          message_text = if is_valid do
            "Player 1 threw piece with #{player1_state.power}% power!"
          else
            "Invalid placement! Piece will dissolve..."
          end

          {[animation | socket.assigns.animating_pieces],
           %{power_state | player1: %{charging: false, power: 0}},
           target_coords,  # Store for preview
           message_text}
        else
          {socket.assigns.animating_pieces,
           %{power_state | player1: %{charging: false, power: 0}},
           nil,
           socket.assigns.message}
        end
      _ ->
        {socket.assigns.animating_pieces, power_state, nil, socket.assigns.message}
    end

    {:noreply, assign(socket,
      keys_pressed: keys_pressed,
      power_state: new_power_state,
      animating_pieces: new_animating_pieces,
      preview_landing: new_preview,
      message: message
    )}
  end

  defp get_pieces_by_group(group) when is_integer(group) do
    case group do
      1 -> Piece.pieces_by_size(1) ++ Piece.pieces_by_size(2) ++ Piece.pieces_by_size(3)
      2 -> Piece.pieces_by_size(4)
      3 -> Piece.pieces_by_size(5)
      _ -> []
    end
  end

  defp get_pieces_by_group(_assigns, group), do: get_pieces_by_group(group)

  defp navigate_piece(selection, direction) do
    pieces = get_pieces_by_group(selection.size_tab)
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
      game = socket.assigns.game
      p1_selection = socket.assigns.p1_selection

      {new_power_state, power_projection} = if player1_state.charging do
        # Increase power, cycling back to 0 if it exceeds max
        new_power = rem(player1_state.power + 2, @max_power + 1)

        # Calculate where piece would land at current power
        {_piece_type, piece_coords} = get_selected_piece(p1_selection)
        {target_coords, _is_valid} = Game.calculate_placement_with_validity(game, 1, piece_coords, new_power)

        # Continue charging
        schedule_power_tick()

        {%{power_state | player1: %{player1_state | power: new_power}},
         {1, target_coords}}
      else
        {power_state, nil}
      end

      {:noreply, assign(socket, power_state: new_power_state, power_projection: power_projection)}
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

      # Separate valid and invalid completed animations
      {valid_completed, invalid_completed} = Enum.split_with(completed, fn anim ->
        Map.get(anim, :is_valid, true)
      end)

      # Only add valid placements to the game board
      new_game = Enum.reduce(valid_completed, socket.assigns.game, fn anim, game ->
        placed_piece = {anim.player_id, anim.target_coords, anim.color}
        %{game | placed_pieces: [placed_piece | game.placed_pieces]}
      end)

      # Invalid pieces start dissolving - add them back with fade progress
      dissolving = invalid_completed
        |> Enum.map(fn anim ->
          anim
          |> Map.put(:progress, 1.0)  # Keep at destination
          |> Map.put(:dissolving, true)
          |> Map.put(:dissolve_start, current_time)
          |> Map.put(:dissolve_progress, 0.0)
        end)

      # Update dissolving pieces
      existing_dissolving = Map.get(socket.assigns, :dissolving_pieces, [])

      {_fully_dissolved, still_dissolving} = existing_dissolving
        |> Enum.concat(dissolving)
        |> Enum.map(fn anim ->
          # Get dissolve_start, default to current_time if not present
          dissolve_start = Map.get(anim, :dissolve_start, current_time)
          elapsed = current_time - dissolve_start
          dissolve_progress = min(1.0, elapsed / 500)  # 500ms dissolve duration (slower for clarity)

          # Calculate shake offset (oscillates quickly then fades)
          shake_frequency = 30.0  # Fast shake
          shake_amplitude = if dissolve_progress < 0.6, do: 8, else: 0  # Shake for first 300ms (8px amplitude)
          shake_offset_x = if dissolve_progress < 0.6 do
            round(:math.sin(elapsed / 1000 * shake_frequency * :math.pi() * 2) * shake_amplitude)
          else
            0
          end
          shake_offset_y = if dissolve_progress < 0.6 do
            round(:math.cos(elapsed / 1000 * shake_frequency * :math.pi() * 2) * shake_amplitude)
          else
            0
          end

          anim
          |> Map.put(:dissolve_progress, dissolve_progress)
          |> Map.put(:shake_offset_x, shake_offset_x)
          |> Map.put(:shake_offset_y, shake_offset_y)
        end)
        |> Enum.split_with(fn anim -> Map.get(anim, :dissolve_progress, 0.0) >= 1.0 end)

      # Schedule next tick if there are still animating or dissolving pieces
      if length(still_animating) > 0 or length(still_dissolving) > 0 do
        schedule_animation_tick()
      end

      # Clear preview when all animations complete
      new_preview = if length(still_animating) == 0 and length(still_dissolving) == 0,
        do: nil,
        else: socket.assigns.preview_landing

      {:noreply, assign(socket,
        game: new_game,
        animating_pieces: still_animating,
        dissolving_pieces: still_dissolving,
        preview_landing: new_preview
      )}
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
    pieces = get_pieces_by_group(selection.size_tab)

    if Enum.empty?(pieces) do
      {nil, []}
    else
      piece_type = Enum.at(pieces, selection.piece_index)
      coords = Piece.get_shape(piece_type)

      # Apply transformations
      coords = if selection.flipped, do: Piece.flip_horizontal(coords), else: coords

      # Apply rotation based on the rotation value (0-3 for 0°, 90°, 180°, 270°)
      coords = case selection.rotation do
        0 -> coords
        1 -> Piece.rotate(coords)
        2 -> coords |> Piece.rotate() |> Piece.rotate()
        3 -> coords |> Piece.rotate() |> Piece.rotate() |> Piece.rotate()
        _ -> coords
      end

      {piece_type, coords}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center p-4 bg-gray-900 min-h-screen" phx-window-keydown="keydown" phx-window-keyup="keyup">
      <h1 class="text-4xl font-bold mb-4 text-white">Blokus Bomberman</h1>

      <div class="flex gap-8 mb-6">
        <div class="px-4 py-2 rounded bg-blue-600 text-white font-bold">
          Player 1 (Blue): W/S Move | Q/E Group | A/D Select | R Rotate | F Flip | K Clear
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
              <%= for group <- [1, 2, 3] do %>
                <%
                  group_label = case group do
                    1 -> "1-3"
                    2 -> "4"
                    3 -> "5"
                  end
                %>
                <button class={"px-3 py-1 rounded text-sm font-bold #{if group == @p1_selection.size_tab, do: "bg-blue-600 text-white", else: "bg-gray-700 text-gray-400"}"}>
                  <%= group_label %>
                </button>
              <% end %>
            </div>

            <!-- Current Piece Info -->
            <%
              group_name = case @p1_selection.size_tab do
                1 -> "Small (1-3 blocks)"
                2 -> "Medium (4 blocks)"
                3 -> "Large (5 blocks)"
                _ -> "Unknown"
              end
              total_pieces = length(get_pieces_by_group(assigns, @p1_selection.size_tab))
            %>
            <div class="mb-3 text-gray-300 text-sm">
              <p>Group: <%= group_name %></p>
              <p>Piece: <%= @p1_selection.piece_index + 1 %> / <%= total_pieces %></p>
              <p>Rotation: <%= @p1_selection.rotation * 90 %>°</p>
              <p>Flipped: <%= if @p1_selection.flipped, do: "Yes", else: "No" %></p>
            </div>

            <!-- Piece Preview -->
            <div class="bg-gray-900 border-2 border-gray-700 rounded p-4 flex items-center justify-center" style="min-height: 150px;">
              <%= render_piece_preview(assigns, @p1_selection) %>
            </div>

            <!-- Controls Help -->
            <div class="mt-4 text-xs text-gray-400">
              <p><strong>Q/E:</strong> Switch group (Small/Medium/Large)</p>
              <p><strong>A/D:</strong> Prev/Next piece in group</p>
              <p><strong>R:</strong> Rotate</p>
              <p><strong>F:</strong> Flip</p>
              <p><strong>SPACE:</strong> Hold to charge throw</p>
              <p><strong>K:</strong> Clear board (debug)</p>
              <p class="mt-2 text-yellow-400"><strong>⭐ Anchor:</strong> Travels from your position</p>
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

      <!-- Message Dialog Box (Below Board) -->
      <div class="mt-6 bg-gray-800 border-2 border-gray-600 rounded-lg p-4 w-full max-w-4xl">
        <div class="text-center">
          <p class="text-lg font-semibold text-gray-200"><%= @message %></p>
        </div>
      </div>

      <div class="mt-4 text-gray-400 text-sm text-center">
        <p>💡 Select and transform pieces, then throw them onto the board!</p>
        <p>📐 <strong>Blokus Rule:</strong> After first piece, new pieces must touch same-color corner (not edge)!</p>
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

    # Check if this cell has a dissolving piece
    dissolving_info = get_dissolving_piece_info(assigns.dissolving_pieces, {x, y})

    # Check if this cell is in the preview landing position (for debugging)
    is_preview = assigns.preview_landing != nil and {x, y} in assigns.preview_landing

    # Check if this cell should be highlighted based on player facing direction
    # Players on edges face inward (toward the board interior)
    {p1_x, p1_y} = p1_pos
    {p2_x, p2_y} = p2_pos

    highlight_color = cond do
      # Player 1 (blue) - check if cell is in their facing row/column
      p1_x == 0 and x == p1_x and y == p1_y -> nil  # Don't highlight player's own position
      p1_x == 0 and y == p1_y -> :blue  # Left edge, faces right (highlight row)
      p1_x == Board.size() - 1 and y == p1_y -> :blue  # Right edge, faces left (highlight row)
      p1_y == 0 and x == p1_x -> :blue  # Top edge, faces down (highlight column)
      p1_y == Board.size() - 1 and x == p1_x -> :blue  # Bottom edge, faces up (highlight column)

      # Player 2 (red) - check if cell is in their facing row/column
      p2_x == 0 and x == p2_x and y == p2_y -> nil  # Don't highlight player's own position
      p2_x == 0 and y == p2_y -> :red  # Left edge, faces right (highlight row)
      p2_x == Board.size() - 1 and y == p2_y -> :red  # Right edge, faces left (highlight row)
      p2_y == 0 and x == p2_x -> :red  # Top edge, faces down (highlight column)
      p2_y == Board.size() - 1 and x == p2_x -> :red  # Bottom edge, faces up (highlight column)

      true -> nil
    end

    # Check if this cell is part of the power projection
    is_power_projection = case assigns.power_projection do
      {_player_id, target_coords} when is_list(target_coords) ->
        {x, y} in target_coords
      _ -> false
    end

    assigns = assigns
      |> assign(:x, x)
      |> assign(:y, y)
      |> assign(:is_p1, {x, y} == p1_pos)
      |> assign(:is_p2, {x, y} == p2_pos)
      |> assign(:on_edge, on_edge)
      |> assign(:placed_color, placed_piece_color)
      |> assign(:animating_color, animating_color)
      |> assign(:dissolving_info, dissolving_info)
      |> assign(:is_preview, is_preview)
      |> assign(:highlight_color, highlight_color)
      |> assign(:is_power_projection, is_power_projection)

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

      <% @dissolving_info -> %>
        <%
          {_color, dissolve_progress, shake_offset_x, shake_offset_y} = @dissolving_info
          opacity = (1.0 - dissolve_progress)
          transform = "translate(#{shake_offset_x}px, #{shake_offset_y}px)"
        %>
          <div
            class="w-8 h-8 border-2 border-red-600 bg-red-500 flex items-center justify-center"
            style={"transform: #{transform}; opacity: #{opacity};"}
          >
            <span class="text-white text-2xl font-bold">✗</span>
          </div>

      <% @is_preview -> %>
        <div class="w-8 h-8 border-2 border-yellow-400 bg-yellow-500 opacity-50 flex items-center justify-center text-white font-bold text-xs">
          🎯
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

      <% @is_power_projection -> %>
        <div class="w-8 h-8 border-2 border-yellow-300 bg-yellow-500 opacity-70 animate-pulse flex items-center justify-center">
          <span class="text-white text-xl font-bold">⚡</span>
        </div>

      <% @on_edge -> %>
        <%
          bg_class = case @highlight_color do
            :blue -> "bg-blue-900"
            :red -> "bg-red-900"
            _ -> "bg-gray-700"
          end
        %>
        <div class={"w-8 h-8 border border-gray-600 #{bg_class}"}></div>

      <% true -> %>
        <%
          bg_class = case @highlight_color do
            :blue -> "bg-blue-900"
            :red -> "bg-red-900"
            _ -> "bg-gray-900"
          end
        %>
        <div class={"w-8 h-8 border border-gray-800 #{bg_class}"}></div>
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

  defp get_dissolving_piece_info(dissolving_pieces, coord) do
    Enum.find_value(dissolving_pieces, fn anim ->
      # Dissolving pieces stay at their target position
      current_coords = interpolate_piece_position(anim)
      if coord in current_coords do
        shake_offset_x = Map.get(anim, :shake_offset_x, 0)
        shake_offset_y = Map.get(anim, :shake_offset_y, 0)
        {anim.color, anim.dissolve_progress, shake_offset_x, shake_offset_y}
      else
        nil
      end
    end)
  end

  defp interpolate_piece_position(anim) do
    {start_x, start_y} = anim.start_pos
    progress = anim.progress

    # The anchor block (first coordinate in piece_coords) travels in a straight line
    # from player position to its corresponding position in target_coords
    anchor_piece = hd(anim.piece_coords)
    anchor_target = hd(anim.target_coords)
    {anchor_target_x, anchor_target_y} = anchor_target

    # Interpolate where the anchor block should be right now
    current_anchor_x = start_x + (anchor_target_x - start_x) * progress
    current_anchor_y = start_y + (anchor_target_y - start_y) * progress

    # Position all blocks relative to the anchor block
    # using the relative offsets from piece_coords
    {anchor_piece_x, anchor_piece_y} = anchor_piece

    Enum.map(anim.piece_coords, fn {piece_x, piece_y} ->
      # Calculate offset from anchor in the piece shape
      offset_x = piece_x - anchor_piece_x
      offset_y = piece_y - anchor_piece_y
      # Apply offset to current anchor position
      {round(current_anchor_x + offset_x), round(current_anchor_y + offset_y)}
    end)
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

      # The first coordinate is the anchor block
      anchor_block = hd(coords)

      assigns = assigns
        |> assign(:coords, coords)
        |> assign(:anchor_block, anchor_block)
        |> assign(:width, width)
        |> assign(:height, height)
        |> assign(:cell_size, cell_size)

      ~H"""
      <div class="grid gap-0" style={"grid-template-columns: repeat(#{@width}, #{@cell_size});"}>
        <%= for y <- 0..(@height - 1) do %>
          <%= for x <- 0..(@width - 1) do %>
            <%= cond do %>
              <% {x, y} == @anchor_block -> %>
                <!-- Anchor block - highlighted with different color and star -->
                <div class="border-2 border-yellow-400 bg-yellow-500 flex items-center justify-center text-white font-bold text-xs" style={"width: #{@cell_size}; height: #{@cell_size};"}>
                  ⭐
                </div>
              <% {x, y} in @coords -> %>
                <!-- Regular piece block -->
                <div class="border border-blue-400 bg-blue-500" style={"width: #{@cell_size}; height: #{@cell_size};"}></div>
              <% true -> %>
                <!-- Empty space -->
                <div class="bg-transparent" style={"width: #{@cell_size}; height: #{@cell_size};"}></div>
            <% end %>
          <% end %>
        <% end %>
      </div>
      <div class="mt-2 text-xs text-yellow-400 text-center">
        ⭐ = Anchor (travels from player)
      </div>
      """
    end
  end
end
