module Cave
  TILE_SIZE = 64
  COLS      = 1280.idiv(TILE_SIZE)  # 20
  ROWS      =  720.idiv(TILE_SIZE)  # 11

  MERGE_RADIUS    = 70
  ALTAR_RADIUS    = 80
  MERGE_THRESHOLD_SMALL  = 8
  MERGE_THRESHOLD_MEDIUM = 4

  # Pure floor tiles — no wall components, safe to tile anywhere
  FLOOR_TILES = [
    'sprites/environment/tiles/tile_(_20_).png',
    'sprites/environment/tiles/tile_(_20_).png',
    'sprites/environment/tiles/tile_(_20_).png',
    'sprites/environment/tiles/tile_(_14_).png',
    'sprites/environment/tiles/tile_(_16_).png',
    'sprites/environment/tiles/tile_(_17_).png',
    'sprites/environment/tiles/tile_(_19_).png',
    'sprites/environment/tiles/tile_(_21_).png',
    'sprites/environment/tiles/tile_(_22_).png',
  ].freeze

  GRATE_TILE = 'sprites/environment/tiles/tile_(_13_).png'

  WALL_TILES = [
    'sprites/environment/tiles/tile_(_9_).png',
    'sprites/environment/tiles/tile_(_10_).png',
    'sprites/environment/tiles/tile_(_10_).png',
    'sprites/environment/tiles/tile_(_12_).png',
  ].freeze

  PROP_POOL = [
    { path: 'sprites/environment/objects/skeleton_1.png',      w: 32, h: 32, cr: 10 },
    { path: 'sprites/environment/objects/skeleton_2.png',      w: 32, h: 32, cr: 10 },
    { path: 'sprites/environment/objects/barrel_(_1_).png',    w: 28, h: 32, cr: 13 },
    { path: 'sprites/environment/objects/barrel_(_2_).png',    w: 28, h: 32, cr: 13 },
    { path: 'sprites/environment/objects/barrel_(_3_).png',    w: 28, h: 32, cr: 13 },
    { path: 'sprites/environment/objects/pot_(_1_).png',       w: 24, h: 28, cr: 11 },
    { path: 'sprites/environment/objects/pot_(_2_).png',       w: 24, h: 28, cr: 11 },
    { path: 'sprites/environment/objects/crate.png',           w: 30, h: 30, cr: 13 },
  ].freeze

  PROP_COUNT   = 14
  PROP_MIN_GAP = 100   # px between prop centers — keeps corridors clear for large shoggoths

  def self.generate_props(grid, exclude_cells)
    cells = floor_cells(grid).reject { |c, r| exclude_cells.any? { |ec, er| ec == c && er == r } }
    placed = []
    cells.shuffle.each do |col, row|
      break if placed.length >= PROP_COUNT
      cx = col * TILE_SIZE + TILE_SIZE / 2
      cy = row * TILE_SIZE + TILE_SIZE / 2
      too_close = placed.any? { |p|
        dx = p[:cx] - cx; dy = p[:cy] - cy
        dx * dx + dy * dy < PROP_MIN_GAP * PROP_MIN_GAP
      }
      placed << { col: col, row: row, cx: cx, cy: cy } unless too_close
    end
    placed.map do |slot|
      col = slot[:col]; row = slot[:row]; cx = slot[:cx]; cy = slot[:cy]
      prop = PROP_POOL[(col * 7 + row * 13) % PROP_POOL.length]
      cx = col * TILE_SIZE + TILE_SIZE / 2
      cy = row * TILE_SIZE + TILE_SIZE / 2
      { sprite: { x: cx - prop[:w] / 2, y: cy - prop[:h] / 2,
                  w: prop[:w], h: prop[:h],
                  path: prop[:path], blendmode_enum: 1 },
        cx: cx.to_f, cy: cy.to_f, cr: prop[:cr] }
    end
  end

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

  # Like wall_at_px? but accounts for the walkable floor-bleed strip on edge tiles.
  WALL_BLEED = 20

  def self.blocks_movement?(grid, px, py)
    col = px.idiv(TILE_SIZE)
    row = py.idiv(TILE_SIZE)
    return true  if col < 0 || col >= COLS || row < 0 || row >= ROWS
    return false unless grid[row][col] == :wall
    return true  if col == 0 || col == COLS - 1 || row == 0 || row == ROWS - 1

    lx = px - col * TILE_SIZE   # 0 = west edge, 63 = east edge
    ly = py - row * TILE_SIZE   # 0 = south edge, 63 = north edge

    fs = row > 0        && grid[row - 1][col] != :wall
    fn = row < ROWS - 1 && grid[row + 1][col] != :wall
    fe = col < COLS - 1 && grid[row][col + 1] != :wall
    fw = col > 0        && grid[row][col - 1] != :wall

    if fs
      ly >= WALL_BLEED                  # south bleed: bottom strip walkable
    elsif fn
      ly < TILE_SIZE - WALL_BLEED      # north bleed: top strip walkable
    elsif fe
      lx < TILE_SIZE - WALL_BLEED      # east bleed: right strip walkable
    elsif fw
      lx >= WALL_BLEED                  # west bleed: left strip walkable
    else
      true
    end
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

  # Edge/corner wall tiles keyed by which orthogonal/diagonal neighbors are floor
  EDGE_S  = ['sprites/environment/tiles/tile_(_25_).png', 'sprites/environment/tiles/tile_(_26_).png'].freeze
  EDGE_N  = ['sprites/environment/tiles/tile_(_36_).png', 'sprites/environment/tiles/tile_(_37_).png'].freeze
  EDGE_E  = 'sprites/environment/tiles/tile_(_29_).png'
  EDGE_W  = 'sprites/environment/tiles/tile_(_33_).png'
  CORNER_SE = 'sprites/environment/tiles/tile_(_24_).png'
  CORNER_SW = 'sprites/environment/tiles/tile_(_28_).png'
  CORNER_NE = 'sprites/environment/tiles/tile_(_34_).png'
  CORNER_NW = 'sprites/environment/tiles/tile_(_38_).png'

  def self.render(grid)
    ROWS.times.flat_map do |r|
      COLS.times.map do |c|
        hash = c * 7 + r * 13
        path = if grid[r][c] == :wall
          wall_tile(grid, c, r, hash)
        elsif hash % 18 == 0
          GRATE_TILE
        else
          FLOOR_TILES[(c * 11 + r * 7) % FLOOR_TILES.length]
        end
        { x: c * TILE_SIZE, y: r * TILE_SIZE, w: TILE_SIZE, h: TILE_SIZE, path: path, blendmode_enum: 1 }
      end
    end
  end

  OUTER_CORNER_NW = 'sprites/environment/tiles/tile_(_80_).png'
  OUTER_CORNER_NE = 'sprites/environment/tiles/tile_(_81_).png'
  OUTER_CORNER_SW = 'sprites/environment/tiles/tile_(_82_).png'
  OUTER_CORNER_SE = 'sprites/environment/tiles/tile_(_83_).png'

  def self.wall_tile(grid, c, r, hash)
    floor_s  = !wall?(grid, c,   r - 1)
    floor_n  = !wall?(grid, c,   r + 1)
    floor_e  = !wall?(grid, c + 1, r)
    floor_w  = !wall?(grid, c - 1, r)
    floor_se = !wall?(grid, c + 1, r - 1)
    floor_sw = !wall?(grid, c - 1, r - 1)
    floor_ne = !wall?(grid, c + 1, r + 1)
    floor_nw = !wall?(grid, c - 1, r + 1)

    outer = (c == 0 || c == COLS - 1 || r == 0 || r == ROWS - 1)

    if outer
      # Screen corners get two-sided stone tiles
      return OUTER_CORNER_NW if r == ROWS - 1 && c == 0
      return OUTER_CORNER_NE if r == ROWS - 1 && c == COLS - 1
      return OUTER_CORNER_SW if r == 0        && c == 0
      return OUTER_CORNER_SE if r == 0        && c == COLS - 1

      # Other border cells: stone face points outward; invert edge direction
      if floor_s then return EDGE_N[hash % EDGE_N.length]
      elsif floor_n then return EDGE_S[hash % EDGE_S.length]
      elsif floor_e then return EDGE_W
      elsif floor_w then return EDGE_E
      end

      # No orthogonal floor on outer border: show stone face on the exposed side
      return EDGE_N[hash % EDGE_N.length] if r == ROWS - 1
      return EDGE_S[hash % EDGE_S.length] if r == 0
      return EDGE_W if c == 0
      return EDGE_E
    end

    # Interior walls
    if floor_s
      EDGE_S[hash % EDGE_S.length]
    elsif floor_n
      EDGE_N[hash % EDGE_N.length]
    elsif floor_e
      EDGE_E
    elsif floor_w
      EDGE_W
    elsif floor_se
      CORNER_SE
    elsif floor_sw
      CORNER_SW
    elsif floor_ne
      CORNER_NE
    elsif floor_nw
      CORNER_NW
    else
      WALL_TILES[hash % WALL_TILES.length]
    end
  end
end
