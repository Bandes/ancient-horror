module Modifiers
  class Base
    LABEL = 'BASE'
    DESC  = ''

    def label; self.class::LABEL; end
    def desc;  self.class::DESC;  end
    def key;   self.class::KEY;   end

    def apply(state, player); end
  end

  class Swift < Base
    KEY = :swift
    LABEL = 'SWIFT ACOLYTE'
    DESC  = '+30% move speed'
    def apply(_state, player); player.speed_scale *= 1.3; end
  end

  class Fervor < Base
    KEY = :fervor
    LABEL = 'FERVOR'
    DESC  = 'Repel cooldown halved'
    def apply(_state, player); player.repel_cd_scale = 0.5; end
  end

  class Fragile < Base
    KEY = :fragile
    LABEL = 'FRAGILE PSYCHE'
    DESC  = '+50 max sanity, drains 2x'
    def apply(_state, player)
      player.max_sanity += 50
      player.sanity = player.max_sanity
      player.sanity_drain_scale = 2.0
    end
  end

  class Ironflesh < Base
    KEY = :ironflesh
    LABEL = 'IRONFLESH'
    DESC  = '+2 max HP, -20% speed'
    def apply(_state, player)
      player.max_hp = [player.max_hp + 2, 1].max
      player.hp = player.max_hp
      player.speed_scale *= 0.8
    end
  end

  class HunterSwarm < Base
    KEY = :hunter_swarm
    LABEL = 'HUNTED'
    DESC  = 'Hunter cap +2'
    def apply(state, _player); state.hunter_cap_bonus = 2; end
  end

  class DimAltar < Base
    KEY = :dim_altar
    LABEL = 'DIM ALTAR'
    DESC  = 'Needs 4 great ones at altar'
    def apply(state, _player); state.large_for_win = 4; end
  end

  class ThinVeil < Base
    KEY = :thin_veil
    LABEL = 'THIN VEIL'
    DESC  = 'Ritual fills 50% faster'
    def apply(state, _player); state.ritual_speed = 1.5; end
  end

  class Eager < Base
    KEY = :eager
    LABEL = 'EAGER SHOGGOTHS'
    DESC  = 'Boids 25% faster'
    def apply(state, _player); state.boid_speed_mult = 1.25; end
  end

  class Keeper < Base
    KEY = :keeper
    LABEL = 'KEEPER OF TORCHES'
    DESC  = 'Sanity recovers 3x, -1 max HP'
    def apply(_state, player)
      player.max_hp = [player.max_hp - 1, 1].max
      player.hp = player.max_hp
      player.sanity_recover_scale = 3.0
    end
  end

  class DreadPace < Base
    KEY = :dread_pace
    LABEL = 'DREAD PACE'
    DESC  = 'Shoggoths spawn twice as fast'
    def apply(state, _player); state.spawn_scale = 0.5; end
  end

  class WatcherKin < Base
    KEY = :watcher_kin
    LABEL = 'WATCHER KIN'
    DESC  = 'Some hunters are Watchers — slow, drain sanity'
    def apply(state, _player); state.allow_watchers = true; end
  end

  class Miasma < Base
    KEY = :miasma
    LABEL = 'MIASMA'
    DESC  = 'Sanity drains constantly — no safe ground'
    def apply(state, _player); state.miasma = true; end
  end

  class Fecund < Base
    KEY = :fecund
    LABEL = 'FECUND DEPTHS'
    DESC  = 'Shoggoths merge at half the threshold'
    def apply(state, _player); state.merge_thresholds = { 1 => 4, 2 => 2 }; end
  end

  class IdolCurse < Base
    KEY = :idol_curse
    LABEL = 'CURSED RELICS'
    DESC  = 'Each held idol slowly drains sanity'
    def apply(state, _player); state.idol_curse = true; end
  end

  class Scattered < Base
    KEY = :scattered
    LABEL = 'SCATTERED MINDS'
    DESC  = 'Start empty-handed — all idols hidden in the cave'
    def apply(_state, player); player.idols_held = 0; end
  end

  REGISTRY = [
    Swift, Fervor, Fragile, Ironflesh, HunterSwarm, DimAltar, ThinVeil,
    Eager, Keeper, DreadPace, WatcherKin, Miasma, Fecund, IdolCurse, Scattered
  ].freeze

  def self.sample(n)
    Array.new(n) { REGISTRY.sample.new }
  end

  def self.apply_baselines(state)
    state.large_for_win    = 3
    state.ritual_speed     = 1.0
    state.boid_speed_mult  = 1.0
    state.spawn_scale      = 1.0
    state.hunter_cap_bonus = 0
    state.allow_watchers   = false
    state.miasma           = false
    state.merge_thresholds = { 1 => 8, 2 => 4 }
    state.idol_curse       = false
  end
end
