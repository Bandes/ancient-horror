class Hunter
  SPEED      = 1.5
  RADIUS     = 10
  TURN_SPEED = 0.07
  HP         = 3
  HIT_CD     = 40
  SCALE      = 2.0

  attr_accessor :x, :y, :vx, :vy, :hp, :hit_timer

  def initialize(x:, y:, animator:)
    @x = x.to_f; @y = y.to_f
    angle = rand * Math::PI * 2
    @vx = Math.cos(angle) * SPEED
    @vy = Math.sin(angle) * SPEED
    @hp = HP
    @hit_timer = 0
    @animator = animator
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
    dx = tx - @x; dy = ty - @y
    mag = Math.sqrt(dx * dx + dy * dy)
    if mag > 0.0001
      @vx += (dx / mag * SPEED - @vx) * TURN_SPEED
      @vy += (dy / mag * SPEED - @vy) * TURN_SPEED
    end

    sp = Math.sqrt(@vx * @vx + @vy * @vy)
    if sp > SPEED
      @vx = @vx / sp * SPEED; @vy = @vy / sp * SPEED
    end

    r = RADIUS
    new_x = @x + @vx
    new_y = @y + @vy
    new_x = @x if (@vx > 0 && Cave.blocks_movement?(cave_grid, (new_x + r).to_i, @y.to_i)) ||
                   (@vx < 0 && Cave.blocks_movement?(cave_grid, (new_x - r).to_i, @y.to_i))
    new_y = @y if (@vy > 0 && Cave.blocks_movement?(cave_grid, @x.to_i, (new_y + r).to_i)) ||
                   (@vy < 0 && Cave.blocks_movement?(cave_grid, @x.to_i, (new_y - r).to_i))
    @x = new_x.clamp(r, 1280.0 - r)
    @y = new_y.clamp(r, 720.0 - r)

    @hit_timer -= 1 if @hit_timer > 0
  end

  def render(tick_count)
    flash = @hit_timer > 0 && (@hit_timer % 6 < 3)
    sprite = @animator.sprite(tick_count, anchor_x: @x, anchor_y: @y, scale: SCALE)
    sprite[:flip_horizontally] = @vx < 0
    sprite[:a] = flash ? 80 : 255
    pip_y = @y + HunterFrames::ALL.map { |f| f[:h] }.max * SCALE / 2 + 4
    pips = HP.times.map do |i|
      filled = i < @hp
      { x: @x - HP * 4 + i * 8, y: pip_y, w: 6, h: 4,
        path: :solid, r: filled ? 220 : 60, g: filled ? 40 : 40, b: filled ? 40 : 50, a: 200 }
    end
    [sprite] + pips
  end
end
