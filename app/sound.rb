class Sound
  MUSIC = {
    ambient: 'sounds/music/swamp_of_sorrow_loop.ogg',
    win:     'sounds/music/decaying_cathedral_loop.ogg',
  }.freeze

  SFX = {
    merge_small:  'sounds/effects/creature_merge.ogg',
    merge_large:  'sounds/effects/creature_merge.ogg',
    player_hit:   'sounds/effects/take_hit.wav',
    repel:        'sounds/effects/eldritch_abomination_roar.ogg',
    idol_place:   'sounds/effects/eldritch_abomination_single_breath.ogg',
    idol_pickup:  'sounds/effects/eldritch_abomination_single_breath.ogg',
    hunter_die:   'sounds/effects/monster_frothy_growl.ogg',
    ritual_tick:  'sounds/effects/eldritch_abomination_heart_beat.ogg',
  }.freeze

  AMBIENT_GROUPS = {
    breathing: {
      paths:        ['sounds/effects/eldritch_abomination_breathing.ogg',
                     'sounds/effects/eldritch_abomination_breathing_2.ogg'],
      min_interval: 240,
      max_interval: 480,
    },
    hiss: {
      paths:        ['sounds/effects/monster_hiss_1.ogg',
                     'sounds/effects/monster_hiss_2.ogg'],
      min_interval: 1200,
      max_interval: 2400,
    },
    roar: {
      paths:        ['sounds/effects/monster_roar_22.ogg',
                     'sounds/effects/monster_frothy_growl.ogg'],
      min_interval: 1800,
      max_interval: 3600,
    },
  }.freeze

  def initialize(gtk)
    @available = {}
    ['sounds', 'sounds/effects', 'sounds/music'].each do |dir|
      (gtk.list_files(dir) || []).each { |f| @available["#{dir}/#{f}"] = true }
    end
    @ambient_timers = {
      breathing: 120 + rand(120),
      hiss:      300 + rand(300),
      roar:      480 + rand(480),
    }
  end

  def play(args, key)
    path = SFX[key]
    return unless path && available?(path)
    args.outputs.sounds << path
  end

  def play_gain(args, key, gain: 1.0)
    path = SFX[key]
    return unless path && available?(path)
    args.outputs.sounds << { path: path, gain: gain }
  end

  def start_music(args, key, gain: 0.7)
    path = MUSIC[key]
    return unless path && available?(path)
    return if args.audio[key]
    args.audio[key] = { input: path, looping: true, gain: gain, pitch: 1.0, paused: false }
  end

  def stop_music(args, key)
    args.audio.delete(key)
  end

  def fade_out(args, key, ticks: 60)
    track = args.audio[key]
    return unless track.is_a?(Hash)
    track[:decay_rate] = track[:gain].to_f / ticks
  end

  def stop_all_music(args)
    MUSIC.each_key { |k| args.audio.delete(k) }
  end

  def available?(path)
    @available.key?(path)
  end

  def tick(args)
    to_delete = []
    args.audio.each do |id, track|
      next unless track.is_a?(Hash) && track[:decay_rate]
      track[:gain] -= track[:decay_rate]
      to_delete << id if track[:gain] <= 0
    end
    to_delete.each { |id| args.audio.delete(id) }
    tick_ambient(args)
  end

  def tick_ambient(args)
    AMBIENT_GROUPS.each do |key, group|
      @ambient_timers[key] -= 1
      next if @ambient_timers[key] > 0
      avail = group[:paths].select { |p| available?(p) }
      args.outputs.sounds << avail.sample unless avail.empty?
      @ambient_timers[key] = group[:min_interval] + rand(group[:max_interval] - group[:min_interval])
    end
  end
end
