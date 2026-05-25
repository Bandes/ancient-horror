class Player
  SPEED          = 2.5
  MAX_HP         = 5
  MAX_SANITY     = 100
  HIT_COOLDOWN   = 60
  RADIUS         = 12
  REPEL_COOLDOWN       = 150
  REPEL_RADIUS         = 110
  REPEL_KILL_RADIUS    = 55
  REPEL_FORCE          = 2.2
  SCALE                = 1.0
  ATTACK_FRAME_DURATION = 4

  attr_accessor :x, :y, :hp, :sanity, :hit_timer, :idols_held, :max_hp, :max_sanity,
                :sanity_drain_scale, :sanity_recover_scale, :repel_cd_scale

  def initialize(x:, y:, max_hp: MAX_HP, max_sanity: MAX_SANITY, starting_idols: 2)
    @x              = x.to_f
    @y              = y.to_f
    @max_hp         = max_hp
    @max_sanity     = max_sanity
    @hp             = @max_hp
    @sanity         = @max_sanity
    @hit_timer      = 0
    @idols_held     = starting_idols
    @sanity_drain_scale   = 1.0
    @sanity_recover_scale = 1.0
    @repel_cd_scale       = 1.0
    @speed_scale          = 1.0
    @facing_left    = false
    @repel_timer    = 0
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

  attr_accessor :speed_scale

  def update(input, cave_grid)
    speed = SPEED * (@speed_scale || 1.0)
    vx = 0.0; vy = 0.0
    vx -= speed if input.keyboard.key_held.left  || input.keyboard.key_held.a
    vx += speed if input.keyboard.key_held.right || input.keyboard.key_held.d
    vy -= speed if input.keyboard.key_held.down  || input.keyboard.key_held.s
    vy += speed if input.keyboard.key_held.up    || input.keyboard.key_held.w
    @facing_left = vx < 0 if vx != 0

    if vx != 0.0 && vy != 0.0
      vx *= 0.7071; vy *= 0.7071
    end

    r = RADIUS
    tx = @x + vx
    ty = @y + vy
    if !Cave.blocks_circle?(cave_grid, tx, ty, r)
      @x = tx; @y = ty
    elsif vx != 0.0 && !Cave.blocks_circle?(cave_grid, tx, @y, r)
      @x = tx
    elsif vy != 0.0 && !Cave.blocks_circle?(cave_grid, @x, ty, r)
      @y = ty
    end

    inner = Cave::TILE_SIZE
    @x = @x.clamp(inner + r.to_f, 1280 - inner - r.to_f)
    @y = @y.clamp(inner + r.to_f, 720  - inner - r.to_f)
    @hit_timer -= 1 if @hit_timer > 0
  end

  def take_hit(damage: 1)
    return if @hit_timer > 0
    @hp -= damage
    @hit_timer = HIT_COOLDOWN
  end

  def drain_sanity(amount)
    @sanity = (@sanity - amount * @sanity_drain_scale).clamp(0, @max_sanity)
  end

  def recover_sanity(amount)
    @sanity = (@sanity + amount * @sanity_recover_scale).clamp(0, @max_sanity)
  end

  def sanity_pct
    @sanity.to_f / @max_sanity
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

  def repel!(tick_count)
    @repel_timer = (REPEL_COOLDOWN * @repel_cd_scale).to_i
    @attack_tick = tick_count
    @attack_animator.reset(tick_count)
  end

  def effective_repel_cd
    [(REPEL_COOLDOWN * @repel_cd_scale).to_i, 1].max
  end

  def attacking?(tick_count)
    @attack_tick && tick_count - @attack_tick < AttackFrames::ALL.length * ATTACK_FRAME_DURATION
  end

  def repel_ready?
    @repel_timer == 0
  end

  def repel_cooldown_pct
    @repel_timer.to_f / effective_repel_cd
  end

  def tick_repel
    @repel_timer -= 1 if @repel_timer > 0
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
    pips  = @max_hp.times.map do |i|
      filled = i < @hp
      { x: @x - @max_hp * 7 + i * 14, y: pip_y, w: 10, h: 6,
        path: :solid, r: filled ? 220 : 60, g: filled ? 50 : 50, b: filled ? 50 : 60, a: 220 }
    end
    [sprite] + pips
  end
end
