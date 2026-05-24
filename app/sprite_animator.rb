class SpriteAnimator
  attr_reader :path, :frames

  def initialize(path:, frames:, frame_duration: 6, start_tick: 0)
    @path = path
    @frames = frames
    @frame_duration = frame_duration
    @start_tick = start_tick
  end

  def frame_count
    @frames.length
  end

  def current_index(tick_count)
    elapsed = tick_count - @start_tick
    (elapsed.idiv(@frame_duration)) % frame_count
  end

  def current_frame(tick_count)
    @frames[current_index(tick_count)]
  end

  def sprite(tick_count, anchor_x:, anchor_y:, scale: 1.0)
    f = current_frame(tick_count)
    w = f[:w] * scale
    h = f[:h] * scale
    {
      x: anchor_x - (f[:cx_off] * scale),
      y: anchor_y - ((f[:h] - f[:cy_off]) * scale),
      w: w,
      h: h,
      path: @path,
      tile_x: f[:x],
      tile_y: f[:y],
      tile_w: f[:w],
      tile_h: f[:h],
      r: 255, g: 255, b: 255, a: 255,
      blendmode_enum: 1   # 1 = alpha blend (default, set explicitly to be safe)
    }
  end

  def reset(tick_count)
    @start_tick = tick_count
  end
end

module WalkFrames
  # Exact content bbox per frame (36x50 px, trimmed from 140x140 cells).
  # tile_x = frame_index * 140 + x_offset_within_cell
  X_OFFSETS = [58, 59, 58, 57, 56, 54, 55, 57].freeze
  W = 36; H = 50
  ALL = 8.times.map { |i|
    { x: i * 140 + X_OFFSETS[i], y: 47, w: W, h: H, cx_off: W / 2, cy_off: H / 2 }
  }.freeze
end

module CthulhuFrames
  # chthulu.png: 2880x784, cell_w=180, top-left tile origin.
  # Idle: row 1 (y=33), 16 frames. Attack: row 5 (y=365), 8 frames.
  IDLE = [
    { x:   64, y: 33, w:  60, h: 63, cx_off: 30, cy_off: 31 },
    { x:  256, y: 33, w:  60, h: 63, cx_off: 30, cy_off: 31 },
    { x:  448, y: 33, w:  60, h: 63, cx_off: 30, cy_off: 31 },
    { x:  640, y: 33, w:  60, h: 63, cx_off: 30, cy_off: 31 },
    { x:  832, y: 33, w:  60, h: 63, cx_off: 30, cy_off: 31 },
    { x: 1024, y: 32, w:  56, h: 64, cx_off: 28, cy_off: 32 },
    { x: 1080, y: 32, w: 180, h: 64, cx_off: 90, cy_off: 32 },
    { x: 1260, y: 32, w: 179, h: 64, cx_off: 89, cy_off: 32 },
    { x: 1443, y: 33, w: 177, h: 63, cx_off: 88, cy_off: 31 },
    { x: 1620, y: 32, w: 180, h: 64, cx_off: 90, cy_off: 32 },
    { x: 1800, y: 32, w:  52, h: 64, cx_off: 26, cy_off: 32 },
    { x: 1984, y: 33, w:  60, h: 63, cx_off: 30, cy_off: 31 },
    { x: 2176, y: 33, w:  60, h: 63, cx_off: 30, cy_off: 31 },
    { x: 2368, y: 33, w:  60, h: 63, cx_off: 30, cy_off: 31 },
    { x: 2560, y: 33, w:  60, h: 63, cx_off: 30, cy_off: 31 },
    { x: 2752, y: 33, w:  60, h: 63, cx_off: 30, cy_off: 31 },
  ].freeze

  ATTACK = [
    { x:   66, y: 365, w:  62, h: 67, cx_off: 31, cy_off: 33 },
    { x:  252, y: 367, w:  53, h: 65, cx_off: 26, cy_off: 32 },
    { x:  438, y: 367, w: 102, h: 65, cx_off: 51, cy_off: 32 },
    { x:  540, y: 369, w: 180, h: 63, cx_off: 90, cy_off: 31 },
    { x:  720, y: 370, w: 180, h: 62, cx_off: 90, cy_off: 31 },
    { x:  900, y: 370, w: 180, h: 62, cx_off: 90, cy_off: 31 },
    { x: 1080, y: 369, w: 180, h: 63, cx_off: 90, cy_off: 31 },
    { x: 1260, y: 370, w:  17, h: 51, cx_off:  8, cy_off: 25 },
  ].freeze
end

module AttackFrames
  # attack.png: 1820x140, 13 frames at 140px each, top-left tile origin.
  # F0-F7: wind-up. F8-12: projectile release (extends right of body).
  # cx_off anchored to character body center so player position stays stable.
  ALL = [
    { x:   57, y: 44, w: 32, h: 53, cx_off: 16, cy_off: 26 },
    { x:  196, y: 45, w: 32, h: 52, cx_off: 16, cy_off: 26 },
    { x:  334, y: 42, w: 30, h: 55, cx_off: 15, cy_off: 27 },
    { x:  474, y: 33, w: 23, h: 63, cx_off: 11, cy_off: 31 },
    { x:  612, y: 32, w: 25, h: 65, cx_off: 12, cy_off: 32 },
    { x:  751, y: 32, w: 26, h: 65, cx_off: 13, cy_off: 32 },
    { x:  894, y: 31, w: 23, h: 66, cx_off: 11, cy_off: 33 },
    { x: 1034, y: 33, w: 30, h: 64, cx_off: 15, cy_off: 32 },
    { x: 1170, y: 34, w: 63, h: 63, cx_off: 15, cy_off: 31 },
    { x: 1309, y: 36, w: 72, h: 61, cx_off: 16, cy_off: 30 },
    { x: 1450, y: 38, w: 79, h: 59, cx_off: 15, cy_off: 29 },
    { x: 1596, y: 39, w: 81, h: 57, cx_off:  9, cy_off: 28 },
    { x: 1737, y: 45, w: 68, h: 52, cx_off:  8, cy_off: 26 },
  ].freeze
end

module HunterFrames
  # hunter-run.png: 1200x150, 8 frames each 150x150, top-left origin.
  # Content bounds measured per frame; cx_off/cy_off = visual center within bbox.
  ALL = [
    { x:   61, y: 58, w: 25, h: 37, cx_off: 12.5, cy_off: 18.5 },
    { x:  206, y: 57, w: 33, h: 34, cx_off: 16.5, cy_off: 17.0 },
    { x:  360, y: 57, w: 25, h: 34, cx_off: 12.5, cy_off: 17.0 },
    { x:  514, y: 58, w: 18, h: 37, cx_off:  9.0, cy_off: 18.5 },
    { x:  659, y: 59, w: 25, h: 36, cx_off: 12.5, cy_off: 18.0 },
    { x:  806, y: 58, w: 34, h: 29, cx_off: 17.0, cy_off: 14.5 },
    { x:  959, y: 58, w: 27, h: 35, cx_off: 13.5, cy_off: 17.5 },
    { x: 1113, y: 59, w: 18, h: 36, cx_off:  9.0, cy_off: 18.0 },
  ].freeze
end

module CreatureFrames
  # Exact bounding boxes extracted from sprites/creature.png via
  # ImageMagick connected-components on alpha channel.
  # x,y,w,h = bbox in source PNG (top-left origin).
  # cx_off, cy_off = centroid offset from bbox top-left.
  # Order: top row left-to-right (frames 0-7), bottom row left-to-right (8-15).
  ALL = [
    { x:   0, y:  10, w: 118, h: 94, cx_off: 64.7,  cy_off: 51.2 },
    { x: 127, y:  13, w: 127, h: 87, cx_off: 62.8,  cy_off: 46.2 },
    { x: 261, y:  10, w: 119, h: 93, cx_off: 61.0,  cy_off: 48.5 },
    { x: 391, y:   7, w: 114, h: 95, cx_off: 58.0,  cy_off: 49.0 },
    { x: 515, y:  10, w: 119, h: 92, cx_off: 62.0,  cy_off: 47.9 },
    { x: 643, y:  11, w: 119, h: 94, cx_off: 60.5,  cy_off: 48.9 },
    { x: 772, y:  10, w: 119, h: 92, cx_off: 60.5,  cy_off: 47.7 },
    { x: 897, y:  11, w: 117, h: 92, cx_off: 64.5,  cy_off: 50.5 },
    { x:   6, y: 126, w: 115, h: 91, cx_off: 57.2,  cy_off: 47.8 },
    { x: 132, y: 126, w: 114, h: 92, cx_off: 59.6,  cy_off: 49.7 },
    { x: 259, y: 126, w: 121, h: 90, cx_off: 60.8,  cy_off: 48.6 },
    { x: 390, y: 126, w: 112, h: 91, cx_off: 58.3,  cy_off: 50.5 },
    { x: 515, y: 126, w: 121, h: 90, cx_off: 59.5,  cy_off: 46.6 },
    { x: 645, y: 126, w: 117, h: 90, cx_off: 63.3,  cy_off: 50.5 },
    { x: 770, y: 126, w: 117, h: 93, cx_off: 64.3,  cy_off: 51.5 },
    { x: 896, y: 126, w: 119, h: 92, cx_off: 65.2,  cy_off: 51.3 }
  ].freeze
end
