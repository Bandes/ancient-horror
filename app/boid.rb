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
    @wander_angle    = rand * Math::PI * 2
    @speed_mult      = 1.0
    @speed_target    = 1.0
    @impulse_cooldown = rand(120)
    @spawn_timer      = rand(300)
    @personality     = personality
    @animator        = animator
    @tier            = tier
  end

  def collision_r
    TIER_R[@tier]
  end

  def render(tick_count)
    s = @animator.sprite(tick_count, anchor_x: @x, anchor_y: @y, scale: TIER_SCALE[@tier])
    s[:flip_horizontally] = @vx < 0
    s
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

  IDOL_ATTRACT_RADIUS_SQ   = 400 * 400
  PLAYER_ATTRACT_RADIUS_SQ = 220 * 220
  W_PLAYER                 = 0.12

  def self.spawn(count, animator_factory, cave_grid:)
    cells = Cave.floor_cells(cave_grid)
    # Fallback if cave generation produced no floor cells
    if cells.empty?
      cells = (1..Cave::ROWS - 2).flat_map { |r| (1..Cave::COLS - 2).map { |c| [c, r] } }
    end
    Array.new(count) do
      angle      = rand * Math::PI * 2
      speed      = MIN_SPEED + rand * (MAX_SPEED - MIN_SPEED)
      bias_angle = rand * Math::PI * 2
      col, row   = cells.sample
      x = col * Cave::TILE_SIZE + Cave::TILE_SIZE / 2 + (rand - 0.5) * Cave::TILE_SIZE * 0.4
      y = row * Cave::TILE_SIZE + Cave::TILE_SIZE / 2 + (rand - 0.5) * Cave::TILE_SIZE * 0.4
      personality = {
        speed_scale:  0.75 + rand * 0.5,
        wander_scale: 0.6  + rand * 0.8,
        bias_scale:   0.5  + rand * 1.0
      }
      Boid.new(
        x: x, y: y,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        bias_x: Math.cos(bias_angle),
        bias_y: Math.sin(bias_angle),
        animator: animator_factory.call,
        personality: personality,
        tier: 1
      )
    end
  end

  def self.step(boids, cave_grid:, idols:, altar_x:, altar_y:, player_x:, player_y:, ritual_stage: 0)
    speed_boost   = 1.0 + ritual_stage * 0.15
    player_w_boost = 1.0 + ritual_stage * 0.25
    perception_sq = PERCEPTION * PERCEPTION
    sep_sq        = SEPARATION_R * SEPARATION_R

    accelerations = Array.new(boids.length) { [0.0, 0.0] }

    boids.each_with_index do |b, i|
      sep_x = sep_y = ali_x = ali_y = coh_x = coh_y = 0.0
      n_neighbors = n_sep = 0

      boids.each_with_index do |o, j|
        next if i == j
        dx = o.x - b.x; dy = o.y - b.y
        d2 = dx * dx + dy * dy
        next if d2 > perception_sq || d2 < 0.0001
        n_neighbors += 1
        ali_x += o.vx; ali_y += o.vy
        coh_x += b.x + dx; coh_y += b.y + dy
        if d2 < sep_sq
          sep_x -= dx / d2; sep_y -= dy / d2
          n_sep += 1
        end
      end

      ax = ay = 0.0

      if n_neighbors > 0
        ali_x /= n_neighbors; ali_y /= n_neighbors
        sx, sy = steer_to(ali_x, ali_y, b.vx, b.vy)
        ax += sx * W_ALIGN; ay += sy * W_ALIGN
        coh_x /= n_neighbors; coh_y /= n_neighbors
        sx, sy = steer_to(coh_x - b.x, coh_y - b.y, b.vx, b.vy)
        ax += sx * W_COH; ay += sy * W_COH
      end

      if n_sep > 0
        sep_x /= n_sep; sep_y /= n_sep
        sx, sy = steer_to(sep_x, sep_y, b.vx, b.vy)
        ax += sx * W_SEP; ay += sy * W_SEP
      end

      # Find nearest placed idol (tier 1+2) or use altar (tier 3)
      near_idol = false
      if b.tier == 3
        best_dx = altar_x - b.x; best_dy = altar_y - b.y
        best_d2 = best_dx * best_dx + best_dy * best_dy
        near_idol = best_d2 < Cave::ALTAR_RADIUS * Cave::ALTAR_RADIUS
      else
        best_d2 = Float::INFINITY
        best_dx = best_dy = 0.0
        idols.each do |idol|
          next unless idol[:placed]
          dx = idol[:x] - b.x; dy = idol[:y] - b.y
          d2 = dx * dx + dy * dy
          if d2 < best_d2
            best_d2 = d2; best_dx = dx; best_dy = dy
          end
        end
        near_idol = best_d2 < Cave::MERGE_RADIUS * Cave::MERGE_RADIUS
      end

      # Suppress autonomous behavior when locked onto target
      wander_scale = near_idol ? 0.05 : 1.0
      impulse_ok   = !near_idol

      b.wander_angle += (rand - 0.5) * WANDER_ANGLE_STEP
      ax += Math.cos(b.wander_angle) * W_WANDER * b.personality[:wander_scale] * wander_scale
      ay += Math.sin(b.wander_angle) * W_WANDER * b.personality[:wander_scale] * wander_scale

      bias_f = W_BIAS * b.personality[:bias_scale] * wander_scale
      ax += b.bias_x * bias_f; ay += b.bias_y * bias_f
      ba = Math.atan2(b.bias_y, b.bias_x) + (rand - 0.5) * BIAS_ANGLE_STEP
      b.bias_x = Math.cos(ba); b.bias_y = Math.sin(ba)

      if b.impulse_cooldown > 0
        b.impulse_cooldown -= 1
      elsif impulse_ok && rand < IMPULSE_CHANCE
        ia = rand * Math::PI * 2
        ax += Math.cos(ia) * IMPULSE_FORCE
        ay += Math.sin(ia) * IMPULSE_FORCE
        b.wander_angle = ia
        b.impulse_cooldown = IMPULSE_MIN_COOLDOWN + rand(180)
      end

      b.speed_target += (rand - 0.5) * SPEED_TARGET_STEP
      b.speed_target  = b.speed_target.clamp(SPEED_MULT_MIN, SPEED_MULT_MAX)
      b.speed_mult   += (b.speed_target - b.speed_mult) * 0.05

      # Seek target — strong pull when close, moderate pull when far
      if b.tier == 3 || best_d2 < IDOL_ATTRACT_RADIUS_SQ
        sx, sy = steer_to(best_dx, best_dy, b.vx, b.vy)
        weight = near_idol ? 5.0 : (0.6 * (1.0 - Math.sqrt(best_d2) / Math.sqrt(IDOL_ATTRACT_RADIUS_SQ)))
        ax += sx * weight; ay += sy * weight
      end

      # Player as lure — tier 1+2 attracted to player at medium range
      if b.tier < 3
        pdx = player_x - b.x; pdy = player_y - b.y
        pd2 = pdx * pdx + pdy * pdy
        if pd2 < PLAYER_ATTRACT_RADIUS_SQ
          sx, sy = steer_to(pdx, pdy, b.vx, b.vy)
          pw = W_PLAYER * player_w_boost * (1.0 - Math.sqrt(pd2) / Math.sqrt(PLAYER_ATTRACT_RADIUS_SQ))
          ax += sx * pw; ay += sy * pw
        end
      end

      accelerations[i] = [ax, ay]
    end

    boids.each_with_index do |b, i|
      b.vx += accelerations[i][0]
      b.vy += accelerations[i][1]

      effective_max = MAX_SPEED * b.personality[:speed_scale] * b.speed_mult * speed_boost
      effective_min = MIN_SPEED * b.personality[:speed_scale] * b.speed_mult * speed_boost
      sp = Math.sqrt(b.vx * b.vx + b.vy * b.vy)
      if sp > effective_max
        b.vx = b.vx / sp * effective_max; b.vy = b.vy / sp * effective_max
      elsif sp < effective_min && sp > 0.0001
        b.vx = b.vx / sp * effective_min; b.vy = b.vy / sp * effective_min
      end

      b.x += b.vx
      b.y += b.vy

      resolve_wall_collision(b, cave_grid)
    end

    resolve_collisions(boids)
  end

  def self.resolve_wall_collision(b, cave_grid)
    r = b.collision_r.to_f

    if Cave.blocks_movement?(cave_grid, (b.x + r).to_i, b.y.to_i) && b.vx > 0
      b.vx = -b.vx.abs * 0.3
      b.x  = (b.x + r).idiv(Cave::TILE_SIZE) * Cave::TILE_SIZE - r - 0.5
    end
    if Cave.blocks_movement?(cave_grid, (b.x - r).to_i, b.y.to_i) && b.vx < 0
      b.vx = b.vx.abs * 0.3
      b.x  = ((b.x - r).idiv(Cave::TILE_SIZE) + 1) * Cave::TILE_SIZE + r + 0.5
    end
    if Cave.blocks_movement?(cave_grid, b.x.to_i, (b.y + r).to_i) && b.vy > 0
      b.vy = -b.vy.abs * 0.3
      b.y  = (b.y + r).idiv(Cave::TILE_SIZE) * Cave::TILE_SIZE - r - 0.5
    end
    if Cave.blocks_movement?(cave_grid, b.x.to_i, (b.y - r).to_i) && b.vy < 0
      b.vy = b.vy.abs * 0.3
      b.y  = ((b.y - r).idiv(Cave::TILE_SIZE) + 1) * Cave::TILE_SIZE + r + 0.5
    end

    b.x = b.x.clamp(r, 1280.0 - r)
    b.y = b.y.clamp(r, 720.0  - r)
  end

  def self.resolve_collisions(boids)
    boids.each_with_index do |a, i|
      ((i + 1)...boids.length).each do |j|
        b     = boids[j]
        min_d = a.collision_r + b.collision_r
        dx    = b.x - a.x; dy = b.y - a.y
        d2    = dx * dx + dy * dy
        next if d2 >= min_d * min_d || d2 < 0.0001

        d  = Math.sqrt(d2)
        nx = dx / d; ny = dy / d
        push = (min_d - d) * 0.5

        a.x -= nx * push; a.y -= ny * push
        b.x += nx * push; b.y += ny * push

        va_n = a.vx * nx + a.vy * ny
        vb_n = b.vx * nx + b.vy * ny
        if va_n > 0
          a.vx -= nx * va_n * COLLISION_DAMP; a.vy -= ny * va_n * COLLISION_DAMP
        end
        if vb_n < 0
          b.vx -= nx * vb_n * COLLISION_DAMP; b.vy -= ny * vb_n * COLLISION_DAMP
        end
      end
    end
  end

  def self.steer_to(dx, dy, vx, vy)
    mag = Math.sqrt(dx * dx + dy * dy)
    return [0.0, 0.0] if mag < 0.0001
    dxn = dx / mag * MAX_SPEED; dyn = dy / mag * MAX_SPEED
    sx  = dxn - vx; sy  = dyn - vy
    smag = Math.sqrt(sx * sx + sy * sy)
    if smag > MAX_FORCE
      sx = sx / smag * MAX_FORCE; sy = sy / smag * MAX_FORCE
    end
    [sx, sy]
  end
end
