require 'app/sprite_animator.rb'
require 'app/cave.rb'
require 'app/boid.rb'
require 'app/player.rb'

CREATURE_COUNT       = 50
LARGE_FOR_WIN        = 3
MAX_SHOGGOTHS        = 120
SPAWN_INTERVAL       = 360   # new shoggoth every 6 seconds
SUMMON_TICKS_NEEDED  = 300   # hold altar 5 seconds to win

def boot(args)
  args.state = {}
end

def tick(args)
  defaults(args)
  return if game_over_screen(args) || win_screen(args)
  handle_input(args)
  calc(args)
  check_merge(args)
  check_win(args)
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
      frame_duration: 4 + rand(4),
      start_tick: -rand(60)
    )
  }

  args.state.boids = Flock.spawn(
    CREATURE_COUNT,
    args.state.animator_factory,
    cave_grid: args.state.cave_grid
  )

  args.state.idols         = Array.new(6) { { placed: false, x: 0.0, y: 0.0 } }
  args.state.won           = false
  args.state.game_over     = false
  args.state.summon_ticks  = 0
  args.state.ritual_stage  = 0   # 0-3: how many large shoggoths have reached altar
  args.state.floor_cells   = Cave.floor_cells(args.state.cave_grid)
  args.state.tile_sprites  = Cave.render(args.state.cave_grid)
  args.state.initialized   = true
end

IDOL_INTERACT_RADIUS = 40

def handle_input(args)
  player = args.state.player
  player.update(args.inputs, args.state.cave_grid)

  return unless args.inputs.keyboard.key_down.space

  args.state.idols.each do |idol|
    next unless idol[:placed]
    dx = idol[:x] - player.x; dy = idol[:y] - player.y
    if dx * dx + dy * dy < IDOL_INTERACT_RADIUS * IDOL_INTERACT_RADIUS
      idol[:placed] = false
      player.idols_held += 1
      return
    end
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
  Flock.step(
    args.state.boids,
    cave_grid: args.state.cave_grid,
    idols:     args.state.idols,
    altar_x:   args.state.altar_x,
    altar_y:   args.state.altar_y
  )

  player = args.state.player
  args.state.boids.each do |b|
    next if player.invincible?
    dx = b.x - player.x; dy = b.y - player.y
    min_d = b.collision_r + player.radius
    player.take_hit if dx * dx + dy * dy < min_d * min_d
  end

  args.state.game_over = true if player.dead?

  # Spawn new shoggoths over time — escalating pressure
  if args.state.boids.length < MAX_SHOGGOTHS && Kernel.tick_count % SPAWN_INTERVAL == 0
    spawn_shoggoth(args)
  end
end

def spawn_shoggoth(args)
  player = args.state.player
  cells  = args.state.floor_cells

  # Prefer cells far from player
  far = cells.select { |c, r|
    px = c * Cave::TILE_SIZE + Cave::TILE_SIZE / 2
    py = r * Cave::TILE_SIZE + Cave::TILE_SIZE / 2
    (px - player.x) ** 2 + (py - player.y) ** 2 > 200 ** 2
  }
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

    [1, 2].each do |tier|
      nearby = boids.select { |b|
        b.tier == tier &&
          (b.x - idol[:x]) ** 2 + (b.y - idol[:y]) ** 2 < merge_r_sq
      }
      next if nearby.length < Cave::MERGE_THRESHOLD

      nearby.first(Cave::MERGE_THRESHOLD).each { |b| boids.delete(b) }

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

      idol[:placed] = false
      args.state.player.idols_held += 1
      break
    end
  end
end

def check_win(args)
  altar_r_sq = Cave::ALTAR_RADIUS * Cave::ALTAR_RADIUS
  ax = args.state.altar_x; ay = args.state.altar_y

  large_at_altar = args.state.boids.count { |b|
    b.tier == 3 && (b.x - ax) ** 2 + (b.y - ay) ** 2 < altar_r_sq
  }

  # Ritual stage: how many large shoggoths have gathered (ratchets up only)
  args.state.ritual_stage = [args.state.ritual_stage, large_at_altar].max

  pdx = args.state.player.x - ax
  pdy = args.state.player.y - ay
  player_at_altar = pdx * pdx + pdy * pdy < Cave::ALTAR_RADIUS * Cave::ALTAR_RADIUS

  if large_at_altar >= LARGE_FOR_WIN && player_at_altar
    args.state.summon_ticks += 1
    args.state.won = true if args.state.summon_ticks >= SUMMON_TICKS_NEEDED
  else
    # Drain slowly if not holding
    args.state.summon_ticks = [args.state.summon_ticks - 2, 0].max
  end
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
  args.outputs.labels << { x: 640, y: 410, text: 'THE ANCIENT ONE RISES',
    alignment_enum: 1, size_enum: 8, r: 120, g: 60, b: 220, a: 255 }
  args.outputs.labels << { x: 640, y: 365, text: 'THE WORLD IS UNMADE',
    alignment_enum: 1, size_enum: 4, r: 200, g: 150, b: 255, a: 255 }
  args.outputs.labels << { x: 640, y: 330, text: 'click to play again',
    alignment_enum: 1, r: 160, g: 160, b: 160, a: 255 }
  args.state = {} if args.inputs.mouse.click
  true
end

def render_base(args)
  args.outputs.sprites << args.state.tile_sprites
  args.outputs.sprites << args.state.boids.map { |b| b.render(Kernel.tick_count) }
end

def render(args)
  args.outputs.sprites << args.state.tile_sprites

  render_altar(args)
  render_idols(args)

  args.outputs.sprites << args.state.boids.map { |b| b.render(Kernel.tick_count) }
  args.outputs.sprites << args.state.player.render(Kernel.tick_count)

  render_hud(args)
end

def render_altar(args)
  ax = args.state.altar_x; ay = args.state.altar_y
  stage = args.state.ritual_stage
  pulse = (Math.sin(Kernel.tick_count * 0.08) * 0.5 + 0.5)

  # Altar glow intensifies with ritual stage
  base_r = 80 + stage * 40
  base_g = 30 + stage * 10
  base_b = 180 + stage * 20
  glow_a = (120 + stage * 30 + pulse * 30).to_i.clamp(0, 255)

  size = 44 + stage * 6 + (pulse * 4).to_i
  args.outputs.sprites << {
    x: ax - size / 2, y: ay - size / 2, w: size, h: size,
    path: :solid, r: base_r, g: base_g, b: base_b, a: glow_a
  }

  # Summoning progress arc (bar above altar)
  if args.state.summon_ticks > 0
    pct   = args.state.summon_ticks.to_f / SUMMON_TICKS_NEEDED
    bar_w = 80
    args.outputs.sprites << { x: ax - bar_w / 2, y: ay + 30, w: bar_w, h: 6,
      path: :solid, r: 40, g: 40, b: 40, a: 200 }
    args.outputs.sprites << { x: ax - bar_w / 2, y: ay + 30, w: (bar_w * pct).to_i, h: 6,
      path: :solid, r: 180, g: 80, b: 255, a: 255 }
    args.outputs.labels << { x: ax, y: ay + 46, text: 'HOLD!',
      alignment_enum: 1, size_enum: -2, r: 220, g: 150, b: 255, a: 255 }
  end
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

  # Shoggoth counts by tier
  counts = [0, 0, 0]
  args.state.boids.each { |b| counts[b.tier - 1] += 1 }

  args.outputs.labels << {
    x: 10, y: 710,
    text: "Idols: #{player.idols_held}  HP: #{player.hp}  " \
          "Small: #{counts[0]}  Medium: #{counts[1]}  Large: #{counts[2]}  " \
          "FPS: #{args.gtk.current_framerate.to_i}",
    r: 255, g: 255, b: 255, a: 255
  }

  # Ritual stage indicator bottom-right
  stage_text = stage == 0 ? 'Altar: dormant' :
               stage == 1 ? 'Altar: stirring' :
               stage == 2 ? 'Altar: awakening' :
                            'Altar: CONVERGE AND HOLD'
  stage_r = [80 + stage * 50, 255].min
  args.outputs.labels << {
    x: 1270, y: 30,
    text: stage_text,
    alignment_enum: 2, r: stage_r, g: 80, b: 220, a: 255
  }
end
