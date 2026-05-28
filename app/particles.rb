module Particles
  FADE_PER_TICK     = 7
  WIN_FADE_PER_TICK = 5
  DAMPING           = 0.93

  def self.burst(list, x, y, count, r:, g:, b:, speed: 2.0, size: 5)
    count.times do
      angle = rand * Math::PI * 2
      spd   = speed * (0.5 + rand * 0.8)
      list << {
        x: x, y: y, w: size, h: size,
        dx: Math.cos(angle) * spd, dy: Math.sin(angle) * spd,
        a: 255, path: :solid, r: r, g: g, b: b, blendmode_enum: 1
      }
    end
  end

  def self.tick(list, fade: FADE_PER_TICK)
    list.each do |p|
      p[:x] += p[:dx]
      p[:y] += p[:dy]
      p[:dx] *= DAMPING
      p[:dy] *= DAMPING
      p[:a]  -= fade
    end
    list.reject! { |p| p[:a] <= 0 }
  end
end
