require 'app/sprite_animator.rb'
require 'app/boid.rb'

CREATURE_COUNT = 50
CREATURE_SCALE = 0.5

def boot(args)
  args.state = {}
end

def tick(args)
  defaults(args)
  calc(args)
  render(args)
end

def defaults(args)
  return unless args.state.boids.nil?

  args.state.boids = Flock.spawn(CREATURE_COUNT, lambda {
    SpriteAnimator.new(
      path: 'sprites/creature.png',
      frames: CreatureFrames::ALL,
      frame_duration: 4 + rand(4),
      start_tick: -rand(60)
    )
  })
end

def calc(args)
  Flock.step(args.state.boids)
end

def render(args)
  args.outputs.background_color = [20, 20, 30]

  args.outputs.sprites << args.state.boids.map { |b|
    b.render(Kernel.tick_count, scale: CREATURE_SCALE)
  }

  args.outputs.labels << {
    x: 20, y: 700,
    text: "boids: #{args.state.boids.length}  fps: #{args.gtk.current_framerate.to_i}",
    r: 255, g: 255, b: 255
  }
end
