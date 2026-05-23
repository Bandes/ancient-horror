require 'app/sprite_animator'
require 'app/cave'
require 'app/boid'
require 'app/player'
require 'app/hunter'

CREATURE_COUNT        = 50
LARGE_FOR_WIN         = 2
MAX_SHOGGOTHS         = 120
SPAWN_INTERVAL        = 360   # new shoggoth every 6 seconds
SUMMON_TICKS_NEEDED   = 300   # hold altar 5 seconds to win
HUNTER_SPAWN_INTERVAL = 1800  # new hunter every 30 seconds
MAX_HUNTERS           = 3

def boot(args)
  args.state = {}
end

def tick(args)
  defaults(args)
  return if intro_screen(args)
  return if game_over_screen(args) || win_screen(args)

  handle_input(args)
  calc(args)
  check_merge(args)
  check_infighting(args)
  check_win(args)
  tick_hunters(args)
  tick_particles(args)
  render(args)
end

def defaults(args)
  return if args.state.initialized

  cave_data = Cave.generate
  args.state.cave_grid = cave_data[:grid]
  args.state.altar_x   = Cave.tile_center(cave_data[:altar_col], cave_data[:altar_row])[:x]
  args.state.altar_y   = Cave.tile_center(cave_data[:altar_col], cave_data[:altar_row])[:y]

  spawn = Cave.tile_center(cave_data[:spawn_col], cave_data[:spawn_row])
  args.state.player = Player.new(x: spawn[:x], y: spawn[:y])

  args.state.animator_factory = lambda {
    SpriteAnimator.new(
      path: 'sprites/creature.png',
      frames: CreatureFrames::ALL,
      frame_duration: Numeric.rand(4..7),
      start_tick: -rand(60)
    )
  }

  args.state.hunter_animator_factory = lambda {
    SpriteAnimator.new(
      path: 'sprites/hunter-run.png',
      frames: HunterFrames::ALL,
      frame_duration: 5,
      start_tick: -rand(40)
    )
  }

  args.state.cthulhu_idle   = SpriteAnimator.new(path: 'sprites/chthulu.png', frames: CthulhuFrames::IDLE,   frame_duration: 8)
  args.state.cthulhu_attack = SpriteAnimator.new(path: 'sprites/chthulu.png', frames: CthulhuFrames::ATTACK, frame_duration: 7)

  args.state.boids = Flock.spawn(
    CREATURE_COUNT,
    args.state.animator_factory,
    cave_grid: args.state.cave_grid
  )

  args.state.idols         = Array.new(6) { { placed: false, x: 0.0, y: 0.0 } }
  args.state.won           = false
  args.state.game_over     = false
  args.state.summon_ticks  = 0
  args.state.ritual_stage  = 0 # 0-3: how many large shoggoths have reached altar
  args.state.particles     = []
  args.state.hunters       = []
  args.state.hunter_timer  = 0
  args.state.floor_cells   = Cave.floor_cells(args.state.cave_grid)
  exclude = [[cave_data[:spawn_col], cave_data[:spawn_row]],
             [cave_data[:altar_col], cave_data[:altar_row]]]
  props = Cave.generate_props(args.state.cave_grid, exclude)
  args.state.prop_colliders = props.map { |p| { cx: p[:cx], cy: p[:cy], cr: p[:cr] } }
  args.state.bg_sprites = Cave.render(args.state.cave_grid) + props.map { |p| p[:sprite] }
  args.state.intro         = true
  args.state.start_tick    = nil
  args.state.initialized   = true
end

IDOL_INTERACT_RADIUS = 40

def resolve_prop_collisions(x, y, r, prop_colliders)
  prop_colliders.each do |p|
    dx = x - p[:cx]
    dy = y - p[:cy]
    min_d = r + p[:cr]
    d2 = dx * dx + dy * dy
    next if d2 >= min_d * min_d || d2 < 0.0001

    d = Math.sqrt(d2)
    push = min_d - d
    x += dx / d * push
    y += dy / d * push
  end
  [x, y]
end

def handle_input(args)
  player = args.state.player
  player.update(args.inputs, args.state.cave_grid)
  player.x, player.y = resolve_prop_collisions(player.x, player.y, Player::RADIUS, args.state.prop_colliders)

  return unless args.inputs.keyboard.key_down.space

  args.state.idols.each do |idol|
    next unless idol[:placed]

    dx = idol[:x] - player.x
    dy = idol[:y] - player.y
    next unless dx * dx + dy * dy < IDOL_INTERACT_RADIUS * IDOL_INTERACT_RADIUS

    idol[:placed] = false
    player.idols_held += 1
    return
  end

  return unless player.idols_held > 0

  idol = args.state.idols.find { |id| !id[:placed] }
  return unless idol

  idol[:placed] = true
  idol[:x] = player.x
  idol[:y] = player.y
  player.idols_held -= 1
end

def calc(args)
  player = args.state.player
  player.tick_stomp

  # Stomp: E key blasts nearby shoggoths away
  if args.inputs.keyboard.key_down.e && player.stomp_ready?
    player.stomp!
    stomp_r_sq = Player::STOMP_RADIUS**2
    args.state.boids.each do |b|
      dx = b.x - player.x
      dy = b.y - player.y
      d2 = dx * dx + dy * dy
      next if d2 > stomp_r_sq || d2 < 0.0001

      d     = Math.sqrt(d2)
      force = Player::STOMP_FORCE * (1.0 - d / Player::STOMP_RADIUS)
      b.vx += dx / d * force
      b.vy += dy / d * force
    end
    args.state.hunters.each do |h|
      dx = h.x - player.x; dy = h.y - player.y
      d2 = dx * dx + dy * dy
      next if d2 > stomp_r_sq || d2 < 0.0001
      d = Math.sqrt(d2)
      force = Player::STOMP_FORCE * 1.5 * (1.0 - d / Player::STOMP_RADIUS)
      h.vx += dx / d * force; h.vy += dy / d * force
      h.take_hit
    end
    args.state.stomp_flash = 8
  end
  args.state.stomp_flash = [(args.state.stomp_flash || 0) - 1, 0].max

  Flock.step(
    args.state.boids,
    cave_grid: args.state.cave_grid,
    idols: args.state.idols,
    altar_x: args.state.altar_x,
    altar_y: args.state.altar_y,
    player_x: player.x,
    player_y: player.y,
    ritual_stage: args.state.ritual_stage
  )

  prop_colliders = args.state.prop_colliders
  args.state.boids.each do |b|
    b.x, b.y = resolve_prop_collisions(b.x, b.y, b.collision_r, prop_colliders)
  end

  # Medium/large shoggoths bud off small ones periodically
  spawned = []
  args.state.boids.each do |b|
    next if b.tier < 2

    b.spawn_timer -= 1
    next if b.spawn_timer > 0

    interval = b.tier == 2 ? 480 : 300
    b.spawn_timer = interval + rand(interval)
    next if args.state.boids.length + spawned.length >= MAX_SHOGGOTHS

    angle = rand * Math::PI * 2
    offset = b.collision_r + Boid::TIER_R[1] + 4
    spawned << Boid.new(
      x: b.x + Math.cos(angle) * offset,
      y: b.y + Math.sin(angle) * offset,
      vx: Math.cos(angle) * Flock::MIN_SPEED,
      vy: Math.sin(angle) * Flock::MIN_SPEED,
      bias_x: Math.cos(angle), bias_y: Math.sin(angle),
      animator: args.state.animator_factory.call,
      personality: { speed_scale: 0.75 + rand * 0.5, wander_scale: 0.6 + rand * 0.8, bias_scale: 0.5 + rand * 1.0 },
      tier: 1
    )
  end
  args.state.boids.concat(spawned)

  nearby_count = 0
  args.state.boids.each do |b|
    dx = b.x - player.x
    dy = b.y - player.y
    d2 = dx * dx + dy * dy
    nearby_count += 1 if d2 < 150 * 150
    next if player.invincible?

    min_d = b.collision_r + player.radius
    if d2 < min_d * min_d
      dmg = b.tier == 3 ? 2 : 1
      player.take_hit(damage: dmg)
    end
  end

  if nearby_count > 0
    player.drain_sanity(0.008 + nearby_count * 0.001)
  else
    player.recover_sanity(0.03)
  end

  args.state.game_over = true if player.dead?

  return unless args.state.boids.length < MAX_SHOGGOTHS && Kernel.tick_count % SPAWN_INTERVAL == 0

  spawn_shoggoth(args)
end

def spawn_shoggoth(args)
  player = args.state.player
  cells  = args.state.floor_cells

  # Prefer cells far from player
  far = cells.select do |c, r|
    px = c * Cave::TILE_SIZE + Cave::TILE_SIZE / 2
    py = r * Cave::TILE_SIZE + Cave::TILE_SIZE / 2
    (px - player.x)**2 + (py - player.y)**2 > 200**2
  end
  col, row = (far.empty? ? cells : far).sample
  return unless col

  x = col * Cave::TILE_SIZE + Cave::TILE_SIZE / 2
  y = row * Cave::TILE_SIZE + Cave::TILE_SIZE / 2
  angle = rand * Math::PI * 2
  args.state.boids << Boid.new(
    x: x, y: y,
    vx: Math.cos(angle) * Flock::MIN_SPEED,
    vy: Math.sin(angle) * Flock::MIN_SPEED,
    bias_x: Math.cos(angle), bias_y: Math.sin(angle),
    animator: args.state.animator_factory.call,
    personality: { speed_scale: 0.75 + rand * 0.5, wander_scale: 0.6 + rand * 0.8, bias_scale: 0.5 + rand * 1.0 },
    tier: 1
  )
end

def check_merge(args)
  merge_r_sq = Cave::MERGE_RADIUS * Cave::MERGE_RADIUS
  boids      = args.state.boids
  factory    = args.state.animator_factory

  args.state.idols.each do |idol|
    next unless idol[:placed]

    { 1 => 8, 2 => 4 }.each do |tier, threshold|
      nearby = boids.select do |b|
        b.tier == tier &&
          (b.x - idol[:x])**2 + (b.y - idol[:y])**2 < merge_r_sq
      end
      next if nearby.length < threshold

      nearby.first(threshold).each { |b| boids.delete(b) }

      angle = rand * Math::PI * 2
      boids << Boid.new(
        x: idol[:x], y: idol[:y],
        vx: Math.cos(angle) * Flock::MIN_SPEED,
        vy: Math.sin(angle) * Flock::MIN_SPEED,
        bias_x: Math.cos(angle), bias_y: Math.sin(angle),
        animator: factory.call,
        personality: { speed_scale: 0.9, wander_scale: 0.7, bias_scale: 0.6 },
        tier: tier + 1
      )

      pr, pg, pb = tier == 1 ? [80, 255, 120] : [200, 80, 255]
      emit_particles(args, idol[:x], idol[:y], 20, r: pr, g: pg, b: pb, speed: 3.5, size: 6)
      args.state.merge_flash = 6

      idol[:placed] = false
      args.state.player.idols_held += 1
      break
    end
  end
end

def check_win(args)
  altar_r_sq = Cave::ALTAR_RADIUS * Cave::ALTAR_RADIUS
  ax = args.state.altar_x
  ay = args.state.altar_y

  large_at_altar = args.state.boids.count do |b|
    b.tier == 3 && (b.x - ax)**2 + (b.y - ay)**2 < altar_r_sq
  end

  # Ritual stage: how many large shoggoths have gathered (ratchets up only)
  args.state.ritual_stage = [args.state.ritual_stage, large_at_altar].max

  pdx = args.state.player.x - ax
  pdy = args.state.player.y - ay
  player_at_altar = pdx * pdx + pdy * pdy < Cave::ALTAR_RADIUS * Cave::ALTAR_RADIUS

  if large_at_altar >= LARGE_FOR_WIN && player_at_altar
    args.state.summon_ticks += 1
    if Kernel.tick_count % 4 == 0
      emit_particles(args, ax, ay, 3, r: 160 + rand(60), g: 40, b: 240 + rand(15), speed: 1.2 + rand * 0.8, size: 5)
    end
    if args.state.summon_ticks >= SUMMON_TICKS_NEEDED
      args.state.won = true
      args.state.end_tick ||= Kernel.tick_count
    end
  else
    # Drain slowly if not holding
    args.state.summon_ticks = [args.state.summon_ticks - 2, 0].max
  end
end

def intro_screen(args)
  return false unless args.state.intro

  args.outputs.background_color = [5, 3, 12]
  args.outputs.labels << { x: 640, y: 520, text: 'ANCIENT AND NAMELESS',
                           alignment_enum: 1, size_enum: 10, r: 160, g: 80, b: 255, a: 255 }
  args.outputs.labels << { x: 640, y: 458, text: 'You are an acolyte of the Old Ones. Legend has it that one awaits deep beneath the earth.',
                           alignment_enum: 1, size_enum: 2, r: 180, g: 150, b: 220, a: 255 }
  args.outputs.labels << { x: 640, y: 425, text: 'It is your job to awaken it and bring about a New Age. The stars align. The altar waits.',
                           alignment_enum: 1, size_enum: 2, r: 180, g: 150, b: 220, a: 255 }
  args.outputs.labels << { x: 640, y: 380, text: 'Place idols [ SPACE ] to lure shoggoths.',
                           alignment_enum: 1, size_enum: 0, r: 200, g: 200, b: 200, a: 255 }
  args.outputs.labels << { x: 640, y: 350, text: '8 small shoggoths merge near an idol. 4 medium ones merge into a large. March them to the altar.',
                           alignment_enum: 1, size_enum: 0, r: 200, g: 200, b: 200, a: 255 }
  args.outputs.labels << { x: 640, y: 320, text: 'Hold the altar with 2 great ones to complete the ritual.',
                           alignment_enum: 1, size_enum: 0, r: 200, g: 200, b: 200, a: 255 }
  args.outputs.labels << { x: 640, y: 270, text: '[ E ] Stomp — blasts shoggoths and hunters back',
                           alignment_enum: 1, size_enum: 0, r: 180, g: 160, b: 200, a: 255 }
  args.outputs.labels << { x: 640, y: 245, text: 'Inquisitors will hunt your idols. Stay calm. Your sanity will not hold forever.',
                           alignment_enum: 1, size_enum: 0, r: 160, g: 100, b: 140, a: 255 }
  args.outputs.labels << { x: 640, y: 170, text: 'press any key to begin',
                           alignment_enum: 1, size_enum: 0, r: 120, g: 120, b: 140, a: (Math.sin(Kernel.tick_count * 0.06) * 80 + 170).to_i }
  kd = args.inputs.keyboard.key_down
  if kd.space || kd.enter || kd.e || kd.w || kd.a || kd.s || kd.d ||
     kd.up || kd.down || kd.left || kd.right || args.inputs.mouse.click
    args.state.intro = false
    args.state.start_tick = Kernel.tick_count
  end
  true
end

def game_over_screen(args)
  return false unless args.state.game_over

  render_base(args)
  args.outputs.labels << { x: 640, y: 400, text: 'YOU HAVE BEEN CONSUMED',
                           alignment_enum: 1, size_enum: 8, r: 255, g: 50, b: 50, a: 255 }
  args.outputs.labels << { x: 640, y: 355, text: 'click to restart',
                           alignment_enum: 1, r: 200, g: 200, b: 200, a: 255 }
  args.state = {} if args.inputs.mouse.click
  true
end

def win_screen(args)
  return false unless args.state.won

  render_base(args)

  age = args.state.end_tick ? Kernel.tick_count - args.state.end_tick : 0

  # Dark overlay fades in
  fade_a = [age * 3, 180].min
  args.outputs.sprites << { x: 0, y: 0, w: 1280, h: 720, path: :solid, r: 5, g: 0, b: 15, a: fade_a }

  # Emit purple particles from Cthulhu position while visible
  if age > 30 && age % 3 == 0
    emit_particles(args, 640, 320, 3, r: 120 + rand(80), g: 20, b: 220 + rand(35), speed: 2.5, size: 5)
  end
  args.state.particles.each { |p| p[:x] += p[:dx]; p[:y] += p[:dy]; p[:dx] *= 0.93; p[:dy] *= 0.93; p[:a] -= 5 }
  args.state.particles.reject! { |p| p[:a] <= 0 }
  args.outputs.sprites << args.state.particles

  # Choose animation: attack after 3 seconds
  anim = age > 180 ? args.state.cthulhu_attack : args.state.cthulhu_idle
  if anim
    sprite = anim.sprite(Kernel.tick_count, anchor_x: 640, anchor_y: 320, scale: 4.0)
    sprite_a = [age * 4, 255].min
    sprite[:a] = sprite_a
    args.outputs.sprites << sprite
  end

  elapsed = args.state.end_tick && args.state.start_tick ? args.state.end_tick - args.state.start_tick : 0
  secs = elapsed.idiv(60)
  time_str = "#{secs.idiv(60)}m #{secs % 60}s"

  text_a = [((age - 60) * 5), 255].min.clamp(0, 255)
  args.outputs.labels << { x: 640, y: 530, text: 'THE ANCIENT ONE RISES',
                           alignment_enum: 1, size_enum: 8, r: 180, g: 80, b: 255, a: text_a }
  args.outputs.labels << { x: 640, y: 485, text: 'THE WORLD IS UNMADE',
                           alignment_enum: 1, size_enum: 4, r: 220, g: 160, b: 255, a: text_a }
  args.outputs.labels << { x: 640, y: 120, text: "Ritual completed in #{time_str}",
                           alignment_enum: 1, size_enum: 1, r: 180, g: 140, b: 255, a: text_a }
  args.outputs.labels << { x: 640, y: 80, text: 'click to play again',
                           alignment_enum: 1, r: 140, g: 140, b: 160, a: text_a }
  args.state = {} if args.inputs.mouse.click
  true
end

def emit_particles(args, x, y, count, r:, g:, b:, speed: 2.0, size: 5)
  count.times do
    angle = rand * Math::PI * 2
    spd   = speed * (0.5 + rand * 0.8)
    args.state.particles << {
      x: x, y: y, w: size, h: size,
      dx: Math.cos(angle) * spd, dy: Math.sin(angle) * spd,
      a: 255, path: :solid, r: r, g: g, b: b, blendmode_enum: 1
    }
  end
end

def tick_particles(args)
  args.state.particles.each do |p|
    p[:x] += p[:dx]; p[:y] += p[:dy]
    p[:dx] *= 0.93; p[:dy] *= 0.93
    p[:a]  -= 7
  end
  args.state.particles.reject! { |p| p[:a] <= 0 }
  args.state.merge_flash = [(args.state.merge_flash || 0) - 1, 0].max
end

def check_infighting(args)
  eaten = []
  args.state.boids.each do |predator|
    next if predator.tier < 3
    eat_r = predator.collision_r - 4
    args.state.boids.each do |prey|
      next if prey.tier == 3 || eaten.include?(prey)
      dx = predator.x - prey.x; dy = predator.y - prey.y
      next unless dx * dx + dy * dy < eat_r * eat_r
      eaten << prey
      emit_particles(args, prey.x, prey.y, 8, r: 80, g: 210, b: 80, speed: 1.5, size: 4)
    end
  end
  args.state.boids -= eaten unless eaten.empty?

  args.state.hunters.reject! do |h|
    args.state.boids.any? do |b|
      dx = b.x - h.x; dy = b.y - h.y
      eat_r = b.collision_r + Hunter::RADIUS - 6
      next unless dx * dx + dy * dy < eat_r * eat_r
      emit_particles(args, h.x, h.y, 10, r: 200, g: 20, b: 20, speed: 2.0, size: 5)
      true
    end
  end
end

def tick_hunters(args)
  player = args.state.player
  args.state.hunter_timer += 1
  if args.state.hunter_timer >= HUNTER_SPAWN_INTERVAL && args.state.hunters.length < MAX_HUNTERS
    args.state.hunter_timer = 0
    spawn_hunter(args)
  end

  placed_idols = args.state.idols.select { |i| i[:placed] }

  args.state.hunters.each do |h|
    target = placed_idols.empty? ? { x: player.x, y: player.y } :
             placed_idols.min_by { |i| (i[:x] - h.x)**2 + (i[:y] - h.y)**2 }
    h.update(target[:x], target[:y], args.state.cave_grid)
    h.x, h.y = resolve_prop_collisions(h.x, h.y, Hunter::RADIUS, args.state.prop_colliders)

    args.state.idols.each do |idol|
      next unless idol[:placed]
      dx = h.x - idol[:x]; dy = h.y - idol[:y]
      next unless dx * dx + dy * dy < (Hunter::RADIUS + 14)**2
      idol[:placed] = false
      player.idols_held += 1
      emit_particles(args, idol[:x], idol[:y], 14, r: 255, g: 100, b: 20, speed: 2.5, size: 5)
    end

    dx = h.x - player.x; dy = h.y - player.y
    player.take_hit if dx * dx + dy * dy < (Hunter::RADIUS + player.radius)**2
  end

  args.state.hunters.reject!(&:dead?)
end

def spawn_hunter(args)
  player = args.state.player
  far = args.state.floor_cells.select do |c, r|
    px = c * Cave::TILE_SIZE + Cave::TILE_SIZE / 2
    py = r * Cave::TILE_SIZE + Cave::TILE_SIZE / 2
    (px - player.x)**2 + (py - player.y)**2 > 300**2
  end
  col, row = (far.empty? ? args.state.floor_cells : far).sample
  return unless col
  args.state.hunters << Hunter.new(
    x: col * Cave::TILE_SIZE + Cave::TILE_SIZE / 2,
    y: row * Cave::TILE_SIZE + Cave::TILE_SIZE / 2,
    animator: args.state.hunter_animator_factory.call
  )
end

def render_base(args)
  args.outputs.sprites << args.state.bg_sprites
  args.outputs.sprites << (args.state.particles || [])
  args.outputs.sprites << (args.state.boids || []).map { |b| b.render(Kernel.tick_count) }
  args.outputs.sprites << (args.state.hunters || []).map { |h| h.render(Kernel.tick_count) }
end

def render(args)
  args.outputs.sprites << args.state.bg_sprites
  render_altar(args)
  render_idols(args)

  args.outputs.sprites << (args.state.particles || [])
  args.outputs.sprites << (args.state.boids || []).map { |b| b.render(Kernel.tick_count) }
  args.outputs.sprites << (args.state.hunters || []).map { |h| h.render(Kernel.tick_count) }
  args.outputs.sprites << args.state.player.render(Kernel.tick_count, sanity_pct: args.state.player.sanity_pct)

  # Merge flash
  if (args.state.merge_flash || 0) > 0
    a = (args.state.merge_flash * 25).clamp(0, 120)
    args.outputs.sprites << { x: 0, y: 0, w: 1280, h: 720, path: :solid, r: 160, g: 255, b: 180, a: a }
  end

  render_hud(args)
end

ALTAR_SPRITE_W = 80
ALTAR_SPRITE_H = 80

def render_altar(args)
  ax = args.state.altar_x
  ay = args.state.altar_y
  stage = args.state.ritual_stage
  pulse = (Math.sin(Kernel.tick_count * 0.08) * 0.5 + 0.5)

  # Glow behind the sprite, intensifies with ritual stage
  base_r = 60 + stage * 40
  base_g = 20 + stage * 10
  base_b = 160 + stage * 25
  glow_a = (80 + stage * 35 + pulse * 40).to_i.clamp(0, 255)
  glow_size = (ALTAR_SPRITE_W * 1.6 + stage * 8 + pulse * 6).to_i
  args.outputs.sprites << {
    x: ax - glow_size / 2, y: ay - glow_size / 2, w: glow_size, h: glow_size,
    path: :solid, r: base_r, g: base_g, b: base_b, a: glow_a
  }

  # Altar sprite — tinted green as ritual advances
  tint_g = (180 + stage * 25).clamp(0, 255)
  args.outputs.sprites << {
    x: ax - ALTAR_SPRITE_W / 2, y: ay - ALTAR_SPRITE_H / 2,
    w: ALTAR_SPRITE_W, h: ALTAR_SPRITE_H,
    path: 'sprites/altar.png',
    r: 255, g: tint_g, b: 255, a: 255, blendmode_enum: 1
  }

  # Summoning progress bar above altar
  return unless args.state.summon_ticks > 0

  pct   = args.state.summon_ticks.to_f / SUMMON_TICKS_NEEDED
  bar_w = 80
  bar_y = ay + ALTAR_SPRITE_H / 2 + 6
  args.outputs.sprites << { x: ax - bar_w / 2, y: bar_y, w: bar_w, h: 6,
                            path: :solid, r: 40, g: 40, b: 40, a: 200 }
  args.outputs.sprites << { x: ax - bar_w / 2, y: bar_y, w: (bar_w * pct).to_i, h: 6,
                            path: :solid, r: 180, g: 80, b: 255, a: 255 }
  args.outputs.labels << { x: ax, y: bar_y + 16, text: 'HOLD!',
                           alignment_enum: 1, size_enum: -2, r: 220, g: 150, b: 255, a: 255 }
end

def render_idols(args)
  args.state.idols.each do |idol|
    next unless idol[:placed]

    pulse = (Math.sin(Kernel.tick_count * 0.12) * 20 + 200).to_i
    args.outputs.sprites << {
      x: idol[:x] - 8, y: idol[:y] - 8, w: 16, h: 16,
      path: :solid, r: pulse, g: 210, b: 50, a: 255
    }
  end
end

def render_hud(args)
  player = args.state.player
  stage  = args.state.ritual_stage

  counts = [0, 0, 0]
  args.state.boids.each { |b| counts[b.tier - 1] += 1 }

  hunter_str = args.state.hunters.length > 0 ? "  Hunters: #{args.state.hunters.length}" : ''
  args.outputs.labels << {
    x: 10, y: 710,
    text: "Idols: #{player.idols_held}  HP: #{player.hp}  " \
          "Small: #{counts[0]}  Medium: #{counts[1]}  Large: #{counts[2]}" \
          "#{hunter_str}  FPS: #{args.gtk.current_framerate.to_i}",
    r: 255, g: 255, b: 255, a: 255
  }

  # Sanity bar (top-right)
  san_w = 120
  san_pct = player.sanity_pct
  san_fill = (san_w * san_pct).to_i
  san_r = (255 * (1.0 - san_pct)).to_i
  san_g = (180 * san_pct).to_i
  args.outputs.labels << { x: 1270, y: 710, text: 'SANITY',
                           alignment_enum: 2, size_enum: -2, r: 200, g: 180, b: 220, a: 255 }
  args.outputs.sprites << { x: 1270 - san_w, y: 692, w: san_w, h: 6,
                            path: :solid, r: 40, g: 20, b: 40, a: 200 }
  args.outputs.sprites << { x: 1270 - san_w, y: 692, w: san_fill, h: 6,
                            path: :solid, r: san_r, g: san_g, b: 200, a: 255 }

  # Stomp cooldown bar (bottom-left)
  bar_w = 80
  ready = player.stomp_ready?
  args.outputs.labels << { x: 10, y: 24, text: ready ? '[E] STOMP' : '[E] ...',
                           size_enum: -2, r: ready ? 255 : 140, g: ready ? 200 : 140, b: ready ? 80 : 140, a: 255 }
  args.outputs.sprites << { x: 10, y: 28, w: bar_w, h: 5,
                            path: :solid, r: 40, g: 40, b: 40, a: 180 }
  fill = ready ? bar_w : ((1.0 - player.stomp_cooldown_pct) * bar_w).to_i
  args.outputs.sprites << { x: 10, y: 28, w: fill, h: 5,
                            path: :solid, r: 255, g: 180, b: 50, a: 255 }

  # Stomp flash ring
  if (args.state.stomp_flash || 0) > 0
    r = Player::STOMP_RADIUS * (1.0 - args.state.stomp_flash / 8.0)
    a = (args.state.stomp_flash * 30).clamp(0, 220)
    args.outputs.sprites << { x: player.x - r, y: player.y - r, w: r * 2, h: r * 2,
                              path: :solid, r: 255, g: 220, b: 80, a: a }
  end

  # Ritual stage indicator bottom-right
  stage_text = if stage == 0
                 'Altar: dormant'
               elsif stage == 1
                 'Altar: stirring'
               elsif stage == 2
                 'Altar: awakening'
               else
                 'Altar: CONVERGE AND HOLD'
               end
  stage_r = [80 + stage * 50, 255].min
  args.outputs.labels << {
    x: 1270, y: 30,
    text: stage_text,
    alignment_enum: 2, r: stage_r, g: 80, b: 220, a: 255
  }
end
