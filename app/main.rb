require 'app/sprite_animator'
require 'app/cave'
require 'app/boid'
require 'app/player'
require 'app/hunter'
require 'app/sound'
require 'app/touch_controls'
require 'app/flow_field'
require 'app/particles'
require 'app/spawner'
require 'app/screens'
require 'app/idol'
require 'app/modifiers'

CREATURE_COUNT        = 50
LARGE_FOR_WIN         = 3
MAX_SHOGGOTHS         = 120
SPAWN_INTERVAL        = 360   # new shoggoth every 6 seconds
SUMMON_TICKS_NEEDED   = 300   # hold altar 5 seconds to win
HUNTER_SPAWN_INTERVAL = 1800  # new hunter every 30 seconds
MAX_HUNTERS           = 3
IDOL_SLOTS            = 6     # total idols in play (held + placed + scattered)
STARTING_IDOLS        = 2     # idols on hand at run start

# Escalation: every ESCALATE_INTERVAL ticks the spawn interval shrinks by
# ESCALATE_STEP (clamped to SPAWN_INTERVAL_MIN) and one extra hunter slot opens.
ESCALATE_INTERVAL    = 3600 # 60s
ESCALATE_STEP        = 40
SPAWN_INTERVAL_MIN   = 120
MAX_HUNTERS_CAP      = 6

MODIFIER_PICK = 3

def boot(args)
  args.state = {}
end

def tick(args)
  defaults(args)
  args.state.sound.tick(args)
  args.state.touch.tick(args)
  return if Screens.intro(args)
  return if Screens.game_over(args) || Screens.win(args)

  tc = args.state.touch
  if args.inputs.keyboard.key_down.escape || tc.pause_tap
    args.state.paused = !args.state.paused
    args.state.pause_sel ||= 0
  end

  if args.state.paused
    render(args)
    Screens.pause(args)
    args.state.touch.render(args)
    return
  end

  # Debug: Ctrl+W forces win screen
  if args.inputs.keyboard.key_down.w && args.inputs.keyboard.key_held.control
    args.state.won      = true
    args.state.end_tick = Kernel.tick_count
    args.state.sound.sfx_enabled = false
    args.state.sound.fade_out(args, :ambient, ticks: 30)
    args.state.sound.start_music(args, :win, base_gain: 0.9)
    args.state.cthulhu_attack.reset(Kernel.tick_count)
    args.state.particles.clear
  end

  handle_input(args)
  calc(args)
  check_merge(args)
  check_infighting(args)
  check_win(args)
  tick_hunters(args)
  emit_flow_particles(args)
  tick_particles(args)
  render(args)
  args.state.touch.render(args)
end

def defaults(args)
  return if args.state.initialized

  Modifiers.apply_baselines(args.state)
  args.state.modifiers = Modifiers.sample(MODIFIER_PICK)

  cave_data = Cave.generate
  args.state.cave_grid = cave_data[:grid]
  args.state.altar_x   = Cave.tile_center(cave_data[:altar_col], cave_data[:altar_row])[:x]
  args.state.altar_y   = Cave.tile_center(cave_data[:altar_col], cave_data[:altar_row])[:y]
  args.state.flow_altar      = FlowField.build(cave_data[:grid], cave_data[:altar_col], cave_data[:altar_row])
  args.state.flow_altar_fat  = FlowField.build(cave_data[:grid], cave_data[:altar_col], cave_data[:altar_row], clearance: 1)
  args.state.wall_colliders = Cave.generate_wall_colliders(cave_data[:grid])

  spawn = Cave.tile_center(cave_data[:spawn_col], cave_data[:spawn_row])

  args.state.player = Player.new(
    x: spawn[:x], y: spawn[:y],
    starting_idols: STARTING_IDOLS
  )

  args.state.modifiers.each { |m| m.apply(args.state, args.state.player) }

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

  args.state.cthulhu_idle   = SpriteAnimator.new(path: 'sprites/chthulu.png', frames: CthulhuFrames::IDLE,
                                                 frame_duration: 8)
  args.state.cthulhu_attack = SpriteAnimator.new(path: 'sprites/chthulu.png', frames: CthulhuFrames::ATTACK,
                                                 frame_duration: 7)

  args.state.boids = Flock.spawn(
    CREATURE_COUNT,
    args.state.animator_factory,
    cave_grid: args.state.cave_grid
  )

  args.state.idols         = Array.new(IDOL_SLOTS) { Idol.new }
  args.state.won           = false
  args.state.elapsed_ticks = 0
  args.state.game_over     = false
  args.state.summon_ticks         = 0
  args.state.ritual_stage         = 0 # 0-3: how many large shoggoths have reached altar
  args.state.ritual_music_started = false
  args.state.particles     = []
  args.state.hunters       = []
  args.state.hunter_timer  = 0
  args.state.shake_timer        = 0
  args.state.total_merges       = 0
  args.state.last_escalate_step = 0
  args.state.escalate_flash     = 0
  args.state.merge_flash        = 0
  args.state.repel_flash        = 0
  args.state.floor_cells   = Cave.floor_cells(args.state.cave_grid)
  exclude = [[cave_data[:spawn_col], cave_data[:spawn_row]],
             [cave_data[:altar_col], cave_data[:altar_row]]]
  props = Cave.generate_props(args.state.cave_grid, exclude)
  args.state.prop_colliders = props.map { |p| { cx: p[:cx], cy: p[:cy], cr: p[:cr] } }
  args.state.bg_sprites = Cave.render(args.state.cave_grid) + props.map { |p| p[:sprite] }

  # Scatter the remaining idols across the cave so the player must explore.
  scatter_count = IDOL_SLOTS - args.state.player.idols_held
  scatter_cells = args.state.floor_cells.reject do |c, r|
    (c == cave_data[:spawn_col] && r == cave_data[:spawn_row]) ||
      (c == cave_data[:altar_col] && r == cave_data[:altar_row])
  end
  far = scatter_cells.select do |c, r|
    px = c * Cave::TILE_SIZE + Cave::TILE_SIZE / 2
    py = r * Cave::TILE_SIZE + Cave::TILE_SIZE / 2
    (px - spawn[:x])**2 + (py - spawn[:y])**2 > Spawner::IDOL_SCATTER_DIST**2
  end
  pool = far.empty? ? scatter_cells : far
  placed_idol_cells = []
  scatter_count.times do |i|
    next if pool.empty?

    candidates = pool.reject do |c, r|
      placed_idol_cells.any? { |pc, pr| (pc - c).abs + (pr - r).abs < 4 }
    end
    cell = (candidates.empty? ? pool : candidates).sample
    placed_idol_cells << cell
    col, row = cell
    args.state.idols[args.state.player.idols_held + i] = Idol.new(
      x: col * Cave::TILE_SIZE + Cave::TILE_SIZE / 2.0,
      y: row * Cave::TILE_SIZE + Cave::TILE_SIZE / 2.0,
      placed: true
    )
  end
  args.state.sound         = Sound.new(args.gtk)
  if (prefs = args.state.sound_prefs)
    args.state.sound.music_vol = prefs[:music_vol]
    args.state.sound.sfx_vol   = prefs[:sfx_vol]
    args.state.sound.muted     = prefs[:muted]
  end
  args.state.touch         = TouchControls.new
  args.state.intro         = true
  args.state.start_tick    = nil
  args.state.paused        = false
  args.state.pause_sel     = 0
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
  tc = args.state.touch
  player.update(args.inputs, args.state.wall_colliders, touch_dx: tc.dx, touch_dy: tc.dy)
  player.x, player.y = resolve_prop_collisions(player.x, player.y, Player::RADIUS, args.state.prop_colliders)

  return unless args.inputs.keyboard.key_down.space || tc.interact_tap

  picked = args.state.idols.find { |idol| idol.placed? && idol.near?(player.x, player.y, IDOL_INTERACT_RADIUS) }
  if picked
    picked.pickup!
    player.idols_held += 1
    args.state.sound.play(args, :idol_pickup)
    return
  end

  return unless player.idols_held > 0

  idol = args.state.idols.find { |id| !id.placed? }
  return unless idol

  idol.place_at(player.x, player.y)
  player.idols_held -= 1
  args.state.sound.play(args, :idol_place)
end

def tick_flow_fields(args)
  cave   = args.state.cave_grid
  player = args.state.player

  pcell = [player.x.idiv(Cave::TILE_SIZE), player.y.idiv(Cave::TILE_SIZE)]
  if args.state.flow_player_cell != pcell
    args.state.flow_player_cell = pcell
    args.state.flow_player     = FlowField.build(cave, pcell[0], pcell[1])
    args.state.flow_player_fat = FlowField.build(cave, pcell[0], pcell[1], clearance: 1)
  end

  idol_sig = args.state.idols.map(&:signature)
  return unless args.state.flow_idol_sig != idol_sig

  args.state.flow_idol_sig = idol_sig
  args.state.flow_idols = args.state.idols.map do |id|
    next nil unless id.placed?

    FlowField.build(cave, id.x.idiv(Cave::TILE_SIZE), id.y.idiv(Cave::TILE_SIZE))
  end
end

def calc(args)
  player = args.state.player
  player.tick_repel

  # Repel: E key blasts nearby shoggoths away; inner kill zone destroys/splits them
  tc = args.state.touch
  if (args.inputs.keyboard.key_down.e || tc.repel_held) && player.repel_ready?
    player.repel!(Kernel.tick_count)
    args.state.sound.play(args, :repel)
    repel_r_sq      = Player::REPEL_RADIUS**2
    kill_r_sq       = Player::REPEL_KILL_RADIUS**2
    destroyed_boids = []
    spawned_boids   = []

    args.state.boids.each do |b|
      dx = b.x - player.x
      dy = b.y - player.y
      d2 = dx * dx + dy * dy
      next if d2 > repel_r_sq || d2 < 0.0001

      d = Math.sqrt(d2)

      if d2 < kill_r_sq
        if b.tier == 1
          destroyed_boids << b
          emit_particles(args, b.x, b.y, 14, r: 40, g: 220, b: 80, speed: 3.0, size: 5)
        elsif b.tier == 2
          # Split medium back into two smalls
          destroyed_boids << b
          2.times do |_i|
            angle = rand * Math::PI * 2
            spawned_boids << Boid.new(
              x: b.x + Math.cos(angle) * 18, y: b.y + Math.sin(angle) * 18,
              vx: (dx / d * Player::REPEL_FORCE * 2.0) + Math.cos(angle) * 0.5,
              vy: (dy / d * Player::REPEL_FORCE * 2.0) + Math.sin(angle) * 0.5,
              bias_x: dx / d, bias_y: dy / d,
              animator: args.state.animator_factory.call,
              personality: { speed_scale: 0.8 + rand * 0.4, wander_scale: 0.8, bias_scale: 0.6 },
              tier: 1
            )
          end
          emit_particles(args, b.x, b.y, 20, r: 80, g: 255, b: 120, speed: 3.5, size: 6)
        else
          # Tier 3 just takes a massive shove
          force = Player::REPEL_FORCE * 3.5 * (1.0 - d / Player::REPEL_RADIUS)
          b.vx += dx / d * force
          b.vy += dy / d * force
        end
      else
        force = Player::REPEL_FORCE * 2.0 * (1.0 - d / Player::REPEL_RADIUS)
        b.vx += dx / d * force
        b.vy += dy / d * force
      end
    end

    args.state.boids -= destroyed_boids unless destroyed_boids.empty?
    args.state.boids.concat(spawned_boids) unless spawned_boids.empty?

    args.state.hunters.each do |h|
      dx = h.x - player.x
      dy = h.y - player.y
      d2 = dx * dx + dy * dy
      next if d2 > repel_r_sq || d2 < 0.0001

      d = Math.sqrt(d2)
      force = Player::REPEL_FORCE * 2.5 * (1.0 - d / Player::REPEL_RADIUS)
      h.vx += dx / d * force
      h.vy += dy / d * force
      h.take_hit
    end
    args.state.repel_flash = 14
    args.state.shake_timer = 10
  end
  args.state.repel_flash = [(args.state.repel_flash || 0) - 1, 0].max

  tick_flow_fields(args)

  Flock.step(
    args.state.boids,
    cave_grid: args.state.cave_grid,
    idols: args.state.idols,
    altar_x: args.state.altar_x,
    altar_y: args.state.altar_y,
    player_x: player.x,
    player_y: player.y,
    ritual_stage: args.state.ritual_stage,
    hunters: args.state.hunters,
    speed_mult: args.state.boid_speed_mult,
    flow_altar: args.state.flow_altar,
    flow_altar_fat: args.state.flow_altar_fat,
    flow_player: args.state.flow_player,
    flow_player_fat: args.state.flow_player_fat,
    flow_idols: args.state.flow_idols,
    wall_rects: args.state.wall_colliders
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
    next unless d2 < min_d * min_d

    altar_dx = player.x - args.state.altar_x
    altar_dy = player.y - args.state.altar_y
    next if altar_dx * altar_dx + altar_dy * altar_dy < Cave::ALTAR_RADIUS * Cave::ALTAR_RADIUS

    dmg = b.tier == 3 ? 2 : 1
    was_inv = player.invincible?
    player.take_hit(damage: dmg)
    args.state.sound.play(args, :player_hit) if !was_inv && player.invincible?
  end

  altar_dx = player.x - args.state.altar_x
  altar_dy = player.y - args.state.altar_y
  at_altar = altar_dx * altar_dx + altar_dy * altar_dy < Cave::ALTAR_RADIUS * Cave::ALTAR_RADIUS

  if nearby_count > 0 && !at_altar
    player.drain_sanity(0.008 + nearby_count * 0.001)
  elsif at_altar || nearby_count == 0
    player.recover_sanity(0.03)
  end
  player.drain_sanity(0.005) if args.state.miasma
  player.drain_sanity(player.idols_held * 0.03) if args.state.idol_curse && player.idols_held > 0

  if player.dead? && !args.state.game_over
    args.state.game_over = true
    args.state.death_cause = player.sanity <= 0 ? :insanity : :consumed
  end

  args.state.elapsed_ticks += 1

  cur_step = args.state.elapsed_ticks.idiv(ESCALATE_INTERVAL)
  if cur_step > args.state.last_escalate_step
    args.state.last_escalate_step = cur_step
    args.state.escalate_flash = 240
  end

  interval = effective_spawn_interval(args)
  return unless args.state.boids.length < MAX_SHOGGOTHS && Kernel.tick_count % interval == 0

  Spawner.spawn_shoggoth(args)
end

def effective_spawn_interval(args)
  base = (SPAWN_INTERVAL * args.state.spawn_scale).to_i
  steps = args.state.elapsed_ticks.idiv(ESCALATE_INTERVAL)
  [base - steps * ESCALATE_STEP, SPAWN_INTERVAL_MIN].max
end

def effective_hunter_cap(args)
  base = MAX_HUNTERS + args.state.hunter_cap_bonus
  steps = args.state.elapsed_ticks.idiv(ESCALATE_INTERVAL)
  [base + steps, MAX_HUNTERS_CAP + args.state.hunter_cap_bonus].min
end

def check_merge(args)
  merge_r_sq = Cave::MERGE_RADIUS * Cave::MERGE_RADIUS
  boids      = args.state.boids
  factory    = args.state.animator_factory

  args.state.idols.each do |idol|
    next unless idol.placed?

    (args.state.merge_thresholds || { 1 => 8, 2 => 4 }).each do |tier, threshold|
      nearby = boids.select do |b|
        b.tier == tier && idol.near?(b.x, b.y, Cave::MERGE_RADIUS)
      end
      next if nearby.length < threshold

      nearby.first(threshold).each { |b| boids.delete(b) }

      angle = rand * Math::PI * 2
      boids << Boid.new(
        x: idol.x, y: idol.y,
        vx: Math.cos(angle) * Flock::MIN_SPEED,
        vy: Math.sin(angle) * Flock::MIN_SPEED,
        bias_x: Math.cos(angle), bias_y: Math.sin(angle),
        animator: factory.call,
        personality: { speed_scale: 0.9, wander_scale: 0.7, bias_scale: 0.6 },
        tier: tier + 1
      )

      pr, pg, pb = tier == 1 ? [80, 255, 120] : [200, 80, 255]
      emit_particles(args, idol.x, idol.y, 20, r: pr, g: pg, b: pb, speed: 3.5, size: 6)
      args.state.merge_flash = 6
      args.state.sound.play(args, tier == 1 ? :merge_small : :merge_large)

      idol.pickup!
      args.state.player.idols_held += 1
      args.state.total_merges += 1
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

  if large_at_altar >= args.state.large_for_win
    # Transition music the first time the ritual activates
    unless args.state.ritual_music_started
      args.state.ritual_music_started = true
      args.state.sound.fade_out(args, :ambient, ticks: 90)
      args.state.sound.start_music(args, :win, base_gain: 0.9)
    end

    # Large shoggoths charge ritual on their own; player presence doubles rate
    charge = (player_at_altar ? 2 : 1) * args.state.ritual_speed
    args.state.summon_ticks += charge
    args.state.sound.play(args, :ritual_tick) if args.state.summon_ticks % 60 == 0

    # Orbiting ring of particles around the altar
    pct = args.state.summon_ticks.to_f / SUMMON_TICKS_NEEDED
    orbit_r = Cave::ALTAR_RADIUS * 0.9
    num_emitters = 6
    num_emitters.times do |i|
      angle = (Kernel.tick_count * 0.04 + i * Math::PI * 2 / num_emitters) % (Math::PI * 2)
      ex = ax + Math.cos(angle) * orbit_r
      ey = ay + Math.sin(angle) * orbit_r
      pr = Numeric.rand(140..219).clamp(0, 255)
      pb = Numeric.rand(220..254).clamp(0, 255)
      emit_particles(args, ex, ey, 2, r: pr, g: 20 + (pct * 60).to_i, b: pb, speed: 0.8 + pct * 1.2,
                                      size: 4 + (pct * 4).to_i)
    end
    # Inward-rushing bursts
    if Kernel.tick_count % 8 == 0
      burst_angle = rand * Math::PI * 2
      bx = ax + Math.cos(burst_angle) * (orbit_r * 1.5)
      by = ay + Math.sin(burst_angle) * (orbit_r * 1.5)
      dx = ax - bx
      dy = ay - by
      mag = Math.sqrt(dx * dx + dy * dy)
      speed = 1.5 + pct * 2.0
      args.state.particles << {
        x: bx, y: by, w: 6, h: 6,
        dx: dx / mag * speed, dy: dy / mag * speed,
        a: 220, path: :solid,
        r: Numeric.rand(180..254).clamp(0, 255), g: 30, b: 255, blendmode_enum: 1
      }
    end
    if args.state.summon_ticks >= SUMMON_TICKS_NEEDED
      args.state.won = true
      if args.state.end_tick.nil?
        args.state.end_tick = Kernel.tick_count
        args.state.sound.sfx_enabled = false
        args.state.cthulhu_attack.reset(Kernel.tick_count)
        args.state.particles.clear
      end
    end
  else
    args.state.summon_ticks = [args.state.summon_ticks - 2, 0].max
  end
end


def emit_particles(args, x, y, count, r:, g:, b:, speed: 2.0, size: 5)
  Particles.burst(args.state.particles, x, y, count, r: r, g: g, b: b, speed: speed, size: size)
end

def tick_particles(args)
  Particles.tick(args.state.particles)
  args.state.merge_flash = [(args.state.merge_flash || 0) - 1, 0].max
end

def check_infighting(args)
  eaten = []
  args.state.boids.each do |predator|
    next if predator.tier < 3

    eat_r = predator.collision_r - 4
    args.state.boids.each do |prey|
      next if prey.tier == 3 || eaten.include?(prey)

      dx = predator.x - prey.x
      dy = predator.y - prey.y
      next unless dx * dx + dy * dy < eat_r * eat_r

      eaten << prey
      emit_particles(args, prey.x, prey.y, 8, r: 80, g: 210, b: 80, speed: 1.5, size: 4)
    end
  end
  unless eaten.empty?
    args.state.boids -= eaten
    args.state.sound.play(args, :great_one_eat)
  end

  args.state.hunters.reject! do |h|
    args.state.boids.any? do |b|
      dx = b.x - h.x
      dy = b.y - h.y
      eat_r = b.collision_r + Hunter::RADIUS - 6
      next unless dx * dx + dy * dy < eat_r * eat_r

      emit_particles(args, h.x, h.y, 10, r: 200, g: 20, b: 20, speed: 2.0, size: 5)
      args.state.sound.play(args, :hunter_die)
      true
    end
  end
end

def hunter_waypoint(hx, hy, flow, fallback_x, fallback_y)
  fdx, fdy = FlowField.direction(flow, hx, hy)
  return [fallback_x, fallback_y] if fdx == 0.0 && fdy == 0.0

  reach = Cave::TILE_SIZE * 1.5
  [hx + fdx * reach, hy + fdy * reach]
end

def tick_hunters(args)
  player = args.state.player
  args.state.hunter_timer += 1
  cap = effective_hunter_cap(args)
  if args.state.hunter_timer >= HUNTER_SPAWN_INTERVAL && args.state.hunters.length < cap
    args.state.hunter_timer = 0
    Spawner.spawn_hunter(args)
  end

  placed_idols = args.state.idols.select(&:placed?)

  args.state.hunters.each do |h|
    target = h.target(player, placed_idols)
    flow = if target[:idol] && args.state.flow_idols
             idx = args.state.idols.index(target[:idol])
             idx ? args.state.flow_idols[idx] : args.state.flow_player
           else
             args.state.flow_player
           end
    tx, ty = hunter_waypoint(h.x, h.y, flow, target[:x], target[:y])
    h.update(tx, ty, args.state.wall_colliders)
    h.x, h.y = resolve_prop_collisions(h.x, h.y, Hunter::RADIUS, args.state.prop_colliders)

    h.aura_drain(player)

    if h.steals_idols?
      args.state.idols.each do |idol|
        next unless idol.placed?
        next unless idol.near?(h.x, h.y, Hunter::RADIUS + 14)

        emit_particles(args, idol.x, idol.y, 14, r: 255, g: 100, b: 20, speed: 2.5, size: 5)
        idol.pickup!
        player.idols_held += 1
        args.state.sound.play(args, :idol_stolen)
      end
    end

    dx = h.x - player.x
    dy = h.y - player.y
    next unless dx * dx + dy * dy < (Hunter::RADIUS + player.radius)**2

    was_inv = player.invincible?
    player.take_hit
    args.state.sound.play(args, :player_hit) if !was_inv && player.invincible?
  end

  args.state.hunters.reject!(&:dead?)
end

def render(args)
  # Screen shake
  args.state.shake_timer = [(args.state.shake_timer || 0) - 1, 0].max
  sx = 0; sy = 0
  if args.state.shake_timer > 0
    mag = args.state.shake_timer * 1.5
    sx = Numeric.rand(-mag.to_i..mag.to_i)
    sy = Numeric.rand(-mag.to_i..mag.to_i)
  end

  # World render target
  wo = args.outputs[:world]
  wo.w = 1280; wo.h = 720
  wo.background_color = [0, 0, 0]
  wo.sprites << args.state.bg_sprites
  render_corruption(wo, args)
  render_altar(wo, args)
  render_idols(wo, args)
  wo.sprites << (args.state.particles || [])
  wo.sprites << (args.state.boids || []).map { |b| b.render(Kernel.tick_count) }
  wo.sprites << (args.state.hunters || []).map { |h| h.render(Kernel.tick_count) }
  wo.sprites << args.state.player.render(Kernel.tick_count, sanity_pct: args.state.player.sanity_pct)

  if (args.state.repel_flash || 0) > 0
    a = (args.state.repel_flash * 12).clamp(0, 140)
    wo.sprites << { x: 0, y: 0, w: 1280, h: 720, path: :solid, r: 200, g: 255, b: 220, a: a, blendmode_enum: 1 }
  end
  if (args.state.merge_flash || 0) > 0
    a = (args.state.merge_flash * 25).clamp(0, 120)
    wo.sprites << { x: 0, y: 0, w: 1280, h: 720, path: :solid, r: 160, g: 255, b: 180, a: a }
  end

  args.outputs.sprites << { x: sx, y: sy, w: 1280, h: 720, path: :world }
  render_hud(args)
end

def render_corruption(out, args)
  stage = args.state.ritual_stage

  if stage > 0
    pulse = Math.sin(Kernel.tick_count * 0.03) * 0.5 + 0.5
    a = (stage * 22 + pulse * 14).to_i
    out.sprites << { x: 0, y: 0, w: 1280, h: 720, path: :solid, r: 80, g: 10, b: 110, a: a, blendmode_enum: 1 }
  end

  sp = args.state.player.sanity_pct
  return unless sp < 0.5

  # Below 50%: red vignette deepens
  sv = ((0.5 - sp) * 2).clamp(0, 1)
  out.sprites << { x: 0, y: 0, w: 1280, h: 720, path: :solid, r: 30, g: 0, b: 0, a: (sv * 100).to_i, blendmode_enum: 1 }

  return unless sp < 0.25

  # Below 25%: violent pulsing crimson wash + desaturation effect
  crisis = ((0.25 - sp) * 4).clamp(0, 1)
  pulse2 = (Math.sin(Kernel.tick_count * 0.12) * 0.5 + 0.5) ** 2
  flash_a = (crisis * 80 + pulse2 * crisis * 60).to_i
  out.sprites << { x: 0, y: 0, w: 1280, h: 720, path: :solid, r: 180, g: 0, b: 20, a: flash_a, blendmode_enum: 1 }
  # Darkening corners — 4 gradient-ish corner rects
  edge_a = (crisis * 120).to_i
  corner = (crisis * 320).to_i
  out.sprites << { x: 0,          y: 0,          w: corner, h: corner, path: :solid, r: 0, g: 0, b: 0, a: edge_a }
  out.sprites << { x: 1280-corner, y: 0,          w: corner, h: corner, path: :solid, r: 0, g: 0, b: 0, a: edge_a }
  out.sprites << { x: 0,          y: 720-corner, w: corner, h: corner, path: :solid, r: 0, g: 0, b: 0, a: edge_a }
  out.sprites << { x: 1280-corner, y: 720-corner, w: corner, h: corner, path: :solid, r: 0, g: 0, b: 0, a: edge_a }
end

ALTAR_SPRITE_W = 80
ALTAR_SPRITE_H = 80

def render_altar(out, args)
  ax = args.state.altar_x
  ay = args.state.altar_y
  stage = args.state.ritual_stage
  pulse = (Math.sin(Kernel.tick_count * 0.08) * 0.5 + 0.5)

  base_r = 60 + stage * 40
  base_g = 20 + stage * 10
  base_b = 160 + stage * 25
  glow_a = (80 + stage * 35 + pulse * 40).to_i.clamp(0, 255)
  glow_size = (ALTAR_SPRITE_W * 1.6 + stage * 8 + pulse * 6).to_i
  out.sprites << { x: ax - glow_size / 2, y: ay - glow_size / 2, w: glow_size, h: glow_size,
                   path: :solid, r: base_r, g: base_g, b: base_b, a: glow_a }

  tint_g = (180 + stage * 25).clamp(0, 255)
  out.sprites << { x: ax - ALTAR_SPRITE_W / 2, y: ay - ALTAR_SPRITE_H / 2,
                   w: ALTAR_SPRITE_W, h: ALTAR_SPRITE_H,
                   path: 'sprites/altar.png', r: 255, g: tint_g, b: 255, a: 255, blendmode_enum: 1 }

  return unless args.state.summon_ticks > 0

  pct   = args.state.summon_ticks.to_f / SUMMON_TICKS_NEEDED
  bar_w = 80
  bar_y = ay + ALTAR_SPRITE_H / 2 + 6
  out.sprites << { x: ax - bar_w / 2, y: bar_y, w: bar_w, h: 6, path: :solid, r: 40, g: 40, b: 40, a: 200 }
  out.sprites << { x: ax - bar_w / 2, y: bar_y, w: (bar_w * pct).to_i, h: 6,
                   path: :solid, r: 180, g: 80, b: 255, a: 255 }
  out.labels  << { x: ax, y: bar_y + 16, text: 'HOLD!', alignment_enum: 1, size_enum: -2, r: 220, g: 150, b: 255, a: 255 }
end

IDOL_W = 41
IDOL_H = 64

def render_idols(out, args)
  merge_r = Cave::MERGE_RADIUS
  args.state.idols.each do |idol|
    next unless idol.placed?

    near_small = 0
    near_medium = 0
    args.state.boids.each do |b|
      next unless idol.near?(b.x, b.y, merge_r)

      near_small  += 1 if b.tier == 1
      near_medium += 1 if b.tier == 2
    end

    small_pct  = near_small.to_f  / Cave::MERGE_THRESHOLD_SMALL
    medium_pct = near_medium.to_f / Cave::MERGE_THRESHOLD_MEDIUM
    best_pct   = [small_pct, medium_pct, 0.0].max.clamp(0.0, 1.0)
    ring_r = (60  + best_pct * 195).to_i.clamp(0, 255)
    ring_g = (180 + best_pct * 75).to_i.clamp(0, 255)
    ring_b = 60
    ring_a = (55 + best_pct * 160).to_i.clamp(0, 255)

    32.times do |i|
      next if i.odd? && best_pct < 0.25

      angle = i * Math::PI * 2 / 32
      rx = idol.x + Math.cos(angle) * merge_r
      ry = idol.y + Math.sin(angle) * merge_r
      out.sprites << { x: rx - 2, y: ry - 2, w: 4, h: 4, path: :solid,
                       r: ring_r, g: ring_g, b: ring_b, a: ring_a, blendmode_enum: 1 }
    end

    parts = []
    parts << "#{near_small}/#{Cave::MERGE_THRESHOLD_SMALL}s" if near_small > 0
    parts << "#{near_medium}/#{Cave::MERGE_THRESHOLD_MEDIUM}m" if near_medium > 0
    unless parts.empty?
      out.labels << { x: idol.x, y: idol.y - IDOL_H / 2 - 4,
                      text: parts.join('  '), alignment_enum: 1, size_enum: -3,
                      r: ring_r, g: ring_g, b: 100, a: 230 }
    end

    pulse = (Math.sin(Kernel.tick_count * 0.12) * 30 + 220).to_i
    out.sprites << { x: idol.x - IDOL_W / 2, y: idol.y - IDOL_H / 2,
                     w: IDOL_W, h: IDOL_H, path: 'sprites/idol.png',
                     r: pulse, g: pulse, b: 80, a: 255, blendmode_enum: 1 }
  end
end

def emit_flow_particles(args)
  placed = args.state.idols.select(&:placed?)
  return if placed.empty?

  attract_r_sq = Flock::IDOL_ATTRACT_RADIUS_SQ
  args.state.boids.each do |b|
    next if Kernel.tick_count % 6 != b.object_id % 6

    nearest = placed.min_by { |idol| idol.distance_sq_to(b.x, b.y) }
    dx = nearest.x - b.x
    dy = nearest.y - b.y
    d2 = dx * dx + dy * dy
    next if d2 > attract_r_sq || d2 < 28 * 28

    d = Math.sqrt(d2)
    speed = 1.6 + rand * 1.2
    t = rand * 0.35
    args.state.particles << {
      x: b.x + dx * t, y: b.y + dy * t,
      w: 3, h: 3,
      dx: dx / d * speed * (0.6 + rand * 0.6),
      dy: dy / d * speed * (0.6 + rand * 0.6),
      a: Numeric.rand(160..219), path: :solid,
      r: Numeric.rand(100..179), g: Numeric.rand(200..254), b: 60, blendmode_enum: 1
    }
  end
end


def render_hud(args)
  player = args.state.player
  stage  = args.state.ritual_stage

  # Modifier reminders bottom-center
  (args.state.modifiers || []).each_with_index do |m, i|
    args.outputs.labels << {
      x: 640, y: 18 + i * 14, text: m.label,
      alignment_enum: 1, size_enum: -3,
      r: 200, g: 180, b: 120, a: 200
    }
  end

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

  # Repel cooldown bar (bottom-left)
  bar_w = 80
  ready = player.repel_ready?
  args.outputs.labels << { x: 10, y: 24, text: ready ? '[E] REPEL' : '[E] ...',
                           size_enum: -2, r: ready ? 255 : 140, g: ready ? 200 : 140, b: ready ? 80 : 140, a: 255 }
  args.outputs.sprites << { x: 10, y: 28, w: bar_w, h: 5,
                            path: :solid, r: 40, g: 40, b: 40, a: 180 }
  fill = ready ? bar_w : ((1.0 - player.repel_cooldown_pct) * bar_w).to_i
  args.outputs.sprites << { x: 10, y: 28, w: fill, h: 5,
                            path: :solid, r: 255, g: 180, b: 50, a: 255 }

  # Repel radius indicator — brief expanding ring
  if (args.state.repel_flash || 0) > 0
    t = 1.0 - args.state.repel_flash / 8.0
    r = Player::REPEL_RADIUS * t
    a = (args.state.repel_flash * 20).clamp(0, 120)
    args.outputs.sprites << { x: player.x - r, y: player.y - r, w: r * 2, h: r * 2,
                              path: :solid, r: 160, g: 80, b: 255, a: a }
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
  args.outputs.labels << { x: 1270, y: 30, text: stage_text,
                           alignment_enum: 2, r: stage_r, g: 80, b: 220, a: 255 }

  # Escalation warning flash
  if (args.state.escalate_flash || 0) > 0
    ef = args.state.escalate_flash
    a = [ef * 4, 255].min
    args.outputs.labels << { x: 640, y: 380, text: 'THE DARKNESS STIRS',
                             alignment_enum: 1, size_enum: 4, r: 220, g: 50, b: 50, a: a }
    args.state.escalate_flash = ef - 1
  end

end
