module Spawner
  SHOGGOTH_MIN_DIST   = 200
  HUNTER_MIN_DIST     = 300
  IDOL_SCATTER_DIST   = 220
  WATCHER_PROBABILITY = 0.4

  def self.pick_far_cell(cells, x, y, min_dist)
    min_sq = min_dist * min_dist
    far = cells.select do |c, r|
      px = c * Cave::TILE_SIZE + Cave::TILE_SIZE / 2
      py = r * Cave::TILE_SIZE + Cave::TILE_SIZE / 2
      (px - x)**2 + (py - y)**2 > min_sq
    end
    (far.empty? ? cells : far).sample
  end

  def self.spawn_shoggoth(args)
    player = args.state.player
    col, row = pick_far_cell(args.state.floor_cells, player.x, player.y, SHOGGOTH_MIN_DIST)
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

  def self.spawn_hunter(args)
    player = args.state.player
    col, row = pick_far_cell(args.state.floor_cells, player.x, player.y, HUNTER_MIN_DIST)
    return unless col

    hx = col * Cave::TILE_SIZE + Cave::TILE_SIZE / 2
    hy = row * Cave::TILE_SIZE + Cave::TILE_SIZE / 2
    kind = args.state.allow_watchers && rand < WATCHER_PROBABILITY ? :watcher : :inquisitor
    args.state.hunters << Hunter.create(
      x: hx, y: hy,
      animator: args.state.hunter_animator_factory.call,
      kind: kind
    )
    cr, cg = kind == :watcher ? [60, 220] : [220, 60]
    Particles.burst(args.state.particles, hx, hy, 16, r: cr, g: cg, b: 40, speed: 2.5, size: 5)
    args.state.sound.play(args, :hunter_spawn)
  end
end
