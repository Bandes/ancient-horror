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
    'sprites/environment/tiles/tile_20.png',
    'sprites/environment/tiles/tile_20.png',
    'sprites/environment/tiles/tile_20.png',
    'sprites/environment/tiles/tile_14.png',
    'sprites/environment/tiles/tile_16.png',
    'sprites/environment/tiles/tile_17.png',
    'sprites/environment/tiles/tile_19.png',
    'sprites/environment/tiles/tile_21.png',
    'sprites/environment/tiles/tile_22.png',
  ].freeze

  GRATE_TILE = 'sprites/environment/tiles/tile_13.png'

  WALL_TILES = [
    'sprites/environment/tiles/tile_9.png',
    'sprites/environment/tiles/tile_10.png',
    'sprites/environment/tiles/tile_10.png',
    'sprites/environment/tiles/tile_12.png',
  ].freeze

  PROP_POOL = [
    { path: 'sprites/environment/objects/skeleton_1.png',      w: 32, h: 32, cr: 10 },
    { path: 'sprites/environment/objects/skeleton_2.png',      w: 32, h: 32, cr: 10 },
    { path: 'sprites/environment/objects/barrel_1.png',    w: 28, h: 32, cr: 13 },
    { path: 'sprites/environment/objects/barrel_2.png',    w: 28, h: 32, cr: 13 },
    { path: 'sprites/environment/objects/barrel_3.png',    w: 28, h: 32, cr: 13 },
    { path: 'sprites/environment/objects/pot_1.png',       w: 24, h: 28, cr: 11 },
    { path: 'sprites/environment/objects/pot_2.png',       w: 24, h: 28, cr: 11 },
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
    20.times do
      result = try_generate
      return result if result
    end
    fallback_generate
  end

  # Interior column range split into thirds for wall placement
  INTERIOR_C1 = 3;  INTERIOR_C2 = 7   # left zone
  INTERIOR_C3 = 8;  INTERIOR_C4 = 12  # mid zone
  INTERIOR_C5 = 13; INTERIOR_C6 = 17  # right zone
  INTERIOR_R1 = 2;  INTERIOR_R2 = 8   # row bounds

  def self.try_generate
    grid = Array.new(ROWS) do |r|
      Array.new(COLS) do |c|
        (r == 0 || r == ROWS - 1 || c == 0 || c == COLS - 1) ? :wall : :floor
      end
    end

    # Place one wall in each zone — 3 total.
    # Pick 2 or 3 zones randomly so the layout varies run-to-run.
    zones = [[INTERIOR_C1, INTERIOR_C2],
             [INTERIOR_C3, INTERIOR_C4],
             [INTERIOR_C5, INTERIOR_C6]].shuffle
    zone_count = 2 + Numeric.rand(2)   # 2 or 3
    i = 0
    while i < zone_count
      place_wall_segment(grid, zones[i][0], zones[i][1])
      i += 1
    end

    # Vary spawn/altar rows so travel paths differ each run
    sc = 2;          sr = 2 + Numeric.rand(ROWS - 4)   # rows 2..ROWS-3
    ac = COLS - 3;   ar = 2 + Numeric.rand(ROWS - 4)

    # 0-2 extra short stubs for interior obstacle variety
    Numeric.rand(3).times { place_stub(grid, sc, sr, ac, ar) }

    clear_around(grid, sc, sr)
    clear_around(grid, ac, ar)

    { grid: grid, altar_col: ac, altar_row: ar, spawn_col: sc, spawn_row: sr }
  end

  # Carve a short wall segment (horizontal or vertical) somewhere in the zone.
  # Leaves at least one tile of gap at each end so flow is never fully blocked.
  def self.place_wall_segment(grid, col_min, col_max)
    if Numeric.rand < 0.5
      # Horizontal wall: pick a row, span most of the zone width, leave 1-tile gap at random end
      row    = INTERIOR_R1 + Numeric.rand(INTERIOR_R2 - INTERIOR_R1 + 1)
      length = col_max - col_min - 1   # leave 1 tile open
      gap_at_start = Numeric.rand < 0.5
      c_start = gap_at_start ? col_min + 1 : col_min
      c = c_start
      while c < c_start + length && c <= col_max && c.between?(1, COLS - 2)
        grid[row][c] = :wall if row.between?(1, ROWS - 2)
        c += 1
      end
    else
      # Vertical wall: full interior height minus 1-tile gap at random end
      col    = col_min + Numeric.rand(col_max - col_min + 1)
      length = INTERIOR_R2 - INTERIOR_R1 - 1
      gap_at_bottom = Numeric.rand < 0.5
      r_start = gap_at_bottom ? INTERIOR_R1 + 1 : INTERIOR_R1
      r = r_start
      while r < r_start + length && r <= INTERIOR_R2 && r.between?(1, ROWS - 2)
        grid[r][col] = :wall if col.between?(1, COLS - 2)
        r += 1
      end
    end
  end

  # Place a short 2-3 tile wall stub anywhere in the interior, clear of spawn/altar.
  # Used for mid-arena obstacles; length is short enough to never fully block flow.
  def self.place_stub(grid, sc, sr, ac, ar)
    20.times do
      col = 3 + Numeric.rand(COLS - 6)
      row = INTERIOR_R1 + Numeric.rand(INTERIOR_R2 - INTERIOR_R1 + 1)
      next if (col - sc).abs < 3 && (row - sr).abs < 3
      next if (col - ac).abs < 3 && (row - ar).abs < 3
      len = 2 + Numeric.rand(2)
      if Numeric.rand < 0.5
        len.times { |i| grid[row][col + i] = :wall if (col + i).between?(1, COLS - 2) }
      else
        len.times { |i| grid[row + i][col] = :wall if (row + i).between?(1, ROWS - 2) }
      end
      return
    end
  end

  def self.pick_far_cell(grid, col_min, col_max, row_min, row_max)
    candidates = []
    r = row_min
    while r <= row_max
      c = col_min
      while c <= col_max
        candidates << [c, r] unless wall?(grid, c, r)
        c += 1
      end
      r += 1
    end
    return [nil, nil] if candidates.empty?
    candidates[Numeric.rand(candidates.length)]
  end

  def self.clear_around(grid, c, r)
    [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]].each do |dc, dr|
      nc = c + dc; nr = r + dr
      grid[nr][nc] = :floor if nr.between?(1, ROWS - 2) && nc.between?(1, COLS - 2)
    end
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
    # A few simple interior walls even in fallback
    r = ROWS / 2
    c = 5
    while c <= 7; grid[r][c] = :wall; c += 1; end
    c = COLS - 8
    while c <= COLS - 6; grid[r + 2][c] = :wall; c += 1; end
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
    if Numeric.rand < 0.5
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

  # Build a list of thin AABB collision rects that exactly match the stone-face
  # strips drawn by wall_tile. Border tiles are full-tile rects; interior face
  # tiles get a STONE_FACE_PX-deep rect on the floor side; corner-only tiles get
  # a STONE_FACE_PX square at the relevant corner.
  def self.generate_wall_colliders(grid)
    rects = []
    ROWS.times do |r|
      COLS.times do |c|
        next unless grid[r][c] == :wall

        tx = c * TILE_SIZE
        ty = r * TILE_SIZE

        # Border tiles: collision handled by the hard clamp in each entity's
        # update method (STONE_FACE_PX + r from screen edge). Skip them here.
        next if c == 0 || c == COLS - 1 || r == 0 || r == ROWS - 1

        fs = r > 0        && grid[r - 1][c] != :wall
        fn = r < ROWS - 1 && grid[r + 1][c] != :wall
        fe = c < COLS - 1 && grid[r][c + 1] != :wall
        fw = c > 0        && grid[r][c - 1] != :wall

        # Mirror blocks_movement? priority (s > n > e > w) — one rect per tile.
        if fs
          rects << { x: tx, y: ty, w: TILE_SIZE, h: STONE_FACE_PX }
        elsif fn
          rects << { x: tx, y: ty + TILE_SIZE - STONE_FACE_PX, w: TILE_SIZE, h: STONE_FACE_PX }
        elsif fe
          rects << { x: tx + TILE_SIZE - STONE_FACE_PX, y: ty, w: STONE_FACE_PX, h: TILE_SIZE }
        elsif fw
          rects << { x: tx, y: ty, w: STONE_FACE_PX, h: TILE_SIZE }
        else
          fse = c < COLS-1 && r > 0      && grid[r-1][c+1] != :wall
          fsw = c > 0      && r > 0      && grid[r-1][c-1] != :wall
          fne = c < COLS-1 && r < ROWS-1 && grid[r+1][c+1] != :wall
          fnw = c > 0      && r < ROWS-1 && grid[r+1][c-1] != :wall

          if fse
            rects << { x: tx + TILE_SIZE - STONE_FACE_PX, y: ty,                             w: STONE_FACE_PX, h: STONE_FACE_PX }
          elsif fsw
            rects << { x: tx,                             y: ty,                             w: STONE_FACE_PX, h: STONE_FACE_PX }
          elsif fne
            rects << { x: tx + TILE_SIZE - STONE_FACE_PX, y: ty + TILE_SIZE - STONE_FACE_PX, w: STONE_FACE_PX, h: STONE_FACE_PX }
          elsif fnw
            rects << { x: tx,                             y: ty + TILE_SIZE - STONE_FACE_PX, w: STONE_FACE_PX, h: STONE_FACE_PX }
          end
        end
      end
    end
    rects
  end

  # Circle vs list of AABB wall rects. Returns true if any rect overlaps.
  def self.circle_blocks?(wall_rects, cx, cy, r)
    r2 = r * r
    wall_rects.any? do |rect|
      nx = cx.clamp(rect[:x], rect[:x] + rect[:w])
      ny = cy.clamp(rect[:y], rect[:y] + rect[:h])
      dx = cx - nx; dy = cy - ny
      dx * dx + dy * dy < r2
    end
  end

  def self.wall?(grid, col, row)
    return true if col < 0 || col >= COLS || row < 0 || row >= ROWS
    grid[row][col] == :wall
  end

  def self.wall_at_px?(grid, px, py)
    wall?(grid, px.idiv(TILE_SIZE), py.idiv(TILE_SIZE))
  end

  # Edge wall tiles render a thin stone-brick "face" strip on the side OPPOSITE
  # the adjacent floor; rest of tile is dark floor-bleed and walkable.
  STONE_FACE_PX = 20

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

    # Interior wall renders bricks on side TOWARD floor neighbor (see wall_tile
    # precedence: s,n,e,w). Block only the brick strip; rest is walkable bleed.
    if fs
      ly < STONE_FACE_PX
    elsif fn
      ly >= TILE_SIZE - STONE_FACE_PX
    elsif fe
      lx >= TILE_SIZE - STONE_FACE_PX
    elsif fw
      lx < STONE_FACE_PX
    else
      true
    end
  end

  def self.walkable_pixel?(grid, px, py)
    !wall_at_px?(grid, px, py)
  end

  # Circle vs walls test — samples 8 points around perimeter so diagonal corners
  # cannot slip through (single-axis sampling misses interior corners).
  def self.blocks_circle?(grid, cx, cy, r)
    return true if blocks_movement?(grid, (cx + r).to_i, cy.to_i)
    return true if blocks_movement?(grid, (cx - r).to_i, cy.to_i)
    return true if blocks_movement?(grid, cx.to_i, (cy + r).to_i)
    return true if blocks_movement?(grid, cx.to_i, (cy - r).to_i)
    s = r * 0.7071
    return true if blocks_movement?(grid, (cx + s).to_i, (cy + s).to_i)
    return true if blocks_movement?(grid, (cx - s).to_i, (cy + s).to_i)
    return true if blocks_movement?(grid, (cx + s).to_i, (cy - s).to_i)
    return true if blocks_movement?(grid, (cx - s).to_i, (cy - s).to_i)
    false
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
  EDGE_S  = ['sprites/environment/tiles/tile_25.png', 'sprites/environment/tiles/tile_26.png'].freeze
  EDGE_N  = ['sprites/environment/tiles/tile_36.png', 'sprites/environment/tiles/tile_37.png'].freeze
  EDGE_E  = 'sprites/environment/tiles/tile_29.png'
  EDGE_W  = 'sprites/environment/tiles/tile_33.png'
  CORNER_SE = 'sprites/environment/tiles/tile_24.png'
  CORNER_SW = 'sprites/environment/tiles/tile_28.png'
  CORNER_NE = 'sprites/environment/tiles/tile_34.png'
  CORNER_NW = 'sprites/environment/tiles/tile_38.png'

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

  OUTER_CORNER_NW = 'sprites/environment/tiles/tile_80.png'
  OUTER_CORNER_NE = 'sprites/environment/tiles/tile_81.png'
  OUTER_CORNER_SW = 'sprites/environment/tiles/tile_82.png'
  OUTER_CORNER_SE = 'sprites/environment/tiles/tile_83.png'

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
