class Hunter
  RADIUS     = 10
  TURN_SPEED = 0.07
  HIT_CD     = 40
  SCALE      = 1.6

  attr_accessor :x, :y, :vx, :vy, :hp, :hit_timer

  def self.create(x:, y:, animator:, kind: :inquisitor)
    klass = kind == :watcher ? Watcher : Inquisitor
    klass.new(x: x, y: y, animator: animator)
  end

  def initialize(x:, y:, animator:)
    @x = x.to_f; @y = y.to_f
    angle = rand * Math::PI * 2
    spd = base_speed
    @vx = Math.cos(angle) * spd
    @vy = Math.sin(angle) * spd
    @hp = max_hp
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

  # Subclasses override
  def kind;        raise NotImplementedError; end
  def base_speed;  raise NotImplementedError; end
  def max_hp;      raise NotImplementedError; end
  def steals_idols?; false; end
  def target(player, _placed_idols); { x: player.x, y: player.y }; end
  def aura_drain(_player); end
  def tint_sprite(_sprite); end
  def render_extras(_tick_count); []; end

  def update(tx, ty, wall_rects)
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
    if !Cave.circle_blocks?(wall_rects, nx, ny, r)
      @x = nx; @y = ny
    elsif @vx != 0 && !Cave.circle_blocks?(wall_rects, nx, @y, r)
      @x = nx
    elsif @vy != 0 && !Cave.circle_blocks?(wall_rects, @x, ny, r)
      @y = ny
    end
    b = Cave::STONE_FACE_PX
    @x = @x.clamp(b + r.to_f, 1280.0 - b - r.to_f)
    @y = @y.clamp(b + r.to_f, 720.0  - b - r.to_f)

    @hit_timer -= 1 if @hit_timer > 0
  end

  def render(tick_count)
    flash = @hit_timer > 0 && (@hit_timer % 6 < 3)
    return [] unless @animator
    sprite = @animator.sprite(tick_count, anchor_x: @x, anchor_y: @y, scale: SCALE)
    sprite[:flip_horizontally] = @vx < 0
    sprite[:a] = flash ? 80 : 255
    tint_sprite(sprite)
    pip_y = @y + HunterFrames::ALL.map { |f| f[:h] }.max * SCALE / 2 + 4
    pips = max_hp.times.map do |i|
      filled = i < @hp
      { x: @x - max_hp * 4 + i * 8, y: pip_y, w: 6, h: 4,
        path: :solid, r: filled ? 220 : 60, g: filled ? 40 : 40, b: filled ? 40 : 50, a: 200 }
    end
    render_extras(tick_count) + [sprite] + pips
  end
end

class Inquisitor < Hunter
  SPEED = 1.5
  HP    = 3

  def kind;       :inquisitor; end
  def base_speed; SPEED; end
  def max_hp;     HP; end
  def steals_idols?; true; end

  def target(player, placed_idols)
    return { x: player.x, y: player.y } if placed_idols.empty?
    nearest = placed_idols.min_by { |i| (i.x - @x)**2 + (i.y - @y)**2 }
    { x: nearest.x, y: nearest.y, idol: nearest }
  end
end

class Watcher < Hunter
  SPEED        = 0.6
  HP           = 4
  AURA_R       = 160
  SANITY_DRAIN = 0.05

  def kind;       :watcher; end
  def base_speed; SPEED; end
  def max_hp;     HP; end

  def aura_drain(player)
    dx = player.x - @x
    dy = player.y - @y
    return unless dx * dx + dy * dy < AURA_R * AURA_R
    player.drain_sanity(SANITY_DRAIN)
  end

  def tint_sprite(sprite)
    sprite[:r] = 140; sprite[:g] = 220; sprite[:b] = 140
  end

  def render_extras(tick_count)
    pulse = (Math.sin(tick_count * 0.05) * 0.3 + 0.7)
    d = (AURA_R * 2).to_i
    [{
      x: @x - d / 2, y: @y - d / 2, w: d, h: d,
      path: :solid, r: 80, g: 200, b: 80, a: (40 * pulse).to_i, blendmode_enum: 1
    }]
  end
end
