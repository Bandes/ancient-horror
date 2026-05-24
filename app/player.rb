class Player
  SPEED          = 2.5
  MAX_HP         = 5
  MAX_SANITY     = 100
  HIT_COOLDOWN   = 60
  RADIUS         = 12
  STOMP_COOLDOWN       = 150
  STOMP_RADIUS         = 110
  STOMP_FORCE          = 2.2
  SCALE                = 1.0
  ATTACK_FRAME_DURATION = 4

  attr_accessor :x, :y, :hp, :sanity, :hit_timer, :idols_held

  def initialize(x:, y:)
    @x              = x.to_f
    @y              = y.to_f
    @hp             = MAX_HP
    @sanity         = MAX_SANITY
    @hit_timer      = 0
    @idols_held     = 6
    @facing_left    = false
    @stomp_timer    = 0
    @attack_tick    = nil
    @animator       = SpriteAnimator.new(
      path: 'sprites/walk.png',
      frames: WalkFrames::ALL,
      frame_duration: 6
    )
    @attack_animator = SpriteAnimator.new(
      path: 'sprites/attack.png',
      frames: AttackFrames::ALL,
      frame_duration: ATTACK_FRAME_DURATION
    )
  end

  def update(input, cave_grid)
    vx = 0.0; vy = 0.0
    vx -= SPEED if input.keyboard.key_held.left  || input.keyboard.key_held.a
    vx += SPEED if input.keyboard.key_held.right || input.keyboard.key_held.d
    vy -= SPEED if input.keyboard.key_held.down  || input.keyboard.key_held.s
    vy += SPEED if input.keyboard.key_held.up    || input.keyboard.key_held.w
    @facing_left = vx < 0 if vx != 0

    if vx != 0.0 && vy != 0.0
      vx *= 0.7071; vy *= 0.7071
    end

    r = RADIUS
    new_x = @x + vx
    new_y = @y + vy
    new_x = @x if (vx > 0 && Cave.blocks_movement?(cave_grid, (new_x + r).to_i, @y.to_i)) ||
                   (vx < 0 && Cave.blocks_movement?(cave_grid, (new_x - r).to_i, @y.to_i))
    new_y = @y if (vy > 0 && Cave.blocks_movement?(cave_grid, @x.to_i, (new_y + r).to_i)) ||
                   (vy < 0 && Cave.blocks_movement?(cave_grid, @x.to_i, (new_y - r).to_i))

    inner = Cave::TILE_SIZE
    @x = new_x.clamp(inner + r.to_f, 1280 - inner - r.to_f)
    @y = new_y.clamp(inner + r.to_f, 720  - inner - r.to_f)
    @hit_timer -= 1 if @hit_timer > 0
  end

  def take_hit(damage: 1)
    return if @hit_timer > 0
    @hp -= damage
    @hit_timer = HIT_COOLDOWN
  end

  def drain_sanity(amount)
    @sanity = (@sanity - amount).clamp(0, MAX_SANITY)
  end

  def recover_sanity(amount)
    @sanity = (@sanity + amount).clamp(0, MAX_SANITY)
  end

  def sanity_pct
    @sanity.to_f / MAX_SANITY
  end

  def low_sanity?
    @sanity < 30
  end

  def dead?
    @hp <= 0 || @sanity <= 0
  end

  def invincible?
    @hit_timer > 0
  end

  def stomp!(tick_count)
    @stomp_timer = STOMP_COOLDOWN
    @attack_tick = tick_count
    @attack_animator.reset(tick_count)
  end

  def attacking?(tick_count)
    @attack_tick && tick_count - @attack_tick < AttackFrames::ALL.length * ATTACK_FRAME_DURATION
  end

  def stomp_ready?
    @stomp_timer == 0
  end

  def stomp_cooldown_pct
    @stomp_timer.to_f / STOMP_COOLDOWN
  end

  def tick_stomp
    @stomp_timer -= 1 if @stomp_timer > 0
  end

  def radius
    RADIUS
  end

  def render(tick_count, sanity_pct: 1.0)
    flash = invincible? && (@hit_timer % 6 < 3)
    a     = flash ? 80 : 255
    g = (sanity_pct * 255).to_i
    b = (sanity_pct * 255).to_i
    if attacking?(tick_count)
      sprite = @attack_animator.sprite(tick_count, anchor_x: @x, anchor_y: @y, scale: SCALE)
    else
      sprite = @animator.sprite(tick_count, anchor_x: @x, anchor_y: @y, scale: SCALE)
    end
    sprite[:flip_horizontally] = @facing_left
    sprite[:a] = a
    sprite[:r] = 255
    sprite[:g] = g
    sprite[:b] = b
    pip_y = @y + WalkFrames::H * SCALE / 2 + 4
    pips  = MAX_HP.times.map do |i|
      filled = i < @hp
      { x: @x - MAX_HP * 7 + i * 14, y: pip_y, w: 10, h: 6,
        path: :solid, r: filled ? 220 : 60, g: filled ? 50 : 50, b: filled ? 50 : 60, a: 220 }
    end
    [sprite] + pips
  end
end
