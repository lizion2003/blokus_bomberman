defmodule BlokusBomberman.Board do
  @moduledoc """
  Represents a 22x22 game board with 20x20 playable interior.
  Avatars can only move along the outer edges of the board.
  The interior 20x20 area is where pieces can be placed.
  """

  @size 22

  def size, do: @size

  @doc """
  Check if a position is on the board edge
  """
  def on_edge?({x, y}) do
    (x == 0 or x == @size - 1) or (y == 0 or y == @size - 1)
  end

  @doc """
  Check if a position is within board bounds
  """
  def in_bounds?({x, y}) do
    x >= 0 and x < @size and y >= 0 and y < @size
  end

  @doc """
  Check if a move from one edge position to another is valid
  (must stay on edge and be adjacent)
  """
  def valid_edge_move?({from_x, from_y}, {to_x, to_y}) do
    # Must be within bounds
    in_bounds?({to_x, to_y}) and
    # Must be on edge
    on_edge?({to_x, to_y}) and
    # Must be adjacent (Manhattan distance of 1)
    (abs(to_x - from_x) + abs(to_y - from_y)) == 1
  end

  @doc """
  Get starting positions for two players (opposite corners)
  """
  def initial_positions do
    %{
      player1: {0, 0},           # Top-left corner
      player2: {@size - 1, @size - 1}  # Bottom-right corner
    }
  end
end
