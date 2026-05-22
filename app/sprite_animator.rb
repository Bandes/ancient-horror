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
