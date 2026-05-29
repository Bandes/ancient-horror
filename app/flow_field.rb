module FlowField
  # BFS from goal outward. Returns came_from hash:
  #   [col, row] => [next_col, next_row]  (the step toward goal)
  # Nil value at goal cell itself.
  #
  # clearance: tiles within this many steps of a wall are treated as impassable.
  # Use clearance=1 for large boids that can't fit through 1-tile-wide passages.
  def self.build(cave_grid, goal_col, goal_row, clearance: 0)
    goal_col = goal_col.clamp(0, Cave::COLS - 1)
    goal_row = goal_row.clamp(0, Cave::ROWS - 1)
    goal = [goal_col, goal_row]

    frontier  = [goal]
    came_from = { goal => nil }

    until frontier.empty?
      col, row = frontier.shift
      # Cardinals first so they get shortest-path priority over diagonals
      [[-1, 0], [1, 0], [0, -1], [0, 1]].each do |dc, dr|
        nc = col + dc; nr = row + dr
        n  = [nc, nr]
        next if came_from.key?(n)
        next unless passable?(cave_grid, nc, nr, clearance)
        came_from[n] = [col, row]
        frontier << n
      end
      # Diagonals — only when both shared cardinal neighbours are open (no corner cutting)
      [[-1, -1], [1, -1], [-1, 1], [1, 1]].each do |dc, dr|
        nc = col + dc; nr = row + dr
        n  = [nc, nr]
        next if came_from.key?(n)
        next unless passable?(cave_grid, nc, nr, clearance)
        next unless passable?(cave_grid, col + dc, row, clearance)
        next unless passable?(cave_grid, col, row + dr, clearance)
        came_from[n] = [col, row]
        frontier << n
      end
    end

    came_from
  end

  def self.passable?(cave_grid, col, row, clearance)
    return false if Cave.wall?(cave_grid, col, row)
    return true  if clearance == 0
    (-clearance..clearance).each do |dc|
      (-clearance..clearance).each do |dr|
        return false if Cave.wall?(cave_grid, col + dc, row + dr)
      end
    end
    true
  end

  # Unit [dx, dy] world-space direction from (wx,wy) toward goal.
  # Returns [0, 0] when no path or boid already at goal cell.
  def self.direction(field, wx, wy)
    return [0.0, 0.0] unless field

    col = wx.idiv(Cave::TILE_SIZE)
    row = wy.idiv(Cave::TILE_SIZE)
    bc  = [col, row]

    # Boid may be in a wall tile (border or interior) — not in field.
    # Walk outward until we find a reachable cell.
    unless field.key?(bc)
      bc = [[col,row-1],[col,row+1],[col-1,row],[col+1,row],
            [col-1,row-1],[col+1,row-1],[col-1,row+1],[col+1,row+1]].find { |c| field.key?(c) }
      return [0.0, 0.0] unless bc
    end

    next_cell = field[bc]
    return [0.0, 0.0] unless next_cell

    nc, nr = next_cell
    tx = nc * Cave::TILE_SIZE + Cave::TILE_SIZE * 0.5
    ty = nr * Cave::TILE_SIZE + Cave::TILE_SIZE * 0.5
    dx = tx - wx
    dy = ty - wy
    mag = Math.sqrt(dx * dx + dy * dy)
    return [0.0, 0.0] if mag < 0.001

    [dx / mag, dy / mag]
  end
end
