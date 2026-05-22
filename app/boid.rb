class Boid
  attr_accessor :x, :y, :vx, :vy,
                :bias_x, :bias_y,
                :wander_angle,
                :speed_mult,
                :speed_target,
                :impulse_cooldown,
                :personality

  def initialize(x:, y:, vx:, vy:, bias_x:, bias_y:, animator:, personality:)
    @x = x
    @y = y
    @vx = vx
    @vy = vy
    @bias_x = bias_x
    @bias_y = bias_y
    @wander_angle = rand * Math::PI * 2
    @speed_mult = 1.0
    @speed_target = 1.0
    @impulse_cooldown = rand(120)
    @personality = personality
    @animator = animator
  end

  def render(tick_count, scale:)
    s = @animator.sprite(tick_count, anchor_x: @x, anchor_y: @y, scale: scale)
    s[:flip_horizontally] = @vx < 0
    s
  end
end

module Flock
  WORLD_W = 1280
  WORLD_H = 720

  PERCEPTION   = 55.0   # tight: boid only sees close neighbors -> multiple sub-flocks
  SEPARATION_R = 22.0
  MAX_SPEED    = 0.9    # walking pace
  MIN_SPEED    = 0.3
  MAX_FORCE    = 0.025

  W_SEP    = 1.8
  W_ALIGN  = 0.55       # weak: groups don't all converge to same heading
  W_COH    = 0.45       # weak: loose local clumping
  W_WANDER = 0.030      # magnitude of smooth-wander force
  W_BIAS   = 0.012      # persistent per-boid heading -> groups drift in different directions

  WANDER_ANGLE_STEP = 0.35    # how fast wander_angle random-walks (radians/tick stddev)
  BIAS_ANGLE_STEP   = 0.04    # how fast bias_angle drifts
  SPEED_TARGET_STEP = 0.012   # how fast speed_mult target drifts
  SPEED_MULT_MIN    = 0.35    # creature can slow this much (loitering)
  SPEED_MULT_MAX    = 1.15    # or briefly burst
  IMPULSE_CHANCE    = 0.006   # ~1 per ~167 ticks per boid: sudden direction kick
  IMPULSE_FORCE     = 0.12
  IMPULSE_MIN_COOLDOWN = 90

  # Hard collision: creatures cannot physically overlap. Circle radius in world units.
  # Matches roughly the rendered footprint (bbox ~120 * scale 0.5 / 2 ~= 30, but tighter
  # feels right since visible mass is smaller than bbox).
  COLLISION_R     = 14.0
  COLLISION_R_SQ  = COLLISION_R * COLLISION_R * 4   # (2r)^2
  COLLISION_DAMP  = 0.5   # velocity component along collision normal absorbed

  def self.spawn(count, animator_factory)
    Array.new(count) do
      angle = rand * Math::PI * 2
      speed = MIN_SPEED + rand * (MAX_SPEED - MIN_SPEED)
      bias_angle = rand * Math::PI * 2
      # per-boid personality: subtle individual variation so no two creatures
      # behave identically -> emergent natural-looking heterogeneity
      personality = {
        speed_scale:  0.75 + rand * 0.5,    # 0.75..1.25
        wander_scale: 0.6 + rand * 0.8,     # 0.6..1.4
        bias_scale:   0.5 + rand * 1.0      # some boids more wilful, some more drifty
      }
      Boid.new(
        x: rand * WORLD_W,
        y: rand * WORLD_H,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        bias_x: Math.cos(bias_angle),
        bias_y: Math.sin(bias_angle),
        animator: animator_factory.call,
        personality: personality
      )
    end
  end

  def self.step(boids)
    perception_sq = PERCEPTION * PERCEPTION
    sep_sq = SEPARATION_R * SEPARATION_R

    accelerations = Array.new(boids.length) { [0.0, 0.0] }

    boids.each_with_index do |b, i|
      sep_x = 0.0
      sep_y = 0.0
      ali_x = 0.0
      ali_y = 0.0
      coh_x = 0.0
      coh_y = 0.0
      n_neighbors = 0
      n_sep = 0

      boids.each_with_index do |o, j|
        next if i == j

        dx = o.x - b.x
        dy = o.y - b.y
        # toroidal wrap distance
        dx -= WORLD_W if dx >  WORLD_W * 0.5
        dx += WORLD_W if dx < -WORLD_W * 0.5
        dy -= WORLD_H if dy >  WORLD_H * 0.5
        dy += WORLD_H if dy < -WORLD_H * 0.5
        d2 = dx * dx + dy * dy
        next if d2 > perception_sq || d2 < 0.0001

        n_neighbors += 1
        ali_x += o.vx
        ali_y += o.vy
        coh_x += b.x + dx
        coh_y += b.y + dy

        next unless d2 < sep_sq

        # inverse-square falloff: gentle at sep_sq edge, strong when very close.
        # allows natural overlap at medium range, hard push only when crowding.
        sep_x -= dx / d2
        sep_y -= dy / d2
        n_sep += 1
      end

      ax = 0.0
      ay = 0.0

      if n_neighbors > 0
        ali_x /= n_neighbors
        ali_y /= n_neighbors
        ali_x, ali_y = steer_to(ali_x, ali_y, b.vx, b.vy)
        ax += ali_x * W_ALIGN
        ay += ali_y * W_ALIGN

        coh_x /= n_neighbors
        coh_y /= n_neighbors
        desired_x = coh_x - b.x
        desired_y = coh_y - b.y
        coh_sx, coh_sy = steer_to(desired_x, desired_y, b.vx, b.vy)
        ax += coh_sx * W_COH
        ay += coh_sy * W_COH
      end

      if n_sep > 0
        sep_x /= n_sep
        sep_y /= n_sep
        sep_sx, sep_sy = steer_to(sep_x, sep_y, b.vx, b.vy)
        ax += sep_sx * W_SEP
        ay += sep_sy * W_SEP
      end

      # smooth wander: wander_angle random-walks each tick. Force applied in that
      # direction. Result is a slowly-curving meander instead of jittery noise.
      b.wander_angle += (rand - 0.5) * WANDER_ANGLE_STEP
      w_force = W_WANDER * b.personality[:wander_scale]
      ax += Math.cos(b.wander_angle) * w_force
      ay += Math.sin(b.wander_angle) * w_force

      # persistent per-boid bias: each boid has its own preferred heading.
      # neighbors with similar bias drift together; differing biases peel sub-flocks apart.
      bias_f = W_BIAS * b.personality[:bias_scale]
      ax += b.bias_x * bias_f
      ay += b.bias_y * bias_f

      # slowly rotate the bias so flocks don't run forever in a straight line
      ba = Math.atan2(b.bias_y, b.bias_x) + (rand - 0.5) * BIAS_ANGLE_STEP
      b.bias_x = Math.cos(ba)
      b.bias_y = Math.sin(ba)

      # impulse: rare sudden direction kick (startle, curiosity, distraction).
      # Cooldown prevents back-to-back kicks on same boid.
      if b.impulse_cooldown > 0
        b.impulse_cooldown -= 1
      elsif rand < IMPULSE_CHANCE
        ia = rand * Math::PI * 2
        ax += Math.cos(ia) * IMPULSE_FORCE
        ay += Math.sin(ia) * IMPULSE_FORCE
        # nudge the wander_angle too so the meander continues in roughly the new direction
        b.wander_angle = ia
        b.impulse_cooldown = IMPULSE_MIN_COOLDOWN + rand(180)
      end

      # speed throttle: each boid has a slowly-drifting target speed multiplier.
      # Creates the loitering / hurrying mix you see in real flocks.
      b.speed_target += (rand - 0.5) * SPEED_TARGET_STEP
      b.speed_target = b.speed_target.clamp(SPEED_MULT_MIN, SPEED_MULT_MAX)
      b.speed_mult += (b.speed_target - b.speed_mult) * 0.05  # smooth toward target

      accelerations[i][0] = ax
      accelerations[i][1] = ay
    end

    boids.each_with_index do |b, i|
      b.vx += accelerations[i][0]
      b.vy += accelerations[i][1]

      # per-boid effective speed range = global range * personality * current throttle
      effective_max = MAX_SPEED * b.personality[:speed_scale] * b.speed_mult
      effective_min = MIN_SPEED * b.personality[:speed_scale] * b.speed_mult

      sp = Math.sqrt(b.vx * b.vx + b.vy * b.vy)
      if sp > effective_max
        b.vx = b.vx / sp * effective_max
        b.vy = b.vy / sp * effective_max
      elsif sp < effective_min && sp > 0.0001
        b.vx = b.vx / sp * effective_min
        b.vy = b.vy / sp * effective_min
      end
      b.x = (b.x + b.vx) % WORLD_W
      b.y = (b.y + b.vy) % WORLD_H
    end

    resolve_collisions(boids)
  end

  # Hard pairwise collision resolution. Treat each boid as a circle of COLLISION_R.
  # On overlap: push apart by half the penetration each, and damp velocity along
  # the collision normal so they don't bounce wildly.
  def self.resolve_collisions(boids)
    min_d = COLLISION_R * 2

    boids.each_with_index do |a, i|
      ((i + 1)...boids.length).each do |j|
        b = boids[j]
        dx = b.x - a.x
        dy = b.y - a.y
        # toroidal wrap
        dx -= WORLD_W if dx >  WORLD_W * 0.5
        dx += WORLD_W if dx < -WORLD_W * 0.5
        dy -= WORLD_H if dy >  WORLD_H * 0.5
        dy += WORLD_H if dy < -WORLD_H * 0.5
        d2 = dx * dx + dy * dy
        next if d2 >= COLLISION_R_SQ || d2 < 0.0001

        d  = Math.sqrt(d2)
        overlap = min_d - d
        nx = dx / d
        ny = dy / d
        push = overlap * 0.5

        a.x = (a.x - nx * push) % WORLD_W
        a.y = (a.y - ny * push) % WORLD_H
        b.x = (b.x + nx * push) % WORLD_W
        b.y = (b.y + ny * push) % WORLD_H

        # damp velocity along collision normal so they don't keep ramming
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
    sx = dxn - vx
    sy = dyn - vy
    smag = Math.sqrt(sx * sx + sy * sy)
    if smag > MAX_FORCE
      sx = sx / smag * MAX_FORCE
      sy = sy / smag * MAX_FORCE
    end
    [sx, sy]
  end
end
