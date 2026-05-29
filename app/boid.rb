class Boid
  TIER_SCALE = { 1 => 0.3, 2 => 0.85, 3 => 1.3 }.freeze
  TIER_R     = { 1 => 9,   2 => 22,   3 => 34  }.freeze

  attr_accessor :x, :y, :vx, :vy,
                :bias_x, :bias_y,
                :wander_angle,
                :speed_mult,
                :speed_target,
                :impulse_cooldown,
                :spawn_timer,
                :personality,
                :tier

  def initialize(x:, y:, vx:, vy:, bias_x:, bias_y:, animator:, personality:, tier: 1)
    @x = x.to_f; @y = y.to_f
    @vx = vx.to_f; @vy = vy.to_f
    @bias_x = bias_x.to_f; @bias_y = bias_y.to_f
    @wander_angle     = Numeric.rand * Math::PI * 2
    @speed_mult       = 1.0
    @speed_target     = 1.0
    @impulse_cooldown = Numeric.rand(120)
    @spawn_timer      = Numeric.rand(300)
    @personality      = personality
    @animator         = animator
    @tier             = tier
  end

  def collision_r
    TIER_R[@tier]
  end

  def render(tick_count)
    s = @animator.sprite(tick_count, anchor_x: @x, anchor_y: @y, scale: TIER_SCALE[@tier])
    s[:flip_horizontally] = @vx < 0
    s
  end

  # Returns [ax, ay] — net steering acceleration for this tick.
  def accelerate(world, boids, self_index)
    ax = ay = 0.0
    fx, fy = flocking_force(boids, self_index)
    ax += fx; ay += fy

    bx, by = border_force
    ax += bx; ay += by

    wx, wy = wall_force(world.wall_rects)
    ax += wx; ay += wy

    target = find_target(world)

    wax, way = advance_motion_force(target[:near_idol])
    ax += wax; ay += way

    sx, sy = seek_force(target)
    ax += sx; ay += sy

    if @tier < 3
      hx, hy = hunter_flee_force(world.hunters)
      ax += hx; ay += hy

      px, py = player_lure_force(world)
      ax += px; ay += py
    end

    [ax, ay]
  end

  # Velocity clamp + position integrate. Caller resolves walls/collisions after.
  def integrate(speed_boost)
    effective_max = Flock::MAX_SPEED * @personality[:speed_scale] * @speed_mult * speed_boost
    effective_min = Flock::MIN_SPEED * @personality[:speed_scale] * @speed_mult * speed_boost
    sp = Math.sqrt(@vx * @vx + @vy * @vy)
    if sp > effective_max
      @vx = @vx / sp * effective_max
      @vy = @vy / sp * effective_max
    elsif sp < effective_min && sp > 0.0001
      @vx = @vx / sp * effective_min
      @vy = @vy / sp * effective_min
    end
    @x += @vx
    @y += @vy
  end

  private

  def flocking_force(boids, self_index)
    sep_x = sep_y = ali_x = ali_y = coh_x = coh_y = 0.0
    n_neighbors = n_sep = 0
    perception_sq = Flock::PERCEPTION * Flock::PERCEPTION
    sep_sq        = Flock::SEPARATION_R * Flock::SEPARATION_R

    boids.each_with_index do |o, j|
      next if j == self_index
      dx = o.x - @x
      dy = o.y - @y
      d2 = dx * dx + dy * dy
      next if d2 > perception_sq || d2 < 0.0001

      n_neighbors += 1
      ali_x += o.vx; ali_y += o.vy
      coh_x += @x + dx; coh_y += @y + dy
      next unless d2 < sep_sq

      sep_x -= dx / d2; sep_y -= dy / d2
      n_sep += 1
    end

    ax = ay = 0.0
    if n_neighbors > 0
      ali_x /= n_neighbors; ali_y /= n_neighbors
      sx, sy = Flock.steer_to(ali_x, ali_y, @vx, @vy)
      ax += sx * Flock::W_ALIGN; ay += sy * Flock::W_ALIGN
      coh_x /= n_neighbors; coh_y /= n_neighbors
      sx, sy = Flock.steer_to(coh_x - @x, coh_y - @y, @vx, @vy)
      ax += sx * Flock::W_COH; ay += sy * Flock::W_COH
    end
    if n_sep > 0
      sep_x /= n_sep; sep_y /= n_sep
      sx, sy = Flock.steer_to(sep_x, sep_y, @vx, @vy)
      ax += sx * Flock::W_SEP; ay += sy * Flock::W_SEP
    end
    [ax, ay]
  end

  def border_force
    ax = ay = 0.0
    bp = Cave::STONE_FACE_PX.to_f
    cr = collision_r.to_f
    r  = Flock::BORDER_AVOID_R
    w  = Flock::W_BORDER_AVOID
    dl = @x - (bp + cr)
    ax += w * (1.0 - dl / r) if dl < r
    dr = 1280.0 - bp - cr - @x
    ax -= w * (1.0 - dr / r) if dr < r
    db = @y - (bp + cr)
    ay += w * (1.0 - db / r) if db < r
    dt = 720.0 - bp - cr - @y
    ay -= w * (1.0 - dt / r) if dt < r
    [ax, ay]
  end

  def wall_force(wall_rects)
    ax = ay = 0.0
    size_ratio = collision_r.to_f / TIER_R[1]
    r  = Flock::WALL_AVOID_R * size_ratio
    r2 = r * r
    w  = Flock::W_WALL_AVOID * size_ratio
    wall_rects.each do |rect|
      nx = @x.clamp(rect[:x], rect[:x] + rect[:w])
      ny = @y.clamp(rect[:y], rect[:y] + rect[:h])
      dx = @x - nx
      dy = @y - ny
      d2 = dx * dx + dy * dy
      next if d2 > r2 || d2 < 0.0001

      d  = Math.sqrt(d2)
      st = w * (1.0 - d / r)
      ax += dx / d * st
      ay += dy / d * st
    end
    [ax, ay]
  end

  # Target selection. Returns hash with seek vector + near flag + flow field.
  def find_target(world)
    if @tier == 3
      tier3_target(world)
    else
      tier12_target(world)
    end
  end

  def tier3_target(world)
    altar_dx = world.altar_x - @x
    altar_dy = world.altar_y - @y
    altar_d2 = altar_dx * altar_dx + altar_dy * altar_dy
    at_altar  = altar_d2 < Cave::ALTAR_RADIUS * Cave::ALTAR_RADIUS
    pdx = world.player_x - @x
    pdy = world.player_y - @y
    pd2 = pdx * pdx + pdy * pdy
    targeting_player = !at_altar && pd2 < altar_d2
    {
      best_dx: targeting_player ? pdx : altar_dx,
      best_dy: targeting_player ? pdy : altar_dy,
      best_d2: targeting_player ? pd2 : altar_d2,
      near_idol: at_altar,
      flow_field: targeting_player ? world.flow_player_fat : world.flow_altar_fat
    }
  end

  def tier12_target(world)
    best_d2 = Float::INFINITY
    best_dx = best_dy = 0.0
    nearest_idx = nil
    world.idols.each_with_index do |idol, idx|
      next unless idol.placed?

      dx = idol.x - @x
      dy = idol.y - @y
      d2 = dx * dx + dy * dy
      next unless d2 < best_d2

      best_d2 = d2; best_dx = dx; best_dy = dy
      nearest_idx = idx
    end
    {
      best_dx: best_dx, best_dy: best_dy, best_d2: best_d2,
      near_idol: best_d2 < Cave::MERGE_RADIUS * Cave::MERGE_RADIUS,
      flow_field: nearest_idx && world.flow_idols ? world.flow_idols[nearest_idx] : world.flow_player
    }
  end

  def seek_force(target)
    seek_dx, seek_dy = flow_or_direct(target[:flow_field], target[:best_dx], target[:best_dy])
    weight = seek_weight(target[:near_idol], target[:best_d2])
    sx, sy = Flock.steer_to(seek_dx, seek_dy, @vx, @vy)
    [sx * weight, sy * weight]
  end

  def flow_or_direct(field, fallback_dx, fallback_dy)
    fdx, fdy = FlowField.direction(field, @x, @y)
    return [fdx, fdy] if fdx != 0.0 || fdy != 0.0
    [fallback_dx, fallback_dy]
  end

  def seek_weight(near_idol, best_d2)
    return near_idol ? 5.0 : 3.5 if @tier == 3
    return Flock::IDOL_PULL_NEAR if near_idol

    if best_d2 < Flock::IDOL_ATTRACT_RADIUS_SQ
      d = Math.sqrt(best_d2)
      t = ((d - Cave::MERGE_RADIUS) / (Flock::IDOL_ATTRACT_RADIUS - Cave::MERGE_RADIUS)).clamp(0.0, 1.0)
      # Quadratic falloff — strong near idol, decays fast in mid-range.
      eased = (1.0 - t) * (1.0 - t)
      Flock::IDOL_PULL_FAR + (Flock::IDOL_PULL_NEAR - Flock::IDOL_PULL_FAR) * eased
    else
      0.6
    end
  end

  # Advances wander/bias/impulse state. Returns [ax, ay] contribution.
  def advance_motion_force(near_idol)
    wander_scale = near_idol || @tier == 3 ? 0.05 : 1.0
    impulse_ok   = !(near_idol || @tier == 3)

    @wander_angle += (Numeric.rand - 0.5) * Flock::WANDER_ANGLE_STEP
    @bias_x, @bias_y = step_bias
    advance_speed_target

    ax = Math.cos(@wander_angle) * Flock::W_WANDER * @personality[:wander_scale] * wander_scale
    ay = Math.sin(@wander_angle) * Flock::W_WANDER * @personality[:wander_scale] * wander_scale
    bias_f = Flock::W_BIAS * @personality[:bias_scale] * wander_scale
    ax += @bias_x * bias_f
    ay += @bias_y * bias_f

    if @impulse_cooldown > 0
      @impulse_cooldown -= 1
    elsif impulse_ok && Numeric.rand < Flock::IMPULSE_CHANCE
      iax, iay = random_impulse
      ax += iax; ay += iay
    end

    [ax, ay]
  end

  def step_bias
    ba = Math.atan2(@bias_y, @bias_x) + (Numeric.rand - 0.5) * Flock::BIAS_ANGLE_STEP
    [Math.cos(ba), Math.sin(ba)]
  end

  def random_impulse
    ia = Numeric.rand * Math::PI * 2
    @wander_angle = ia
    @impulse_cooldown = Flock::IMPULSE_MIN_COOLDOWN + Numeric.rand(180)
    [Math.cos(ia) * Flock::IMPULSE_FORCE, Math.sin(ia) * Flock::IMPULSE_FORCE]
  end

  def advance_speed_target
    @speed_target += (Numeric.rand - 0.5) * Flock::SPEED_TARGET_STEP
    @speed_target  = @speed_target.clamp(Flock::SPEED_MULT_MIN, Flock::SPEED_MULT_MAX)
    @speed_mult   += (@speed_target - @speed_mult) * 0.05
  end

  def hunter_flee_force(hunters)
    return [0.0, 0.0] if hunters.empty?

    flee_x = flee_y = 0.0
    flee_n = 0
    hunters.each do |h|
      hdx = @x - h.x
      hdy = @y - h.y
      hd2 = hdx * hdx + hdy * hdy
      next if hd2 > Flock::HUNTER_FLEE_R_SQ || hd2 < 0.0001

      hd = Math.sqrt(hd2)
      weight = 1.0 - hd / Flock::HUNTER_FLEE_R
      flee_x += hdx / hd * weight
      flee_y += hdy / hd * weight
      flee_n += 1
    end
    return [0.0, 0.0] if flee_n == 0

    sx, sy = Flock.steer_to(flee_x, flee_y, @vx, @vy)
    [sx * Flock::W_HUNTER_FLEE, sy * Flock::W_HUNTER_FLEE]
  end

  def player_lure_force(world)
    pdx = world.player_x - @x
    pdy = world.player_y - @y
    pd2 = pdx * pdx + pdy * pdy
    return [0.0, 0.0] unless pd2 < Flock::PLAYER_ATTRACT_RADIUS_SQ

    field = @tier >= 2 ? world.flow_player_fat : world.flow_player
    pfdx, pfdy = FlowField.direction(field, @x, @y)
    use_dx = pfdx != 0.0 || pfdy != 0.0 ? pfdx : pdx
    use_dy = pfdx != 0.0 || pfdy != 0.0 ? pfdy : pdy
    sx, sy = Flock.steer_to(use_dx, use_dy, @vx, @vy)
    pw = Flock::W_PLAYER * world.player_w_boost *
         (1.0 - Math.sqrt(pd2) / Flock::PLAYER_ATTRACT_RADIUS)
    [sx * pw, sy * pw]
  end

end

class FlockWorld
  attr_reader :cave_grid, :idols, :altar_x, :altar_y, :player_x, :player_y,
              :hunters, :flow_altar, :flow_altar_fat, :flow_player, :flow_player_fat,
              :flow_idols, :wall_rects, :speed_boost, :player_w_boost

  def initialize(cave_grid:, idols:, altar_x:, altar_y:, player_x:, player_y:,
                 hunters:, ritual_stage:, speed_mult:,
                 flow_altar:, flow_altar_fat:, flow_player:, flow_player_fat:,
                 flow_idols:, wall_rects:)
    @cave_grid = cave_grid; @idols = idols
    @altar_x = altar_x; @altar_y = altar_y
    @player_x = player_x; @player_y = player_y
    @hunters = hunters
    @flow_altar = flow_altar; @flow_altar_fat = flow_altar_fat
    @flow_player = flow_player; @flow_player_fat = flow_player_fat
    @flow_idols = flow_idols
    @wall_rects = wall_rects
    @speed_boost    = (1.0 + ritual_stage * 0.15) * speed_mult
    @player_w_boost = 1.0 + ritual_stage * 0.25
  end
end

class FlockSimulation
  def initialize(world)
    @world = world
  end

  def step(boids)
    accs = compute_accelerations(boids)
    integrate(boids, accs)
    resolve_walls(boids)
    Flock.resolve_collisions(boids)
  end

  private

  def compute_accelerations(boids)
    boids.each_with_index.map { |b, i| b.accelerate(@world, boids, i) }
  end

  def integrate(boids, accs)
    boids.each_with_index do |b, i|
      b.vx += accs[i][0]
      b.vy += accs[i][1]
      b.integrate(@world.speed_boost)
    end
  end

  def resolve_walls(boids)
    boids.each { |b| Flock.resolve_wall_collision(b, @world.wall_rects) }
  end
end

module Flock
  PERCEPTION   = 55.0
  SEPARATION_R = 22.0
  MAX_SPEED    = 0.9
  MIN_SPEED    = 0.3
  MAX_FORCE    = 0.025

  W_SEP    = 1.8
  W_ALIGN  = 0.55
  W_COH    = 0.45
  W_WANDER = 0.030
  W_BIAS   = 0.012

  WANDER_ANGLE_STEP    = 0.35
  BIAS_ANGLE_STEP      = 0.04
  SPEED_TARGET_STEP    = 0.012
  SPEED_MULT_MIN       = 0.35
  SPEED_MULT_MAX       = 1.15
  IMPULSE_CHANCE       = 0.006
  IMPULSE_FORCE        = 0.12
  IMPULSE_MIN_COOLDOWN = 90

  COLLISION_DAMP       = 0.5

  BORDER_AVOID_R = 80.0
  W_BORDER_AVOID = 0.04
  WALL_AVOID_R   = 45.0
  W_WALL_AVOID   = 0.03

  IDOL_ATTRACT_RADIUS      = 400.0
  IDOL_ATTRACT_RADIUS_SQ   = IDOL_ATTRACT_RADIUS * IDOL_ATTRACT_RADIUS
  IDOL_PULL_NEAR           = 4.0
  IDOL_PULL_FAR            = 0.6

  PLAYER_ATTRACT_RADIUS    = 220.0
  PLAYER_ATTRACT_RADIUS_SQ = PLAYER_ATTRACT_RADIUS * PLAYER_ATTRACT_RADIUS
  W_PLAYER                 = 0.12

  HUNTER_FLEE_R    = 130.0
  HUNTER_FLEE_R_SQ = HUNTER_FLEE_R * HUNTER_FLEE_R
  W_HUNTER_FLEE    = 2.4

  def self.spawn(count, animator_factory, cave_grid:)
    cells = Cave.floor_cells(cave_grid)
    cells = (1..Cave::ROWS - 2).flat_map { |r| (1..Cave::COLS - 2).map { |c| [c, r] } } if cells.empty?
    Array.new(count) do
      angle      = Numeric.rand * Math::PI * 2
      speed      = MIN_SPEED + Numeric.rand * (MAX_SPEED - MIN_SPEED)
      bias_angle = Numeric.rand * Math::PI * 2
      col, row   = cells.sample
      x = col * Cave::TILE_SIZE + Cave::TILE_SIZE / 2 + (Numeric.rand - 0.5) * Cave::TILE_SIZE * 0.4
      y = row * Cave::TILE_SIZE + Cave::TILE_SIZE / 2 + (Numeric.rand - 0.5) * Cave::TILE_SIZE * 0.4
      personality = {
        speed_scale: 0.75 + Numeric.rand * 0.5,
        wander_scale: 0.6 + Numeric.rand * 0.8,
        bias_scale: 0.5 + Numeric.rand * 1.0
      }
      Boid.new(
        x: x, y: y,
        vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed,
        bias_x: Math.cos(bias_angle), bias_y: Math.sin(bias_angle),
        animator: animator_factory.call,
        personality: personality,
        tier: 1
      )
    end
  end

  # Thin shim — main.rb still calls Flock.step. New code should use FlockSimulation directly.
  def self.step(boids, cave_grid:, idols:, altar_x:, altar_y:, player_x:, player_y:,
                ritual_stage: 0, hunters: [], speed_mult: 1.0,
                flow_altar: nil, flow_altar_fat: nil,
                flow_player: nil, flow_player_fat: nil,
                flow_idols: nil, wall_rects: [])
    world = FlockWorld.new(
      cave_grid: cave_grid, idols: idols,
      altar_x: altar_x, altar_y: altar_y,
      player_x: player_x, player_y: player_y,
      hunters: hunters, ritual_stage: ritual_stage, speed_mult: speed_mult,
      flow_altar: flow_altar, flow_altar_fat: flow_altar_fat,
      flow_player: flow_player, flow_player_fat: flow_player_fat,
      flow_idols: flow_idols, wall_rects: wall_rects
    )
    FlockSimulation.new(world).step(boids)
  end

  def self.resolve_wall_collision(b, wall_rects)
    r  = b.collision_r.to_f
    r2 = r * r

    wall_rects.each do |rect|
      nx = b.x.clamp(rect[:x], rect[:x] + rect[:w])
      ny = b.y.clamp(rect[:y], rect[:y] + rect[:h])
      dx = b.x - nx
      dy = b.y - ny
      d2 = dx * dx + dy * dy
      next if d2 >= r2 || d2 < 0.0001

      d       = Math.sqrt(d2)
      overlap = r - d
      px = dx / d
      py = dy / d
      b.x += px * overlap
      b.y += py * overlap

      dot = b.vx * px + b.vy * py
      if dot < 0
        b.vx -= px * dot * COLLISION_DAMP
        b.vy -= py * dot * COLLISION_DAMP
      end
    end

    bp = Cave::STONE_FACE_PX
    b.x = b.x.clamp(bp + r, 1280.0 - bp - r)
    b.y = b.y.clamp(bp + r, 720.0  - bp - r)
  end

  def self.resolve_collisions(boids)
    boids.each_with_index do |a, i|
      ((i + 1)...boids.length).each do |j|
        b     = boids[j]
        min_d = a.collision_r + b.collision_r
        dx    = b.x - a.x
        dy    = b.y - a.y
        d2    = dx * dx + dy * dy
        next if d2 >= min_d * min_d || d2 < 0.0001

        d  = Math.sqrt(d2)
        nx = dx / d
        ny = dy / d
        push = (min_d - d) * 0.5

        a.x -= nx * push; a.y -= ny * push
        b.x += nx * push; b.y += ny * push

        va_n = a.vx * nx + a.vy * ny
        vb_n = b.vx * nx + b.vy * ny
        if va_n > 0
          a.vx -= nx * va_n * COLLISION_DAMP
          a.vy -= ny * va_n * COLLISION_DAMP
        end
        if vb_n < 0
          b.vx -= nx * vb_n * COLLISION_DAMP
          b.vy -= ny * vb_n * COLLISION_DAMP
        end
      end
    end
  end

  def self.steer_to(dx, dy, vx, vy)
    mag = Math.sqrt(dx * dx + dy * dy)
    return [0.0, 0.0] if mag < 0.0001

    dxn = dx / mag * MAX_SPEED
    dyn = dy / mag * MAX_SPEED
    sx  = dxn - vx
    sy  = dyn - vy
    smag = Math.sqrt(sx * sx + sy * sy)
    if smag > MAX_FORCE
      sx = sx / smag * MAX_FORCE
      sy = sy / smag * MAX_FORCE
    end
    [sx, sy]
  end
end
