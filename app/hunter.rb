class Hunter
  SPEED      = 1.5
  RADIUS     = 10
  TURN_SPEED = 0.07
  HP         = 3
  HIT_CD     = 40
  SCALE      = 1.6

  WATCHER_SPEED         = 0.6
  WATCHER_HP            = 4
  WATCHER_AURA_R        = 160
  WATCHER_SANITY_DRAIN  = 0.05

  attr_accessor :x, :y, :vx, :vy, :hp, :hit_timer, :kind

  def initialize(x:, y:, animator:, kind: :inquisitor)
    @x = x.to_f; @y = y.to_f
    @kind = kind
    angle = rand * Math::PI * 2
    spd = base_speed
    @vx = Math.cos(angle) * spd
    @vy = Math.sin(angle) * spd
    @hp = kind == :watcher ? WATCHER_HP : HP
    @hit_timer = 0
    @animator = animator
  end

  def base_speed
    @kind == :watcher ? WATCHER_SPEED : SPEED
  end

  def dead?
    @hp <= 0
  end

  def take_hit
    return if @hit_timer > 0
    @hp -= 1
    @hit_timer = HIT_CD
  end

  def update(tx, ty, cave_grid)
    spd = base_speed
    dx = tx - @x; dy = ty - @y
    mag = Math.sqrt(dx * dx + dy * dy)
    if mag > 0.0001
      @vx += (dx / mag * spd - @vx) * TURN_SPEED
      @vy += (dy / mag * spd - @vy) * TURN_SPEED
    end

    sp = Math.sqrt(@vx * @vx + @vy * @vy)
    if sp > spd
      @vx = @vx / sp * spd; @vy = @vy / sp * spd
    end

    r = RADIUS
    nx = @x + @vx
    ny = @y + @vy
    if !Cave.blocks_circle?(cave_grid, nx, ny, r)
      @x = nx; @y = ny
    elsif @vx != 0 && !Cave.blocks_circle?(cave_grid, nx, @y, r)
      @x = nx
    elsif @vy != 0 && !Cave.blocks_circle?(cave_grid, @x, ny, r)
      @y = ny
    end
    @x = @x.clamp(Cave::TILE_SIZE + r.to_f, 1280.0 - Cave::TILE_SIZE - r.to_f)
    @y = @y.clamp(Cave::TILE_SIZE + r.to_f, 720.0 - Cave::TILE_SIZE - r.to_f)

    @hit_timer -= 1 if @hit_timer > 0
  end

  def render(tick_count)
    flash = @hit_timer > 0 && (@hit_timer % 6 < 3)
    return [] unless @animator
    sprite = @animator.sprite(tick_count, anchor_x: @x, anchor_y: @y, scale: SCALE)
    sprite[:flip_horizontally] = @vx < 0
    sprite[:a] = flash ? 80 : 255
    if @kind == :watcher
      # Sickly green tint for the Watcher
      sprite[:r] = 140; sprite[:g] = 220; sprite[:b] = 140
    end
    max = @kind == :watcher ? WATCHER_HP : HP
    pip_y = @y + HunterFrames::ALL.map { |f| f[:h] }.max * SCALE / 2 + 4
    pips = max.times.map do |i|
      filled = i < @hp
      { x: @x - max * 4 + i * 8, y: pip_y, w: 6, h: 4,
        path: :solid, r: filled ? 220 : 60, g: filled ? 40 : 40, b: filled ? 40 : 50, a: 200 }
    end
    extras = []
    if @kind == :watcher
      # Faint aura
      pulse = (Math.sin(tick_count * 0.05) * 0.3 + 0.7)
      d = (WATCHER_AURA_R * 2).to_i
      extras << {
        x: @x - d / 2, y: @y - d / 2, w: d, h: d,
        path: :solid, r: 80, g: 200, b: 80, a: (40 * pulse).to_i, blendmode_enum: 1
      }
    end
    extras + [sprite] + pips
  end
end
