module Cave
  TILE_SIZE = 64
  COLS      = 1280.idiv(TILE_SIZE)  # 20
  ROWS      =  720.idiv(TILE_SIZE)  # 11

  MERGE_RADIUS    = 70
  ALTAR_RADIUS    = 80
  MERGE_THRESHOLD = 5

  # Pure floor tiles — no wall components, safe to tile anywhere
  FLOOR_TILES = [
    'sprites/environment/tiles/Tile (20).png',
    'sprites/environment/tiles/Tile (20).png',
    'sprites/environment/tiles/Tile (20).png',
    'sprites/environment/tiles/Tile (14).png',
    'sprites/environment/tiles/Tile (16).png',
    'sprites/environment/tiles/Tile (17).png',
    'sprites/environment/tiles/Tile (19).png',
    'sprites/environment/tiles/Tile (21).png',
    'sprites/environment/tiles/Tile (22).png',
  ].freeze

  GRATE_TILE = 'sprites/environment/tiles/Tile (13).png'

  # Pure wall tiles — dark spiral stone
  WALL_TILES = [
    'sprites/environment/tiles/Tile (9).png',
    'sprites/environment/tiles/Tile (10).png',
    'sprites/environment/tiles/Tile (10).png',
    'sprites/environment/tiles/Tile (12).png',
  ].freeze

  def self.generate
    10.times do
      result = try_generate
      return result if result
    end
    fallback_generate
  end

  def self.try_generate
    grid = Array.new(ROWS) { Array.new(COLS, :wall) }

    # Two large chambers, each filling most of their half
    chamber_w = 7 + rand(3)                           # 7-9
    chamber_w = [chamber_w, COLS.idiv(2) - 1].min
    chamber_h = ROWS - 2                               # full interior height = 9

    # Left chamber flush to left border
    carve_rect(grid, 1, 1, chamber_w, chamber_h)

    # Right chamber flush to right border
    rx = COLS - 1 - chamber_w
    carve_rect(grid, rx, 1, chamber_w, chamber_h)

    # Carve 2-3 corridors through the gap at different row heights
    gap_left  = 1 + chamber_w
    gap_right = rx - 1
    rows_carved = []
    (2 + rand(2)).times do
      50.times do
        r = 1 + rand(ROWS - 2)
        next if rows_carved.any? { |used| (used - r).abs < 2 }
        carve_h(grid, r, gap_left, gap_right + 1)
        rows_carved << r
        break
      end
    end
    # Guarantee at least one corridor
    carve_h(grid, ROWS.idiv(2), gap_left, gap_right + 1) if rows_carved.empty?

    sc = 1 + chamber_w.idiv(2)
    sr = ROWS.idiv(2)
    ac = rx + chamber_w.idiv(2)
    ar = ROWS.idiv(2)

    { grid: grid, altar_col: ac, altar_row: ar, spawn_col: sc, spawn_row: sr }
  end

  def self.connect_rooms(grid, rooms)
    connected   = [rooms[0]]
    unconnected = rooms[1..-1].dup

    until unconnected.empty?
      best_dist = Float::INFINITY
      best_c = best_u = nil

      connected.each do |c_room|
        unconnected.each do |u_room|
          cx, cy = center(c_room)
          ux, uy = center(u_room)
          d = (cx - ux).abs + (cy - uy).abs
          if d < best_dist
            best_dist = d; best_c = c_room; best_u = u_room
          end
        end
      end

      carve_corridor(grid, center(best_c), center(best_u))
      connected << best_u
      unconnected = unconnected - [best_u]
    end
  end

  def self.fallback_generate
    grid = Array.new(ROWS) do |r|
      Array.new(COLS) { |c| (r == 0 || r == ROWS - 1 || c == 0 || c == COLS - 1) ? :wall : :floor }
    end
    { grid: grid, altar_col: COLS - 3, altar_row: ROWS / 2, spawn_col: 2, spawn_row: ROWS / 2 }
  end

  def self.overlaps?(a, b, margin: 0)
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    ax - margin <= bx + bw && ax + aw + margin >= bx &&
    ay - margin <= by + bh && ay + ah + margin >= by
  end

  def self.carve_rect(grid, x, y, w, h)
    h.times do |dy|
      w.times do |dx|
        r = y + dy; c = x + dx
        grid[r][c] = :floor if r.between?(1, ROWS - 2) && c.between?(1, COLS - 2)
      end
    end
  end

  def self.center(room)
    x, y, w, h = room
    [x + w.idiv(2), y + h.idiv(2)]
  end

  def self.carve_corridor(grid, from_pos, to_pos)
    fx, fy = from_pos; tx, ty = to_pos
    if rand < 0.5
      carve_h(grid, fy, [fx, tx].min, [fx, tx].max)
      carve_v(grid, tx, [fy, ty].min, [fy, ty].max)
    else
      carve_v(grid, fx, [fy, ty].min, [fy, ty].max)
      carve_h(grid, ty, [fx, tx].min, [fx, tx].max)
    end
  end

  def self.carve_h(grid, row, c1, c2)
    [row, row + 1].each do |r|
      next unless r.between?(1, ROWS - 2)
      (c1..c2).each { |c| grid[r][c] = :floor if c.between?(1, COLS - 2) }
    end
  end

  def self.carve_v(grid, col, r1, r2)
    [col, col + 1].each do |c|
      next unless c.between?(1, COLS - 2)
      (r1..r2).each { |r| grid[r][c] = :floor if r.between?(1, ROWS - 2) }
    end
  end

  def self.flood_fill(grid, start_col, start_row)
    visited = {}
    queue   = [[start_col, start_row]]
    until queue.empty?
      col, row = queue.shift
      next if visited[[col, row]] || wall?(grid, col, row)
      visited[[col, row]] = true
      [[-1, 0], [1, 0], [0, -1], [0, 1]].each do |dc, dr|
        nc = col + dc; nr = row + dr
        queue << [nc, nr] unless visited[[nc, nr]]
      end
    end
    visited
  end

  def self.wall?(grid, col, row)
    return true if col < 0 || col >= COLS || row < 0 || row >= ROWS
    grid[row][col] == :wall
  end

  def self.wall_at_px?(grid, px, py)
    wall?(grid, px.idiv(TILE_SIZE), py.idiv(TILE_SIZE))
  end

  def self.walkable_pixel?(grid, px, py)
    !wall_at_px?(grid, px, py)
  end

  def self.tile_center(col, row)
    { x: col * TILE_SIZE + TILE_SIZE / 2, y: row * TILE_SIZE + TILE_SIZE / 2 }
  end

  def self.floor_cells(grid)
    cells = []
    ROWS.times { |r| COLS.times { |c| cells << [c, r] unless wall?(grid, c, r) } }
    cells
  end

  def self.render(grid)
    ROWS.times.flat_map do |r|
      COLS.times.map do |c|
        hash = c * 7 + r * 13
        path = if grid[r][c] == :wall
          WALL_TILES[hash % WALL_TILES.length]
        elsif hash % 18 == 0
          GRATE_TILE
        else
          FLOOR_TILES[(c * 11 + r * 7) % FLOOR_TILES.length]
        end
        { x: c * TILE_SIZE, y: r * TILE_SIZE, w: TILE_SIZE, h: TILE_SIZE, path: path, blendmode_enum: 1 }
      end
    end
  end
end
