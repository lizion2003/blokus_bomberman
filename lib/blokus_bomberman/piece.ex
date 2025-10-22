defmodule BlokusBomberman.Piece do
  @moduledoc """
  Defines all 21 Blokus pieces grouped by size (1-5 blocks).
  """

  @pieces %{
    # 1 block - Monomino
    mono: [{0, 0}],

    # 2 blocks - Domino
    domino: [{0, 0}, {1, 0}],

    # 3 blocks - Trominoes
    tri_i: [{0, 0}, {1, 0}, {2, 0}],
    tri_l: [{0, 0}, {0, 1}, {1, 0}],

    # 4 blocks - Tetrominoes
    tetra_i: [{0, 0}, {1, 0}, {2, 0}, {3, 0}],
    tetra_o: [{0, 0}, {1, 0}, {0, 1}, {1, 1}],
    tetra_t: [{0, 0}, {1, 0}, {2, 0}, {1, 1}],
    tetra_l: [{0, 0}, {0, 1}, {0, 2}, {1, 0}],
    tetra_z: [{0, 0}, {1, 0}, {1, 1}, {2, 1}],

    # 5 blocks - Pentominoes
    penta_f: [{1, 0}, {2, 0}, {0, 1}, {1, 1}, {1, 2}],
    penta_i: [{0, 0}, {1, 0}, {2, 0}, {3, 0}, {4, 0}],
    penta_l: [{0, 0}, {0, 1}, {0, 2}, {0, 3}, {1, 0}],
    penta_n: [{0, 1}, {1, 0}, {1, 1}, {2, 0}, {3, 0}],
    penta_p: [{0, 0}, {1, 0}, {0, 1}, {1, 1}, {0, 2}],
    penta_t: [{0, 0}, {1, 0}, {2, 0}, {1, 1}, {1, 2}],
    penta_u: [{0, 0}, {2, 0}, {0, 1}, {1, 1}, {2, 1}],
    penta_v: [{0, 0}, {0, 1}, {0, 2}, {1, 2}, {2, 2}],
    penta_w: [{0, 0}, {0, 1}, {1, 1}, {1, 2}, {2, 2}],
    penta_x: [{1, 0}, {0, 1}, {1, 1}, {2, 1}, {1, 2}],
    penta_y: [{0, 1}, {1, 0}, {1, 1}, {1, 2}, {1, 3}],
    penta_z: [{0, 0}, {1, 0}, {1, 1}, {1, 2}, {2, 2}]
  }

  @pieces_by_size %{
    1 => [:mono],
    2 => [:domino],
    3 => [:tri_i, :tri_l],
    4 => [:tetra_i, :tetra_o, :tetra_t, :tetra_l, :tetra_z],
    5 => [:penta_f, :penta_i, :penta_l, :penta_n, :penta_p, :penta_t,
          :penta_u, :penta_v, :penta_w, :penta_x, :penta_y, :penta_z]
  }

  def all_pieces, do: Map.keys(@pieces)

  def get_shape(piece_type), do: Map.get(@pieces, piece_type, [])

  def pieces_by_size(size), do: Map.get(@pieces_by_size, size, [])

  def all_sizes, do: [1, 2, 3, 4, 5]

  @doc """
  Rotate coordinates 90 degrees clockwise
  """
  def rotate(coords) do
    coords
    |> Enum.map(fn {x, y} -> {-y, x} end)
    |> normalize()
  end

  @doc """
  Flip coordinates horizontally (along Y-axis)
  """
  def flip_horizontal(coords) do
    coords
    |> Enum.map(fn {x, y} -> {-x, y} end)
    |> normalize()
  end

  @doc """
  Normalize coordinates so minimum is (0, 0)
  """
  def normalize(coords) do
    if Enum.empty?(coords) do
      []
    else
      min_x = coords |> Enum.map(&elem(&1, 0)) |> Enum.min()
      min_y = coords |> Enum.map(&elem(&1, 1)) |> Enum.min()

      coords
      |> Enum.map(fn {x, y} -> {x - min_x, y - min_y} end)
    end
  end

  @doc """
  Get bounding box dimensions
  """
  def get_bounds(coords) do
    if Enum.empty?(coords) do
      {0, 0}
    else
      max_x = coords |> Enum.map(&elem(&1, 0)) |> Enum.max()
      max_y = coords |> Enum.map(&elem(&1, 1)) |> Enum.max()
      {max_x + 1, max_y + 1}
    end
  end
end
