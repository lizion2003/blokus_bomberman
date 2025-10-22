defmodule BlokusBomberman.Game do
  @moduledoc """
  Manages the game state for two players controlling avatars on board edges.
  """

  alias BlokusBomberman.Board

  @doc """
  Create a new game with two players
  """
  def new do
    positions = Board.initial_positions()

    %{
      player1: %{
        id: 1,
        position: positions.player1,
        color: :blue
      },
      player2: %{
        id: 2,
        position: positions.player2,
        color: :red
      },
      placed_pieces: []  # List of placed pieces: [{player_id, coords, color}, ...]
    }
  end

  @doc """
  Move a player's avatar around the perimeter.
  Only up/down directions - automatically wraps around corners.
  """
  def move_player(game, player_id, direction) do
    player_key = player_key(player_id)
    player = Map.get(game, player_key)

    new_pos = move_along_perimeter(player.position, direction)

    # Check if colliding with other player
    other_player = get_other_player(game, player_id)

    if new_pos != other_player.position do
      updated_player = %{player | position: new_pos}
      %{game | player_key => updated_player}
    else
      # Collision - return game unchanged
      game
    end
  end

  @doc """
  Move along the perimeter in clockwise (:down) or counter-clockwise (:up) direction.
  The perimeter is treated as a continuous loop.
  """
  defp move_along_perimeter({x, y}, direction) do
    size = Board.size()
    max_coord = size - 1

    # Calculate perimeter position (0 to perimeter_length - 1)
    # Perimeter segments: top (left to right), right (top to bottom),
    # bottom (right to left), left (bottom to top)
    perimeter_length = 4 * (size - 1)

    current_index = cond do
      # Top edge (y = 0, x from 0 to max_coord)
      y == 0 and x < max_coord -> x
      # Right edge (x = max_coord, y from 0 to max_coord)
      x == max_coord and y < max_coord -> size - 1 + y
      # Bottom edge (y = max_coord, x from max_coord to 0)
      y == max_coord and x > 0 -> 2 * (size - 1) + (max_coord - x)
      # Left edge (x = 0, y from max_coord to 0)
      x == 0 and y > 0 -> 3 * (size - 1) + (max_coord - y)
      # Corner case: bottom-left corner wrapping
      true -> 0
    end

    # Move in the direction
    new_index = case direction do
      :down -> rem(current_index + 1, perimeter_length)
      :up -> rem(current_index - 1 + perimeter_length, perimeter_length)
    end

    # Convert index back to coordinates
    index_to_position(new_index, size)
  end

  defp index_to_position(index, size) do
    max_coord = size - 1
    segment_length = size - 1

    cond do
      # Top edge
      index < segment_length ->
        {index, 0}
      # Right edge
      index < 2 * segment_length ->
        {max_coord, index - segment_length}
      # Bottom edge
      index < 3 * segment_length ->
        {max_coord - (index - 2 * segment_length), max_coord}
      # Left edge
      true ->
        {0, max_coord - (index - 3 * segment_length)}
    end
  end

  @doc """
  Calculate where a piece would be placed without actually placing it.
  Returns the target coordinates if valid, nil otherwise.
  """
  def calculate_placement(game, player_id, piece_coords, power) do
    player_key = player_key(player_id)
    player = Map.get(game, player_key)
    {px, py} = player.position

    # Determine throw direction based on player position on edge
    direction = get_throw_direction({px, py})

    # Calculate placement distance based on power (0-100)
    max_distance = Board.size() - 1
    distance = if power >= 95 do
      max_distance
    else
      # Scale power (0-94) to distance (1 to max_distance-1)
      max(1, round(power / 100.0 * max_distance))
    end

    # Calculate the anchor position for the piece
    anchor_pos = calculate_throw_position({px, py}, direction, distance)

    # Translate piece coordinates to world position
    placed_coords = Enum.map(piece_coords, fn {dx, dy} ->
      {anchor_pos |> elem(0) |> Kernel.+(dx), anchor_pos |> elem(1) |> Kernel.+(dy)}
    end)

    # Check if all coordinates are valid (within bounds and not overlapping)
    if valid_placement?(game, placed_coords) do
      placed_coords
    else
      nil
    end
  end

  @doc """
  Place a piece on the board at a calculated position based on power and player position.
  Power range: 0-100
  - 0-94: Place at calculated distance
  - 95-100: Place at furthest position
  """
  def place_piece(game, player_id, piece_coords, power) do
    placed_coords = calculate_placement(game, player_id, piece_coords, power)

    if placed_coords do
      player_key = player_key(player_id)
      player = Map.get(game, player_key)
      # Add placed piece to game state
      placed_piece = {player_id, placed_coords, player.color}
      %{game | placed_pieces: [placed_piece | game.placed_pieces]}
    else
      # Invalid placement, return game unchanged
      game
    end
  end

  defp get_throw_direction({x, y}) do
    max_coord = Board.size() - 1

    cond do
      # Top edge - throw down
      y == 0 and x > 0 and x < max_coord -> :down
      # Bottom edge - throw up
      y == max_coord and x > 0 and x < max_coord -> :up
      # Left edge - throw right
      x == 0 and y > 0 and y < max_coord -> :right
      # Right edge - throw left
      x == max_coord and y > 0 and y < max_coord -> :left
      # Top-left corner - throw diagonally down-right
      x == 0 and y == 0 -> :down_right
      # Top-right corner - throw diagonally down-left
      x == max_coord and y == 0 -> :down_left
      # Bottom-left corner - throw diagonally up-right
      x == 0 and y == max_coord -> :up_right
      # Bottom-right corner - throw diagonally up-left
      x == max_coord and y == max_coord -> :up_left
      # Default
      true -> :down
    end
  end

  defp calculate_throw_position({px, py}, direction, distance) do
    case direction do
      :down -> {px, py + distance}
      :up -> {px, py - distance}
      :right -> {px + distance, py}
      :left -> {px - distance, py}
      :down_right -> {px + distance, py + distance}
      :down_left -> {px - distance, py + distance}
      :up_right -> {px + distance, py - distance}
      :up_left -> {px - distance, py - distance}
    end
  end

  defp valid_placement?(game, coords) do
    # Check all coordinates are within bounds
    all_in_bounds = Enum.all?(coords, &Board.in_bounds?/1)

    # Check no overlap with existing pieces
    existing_coords = game.placed_pieces
      |> Enum.flat_map(fn {_player_id, piece_coords, _color} -> piece_coords end)
      |> MapSet.new()

    no_overlap = coords
      |> Enum.all?(fn coord -> not MapSet.member?(existing_coords, coord) end)

    all_in_bounds and no_overlap
  end

  defp player_key(1), do: :player1
  defp player_key(2), do: :player2

  defp get_other_player(game, 1), do: game.player2
  defp get_other_player(game, 2), do: game.player1
end
