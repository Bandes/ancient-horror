module Screens
  ACTION_KEYS = %i[space enter e w a s d up down left right].freeze

  def self.any_action_pressed?(args)
    kd = args.inputs.keyboard.key_down
    ACTION_KEYS.any? { |k| kd.send(k) } || args.inputs.mouse.click
  end

  def self.intro(args)
    return false unless args.state.intro

    args.outputs.background_color = [5, 3, 12]
    args.outputs.labels << { x: 640, y: 520, text: 'Elder Cave',
                             alignment_enum: 1, size_enum: 10, r: 160, g: 80, b: 255, a: 255 }
    args.outputs.labels << { x: 640, y: 458, text: 'You are an acolyte of the Old Ones. Legend has it that one awaits deep beneath the earth.',
                             alignment_enum: 1, size_enum: 2, r: 180, g: 150, b: 220, a: 255 }
    args.outputs.labels << { x: 640, y: 425, text: 'It is your job to awaken it and Unmake the World. The stars align. The altar waits.',
                             alignment_enum: 1, size_enum: 2, r: 180, g: 150, b: 220, a: 255 }
    args.outputs.labels << { x: 640, y: 380, text: 'Place idols [ SPACE ] to lure shoggoths.',
                             alignment_enum: 1, size_enum: 0, r: 200, g: 200, b: 200, a: 255 }
    args.outputs.labels << { x: 640, y: 350, text: '8 small shoggoths merge near an idol. 4 medium ones merge into a large. March them to the altar.',
                             alignment_enum: 1, size_enum: 0, r: 200, g: 200, b: 200, a: 255 }
    args.outputs.labels << { x: 640, y: 320, text: 'Three great ones at the altar will begin the ritual. Stand with them to hasten it.',
                             alignment_enum: 1, size_enum: 0, r: 200, g: 200, b: 200, a: 255 }
    args.outputs.labels << { x: 640, y: 270, text: '[ E ] Repel — blasts shoggoths and hunters back',
                             alignment_enum: 1, size_enum: 0, r: 180, g: 160, b: 200, a: 255 }
    args.outputs.labels << { x: 640, y: 245, text: 'Inquisitors will hunt your idols. Stay calm. Your sanity will not hold forever.',
                             alignment_enum: 1, size_enum: 0, r: 160, g: 100, b: 140, a: 255 }

    args.outputs.labels << { x: 640, y: 215, text: 'OMENS OF THIS NIGHT',
                             alignment_enum: 1, size_enum: 1, r: 220, g: 180, b: 100, a: 255 }
    (args.state.modifiers || []).each_with_index do |m, i|
      args.outputs.labels << { x: 640, y: 195 - i * 18,
                               text: "#{m.label} — #{m.desc}",
                               alignment_enum: 1, size_enum: -1,
                               r: 255, g: 220, b: 140, a: 240 }
    end

    args.outputs.labels << { x: 640, y: 130, text: 'press any key to begin',
                             alignment_enum: 1, size_enum: 0, r: 120, g: 120, b: 140,
                             a: (Math.sin(Kernel.tick_count * 0.06) * 80 + 170).to_i }
    if any_action_pressed?(args)
      args.state.intro = false
      args.state.start_tick = Kernel.tick_count
      args.state.sound.sfx_enabled = true
      args.state.sound.start_music(args, :ambient)
    end
    true
  end

  def self.game_over(args)
    return false unless args.state.game_over

    render_base(args)
    death_text = args.state.death_cause == :insanity ? 'YOU HAVE GONE INSANE' : 'YOU HAVE BEEN CONSUMED'
    args.outputs.labels << { x: 640, y: 400, text: death_text,
                             alignment_enum: 1, size_enum: 8, r: 255, g: 50, b: 50, a: 255 }
    args.outputs.labels << { x: 640, y: 355, text: 'press any key or click to restart',
                             alignment_enum: 1, r: 200, g: 200, b: 200, a: 255 }
    if any_action_pressed?(args)
      args.state.sound.stop_all_music(args)
      args.state = {}
    end
    true
  end

  def self.win(args)
    return false unless args.state.won

    args.outputs.sprites << args.state.bg_sprites

    age = args.state.end_tick ? Kernel.tick_count - args.state.end_tick : 0

    fade_a = [age * 3, 180].min
    args.outputs.sprites << { x: 0, y: 0, w: 1280, h: 720, path: :solid, r: 5, g: 0, b: 15, a: fade_a }

    if age > 30 && age % 3 == 0
      Particles.burst(args.state.particles, 640, 360, 3,
                      r: Numeric.rand(120..199), g: 20, b: Numeric.rand(220..254), speed: 2.5, size: 5)
    end
    Particles.tick(args.state.particles, fade: Particles::WIN_FADE_PER_TICK)
    args.outputs.sprites << args.state.particles

    anim = args.state.cthulhu_attack
    if anim
      sprite = anim.sprite(Kernel.tick_count, anchor_x: 420, anchor_y: 360, scale: 2.5)
      sprite[:a] = [age * 4, 255].min
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
    args.outputs.labels << { x: 640, y: 148, text: "Ritual completed in #{time_str}   Merges: #{args.state.total_merges || 0}",
                             alignment_enum: 1, size_enum: 1, r: 180, g: 140, b: 255, a: text_a }
    mods = args.state.modifiers || []
    unless mods.empty?
      args.outputs.labels << { x: 640, y: 122, text: 'Omens: ' + mods.map(&:label).join('  ·  '),
                               alignment_enum: 1, size_enum: -2, r: 200, g: 180, b: 120, a: text_a }
    end
    args.outputs.labels << { x: 640, y: 80, text: 'press any key or click to play again',
                             alignment_enum: 1, r: 140, g: 140, b: 160, a: text_a }
    if any_action_pressed?(args)
      args.state.sound.stop_all_music(args)
      args.state = {}
    end
    true
  end

  def self.pause(args)
    sound = args.state.sound
    sel   = args.state.pause_sel ||= 0
    kd    = args.inputs.keyboard.key_down

    sel = (sel - 1) % 2 if kd.up   || kd.w
    sel = (sel + 1) % 2 if kd.down || kd.s
    args.state.pause_sel = sel

    step = 0.05
    delta = 0
    delta = -step if kd.left  || kd.a
    delta =  step if kd.right || kd.d
    if delta != 0
      if sel == 0
        sound.music_vol = (sound.music_vol + delta).clamp(0.0, 1.0).round(2)
        sound.apply_music_vol(args)
      else
        sound.sfx_vol = (sound.sfx_vol + delta).clamp(0.0, 1.0).round(2)
      end
    end

    mods = args.state.modifiers || []

    args.outputs.sprites << { x: 0, y: 0, w: 1280, h: 720, path: :solid, r: 0, g: 0, b: 0, a: 160 }

    panel_x = 440; panel_w = 400
    panel_h = 210 + (mods.empty? ? 0 : 28 + mods.length * 18)
    panel_y = 255 - (mods.empty? ? 0 : 28 + mods.length * 18)
    args.outputs.sprites << { x: panel_x, y: panel_y, w: panel_w, h: panel_h, path: :solid,
                              r: 12, g: 8, b: 28, a: 235 }
    args.outputs.borders << { x: panel_x, y: panel_y, w: panel_w, h: panel_h,
                              r: 100, g: 60, b: 180, a: 200 }

    args.outputs.labels << { x: 640, y: 445, text: 'PAUSED',
                             alignment_enum: 1, size_enum: 6, r: 200, g: 160, b: 255, a: 255 }

    labels = %w[MUSIC EFFECTS]
    vols   = [sound.music_vol, sound.sfx_vol]
    2.times do |i|
      row_y  = 385 - i * 65
      active = sel == i
      lr = active ? 255 : 150
      lg = active ? 220 : 140
      lb = active ? 255 : 170
      args.outputs.labels << { x: 490, y: row_y + 12, text: labels[i],
                               size_enum: 1, r: lr, g: lg, b: lb, a: 255 }
      bar_x = 590; bar_w = 190; bar_h = 16
      fill_w = (bar_w * vols[i]).to_i
      args.outputs.sprites << { x: bar_x, y: row_y, w: bar_w, h: bar_h,
                                path: :solid, r: 35, g: 25, b: 55, a: 220 }
      args.outputs.sprites << { x: bar_x, y: row_y, w: fill_w, h: bar_h,
                                path: :solid, r: lr, g: (lg * 0.55).to_i, b: lb, a: 220 }
      args.outputs.labels  << { x: bar_x + bar_w + 10, y: row_y + 12,
                                text: "#{(vols[i] * 100).round}%",
                                size_enum: -1, r: lr, g: lg, b: lb, a: 220 }
    end

    args.outputs.labels << { x: 640, y: 272, text: '← → adjust   ↑ ↓ select   ESC resume',
                             alignment_enum: 1, size_enum: -2, r: 120, g: 100, b: 155, a: 200 }

    return if mods.empty?

    args.outputs.labels << { x: 640, y: 258, text: 'OMENS',
                             alignment_enum: 1, size_enum: -2, r: 200, g: 180, b: 100, a: 200 }
    mods.each_with_index do |m, i|
      args.outputs.labels << { x: 640, y: 242 - i * 18,
                               text: "#{m.label} — #{m.desc}",
                               alignment_enum: 1, size_enum: -3,
                               r: 220, g: 200, b: 130, a: 220 }
    end
  end

  def self.render_base(args)
    args.outputs.sprites << args.state.bg_sprites
    args.outputs.sprites << (args.state.particles || [])
    args.outputs.sprites << (args.state.boids || []).map { |b| b.render(Kernel.tick_count) }
    args.outputs.sprites << (args.state.hunters || []).map { |h| h.render(Kernel.tick_count) }
  end
end
