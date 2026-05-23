class Player
  SPEED        = 2.5
  MAX_HP       = 5
  HIT_COOLDOWN = 60
  RADIUS       = 12
  W            = 24
  H            = 36

  SCALE = 1.0

  attr_accessor :x, :y, :hp, :hit_timer, :idols_held

  def initialize(x:, y:)
    @x          = x.to_f
    @y          = y.to_f
    @hp         = MAX_HP
    @hit_timer  = 0
    @idols_held = 6
    @facing_left = false
    @moving      = false
    @animator    = SpriteAnimator.new(
      path: 'sprites/walk.png',
      frames: WalkFrames::ALL,
      frame_duration: 6
    )
  end

  def update(input, cave_grid)
    vx = 0.0; vy = 0.0
    vx -= SPEED if input.keyboard.key_held.left  || input.keyboard.key_held.a
    vx += SPEED if input.keyboard.key_held.right || input.keyboard.key_held.d
    vy -= SPEED if input.keyboard.key_held.down  || input.keyboard.key_held.s
    vy += SPEED if input.keyboard.key_held.up    || input.keyboard.key_held.w
    @facing_left = vx < 0 if vx != 0
    @moving = vx != 0 || vy != 0

    if vx != 0.0 && vy != 0.0
      vx *= 0.7071
      vy *= 0.7071
    end

    r = RADIUS
    new_x = @x + vx
    new_y = @y + vy

    new_x = @x if Cave.wall_at_px?(cave_grid, (new_x + r).to_i, @y.to_i) ||
                   Cave.wall_at_px?(cave_grid, (new_x - r).to_i, @y.to_i)
    new_y = @y if Cave.wall_at_px?(cave_grid, @x.to_i, (new_y + r).to_i) ||
                   Cave.wall_at_px?(cave_grid, @x.to_i, (new_y - r).to_i)

    @x = new_x.clamp(r.to_f, (1280 - r).to_f)
    @y = new_y.clamp(r.to_f, (720 - r).to_f)

    @hit_timer -= 1 if @hit_timer > 0
  end

  def take_hit
    return if @hit_timer > 0
    @hp -= 1
    @hit_timer = HIT_COOLDOWN
  end

  def dead?
    @hp <= 0
  end

  def invincible?
    @hit_timer > 0
  end

  def radius
    RADIUS
  end

  def render(tick_count)
    flash = invincible? && (@hit_timer % 6 < 3)
    a     = flash ? 80 : 255
    sprite = @animator.sprite(tick_count, anchor_x: @x, anchor_y: @y, scale: SCALE)
    sprite[:flip_horizontally] = @facing_left
    sprite[:a] = a
    pip_y = @y + WalkFrames::H * SCALE / 2 + 4
    pips = MAX_HP.times.map do |i|
      filled = i < @hp
      { x: @x - MAX_HP * 7 + i * 14, y: pip_y, w: 10, h: 6,
        path: :solid, r: filled ? 220 : 60, g: filled ? 50 : 50, b: filled ? 50 : 60, a: 220 }
    end
    [sprite] + pips
  end
end
