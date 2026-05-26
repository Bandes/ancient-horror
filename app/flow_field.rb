module FlowField
  # BFS from goal outward. Returns came_from hash:
  #   [col, row] => [next_col, next_row]  (the step toward goal)
  # Nil value at goal cell itself.
  def self.build(cave_grid, goal_col, goal_row)
    goal_col = goal_col.clamp(0, Cave::COLS - 1)
    goal_row = goal_row.clamp(0, Cave::ROWS - 1)
    goal = [goal_col, goal_row]

    frontier  = [goal]
    came_from = { goal => nil }

    until frontier.empty?
      col, row = frontier.shift
      [[-1, 0], [1, 0], [0, -1], [0, 1]].each do |dc, dr|
        nc = col + dc
        nr = row + dr
        n  = [nc, nr]
        next if came_from.key?(n)
        next if Cave.wall?(cave_grid, nc, nr)
        came_from[n] = [col, row]
        frontier << n
      end
    end

    came_from
  end

  # Unit [dx, dy] world-space direction from (wx,wy) toward goal.
  # Returns [0, 0] when no path or boid already at goal cell.
  def self.direction(field, wx, wy)
    return [0.0, 0.0] unless field

    bc        = [wx.idiv(Cave::TILE_SIZE), wy.idiv(Cave::TILE_SIZE)]
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
