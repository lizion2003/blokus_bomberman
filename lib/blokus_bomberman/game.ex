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
      }
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

  defp player_key(1), do: :player1
  defp player_key(2), do: :player2

  defp get_other_player(game, 1), do: game.player2
  defp get_other_player(game, 2), do: game.player1
end
