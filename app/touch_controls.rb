class TouchControls
  JOYSTICK_MAX_DIST = 48

  BTN_R        = 48
  REPEL_BTN    = { cx: 1190, cy: 100,  r: BTN_R }
  INTERACT_BTN = { cx: 1100, cy: 195,  r: BTN_R }
  PAUSE_BTN    = { cx: 1248, cy: 682,  r: 22    }

  CIRCLE = 'sprites/circle/solid.png'

  attr_reader :dx, :dy, :repel_held, :interact_tap, :pause_tap

  def initialize
    @joystick       = nil
    @thumb_x        = 0.0
    @thumb_y        = 0.0
    @touch_seen     = false
    @mouse_was_held = false
    @repel_was      = false
    @interact_was   = false
    @pause_was      = false
    clear_outputs
  end

  def touch_seen?
    @touch_seen
  end

  def tick(args)
    clear_outputs
    if args.gtk.platform == 'Web'
      lf = args.inputs.finger_left
      rf = args.inputs.finger_right
      @touch_seen = true if lf || rf
      tick_joystick(lf)
      tick_buttons(rf)
    else
      @touch_seen = true
      m    = args.inputs.mouse
      held = m.button_left
      @mouse_was_held = held
      tick_joystick(held && m.x < 700 ? m : nil)
      tick_buttons(held && m.x >= 700 ? m : nil)
    end
  end

  def render(args)
    return unless @touch_seen
    render_joystick(args)
    render_button(args, REPEL_BTN,    'E',   @repel_held)
    render_button(args, INTERACT_BTN, 'USE', @interact_held)
    render_button(args, PAUSE_BTN,    'II',  false, small: true)
  end

  private

  def clear_outputs
    @dx            = 0.0
    @dy            = 0.0
    @repel_held    = false
    @interact_held = false
    @interact_tap  = false
    @pause_tap     = false
  end

  def tick_joystick(finger)
    unless finger
      if @joystick
        @joystick[:a] = @joystick[:a].lerp(0, 0.25)
        @joystick = nil if @joystick[:a] < 1
      end
      return
    end

    @joystick ||= { x: finger.x.to_f, y: finger.y.to_f, a: 0.0 }

    dist  = Geometry.distance(finger, @joystick)
    angle = Geometry.angle(finger, @joystick)
    vec   = angle.to_vector

    if dist > JOYSTICK_MAX_DIST
      @joystick[:x] = @joystick[:x].lerp(finger.x + vec.x * JOYSTICK_MAX_DIST, 0.1)
      @joystick[:y] = @joystick[:y].lerp(finger.y + vec.y * JOYSTICK_MAX_DIST, 0.1)
    end

    perc      = dist.clamp(0, JOYSTICK_MAX_DIST).fdiv(JOYSTICK_MAX_DIST)
    dir_angle = (angle + 180) % 360
    dir_vec   = dir_angle.to_vector

    @dx = dir_vec.x * perc ** 2
    @dy = dir_vec.y * perc ** 2

    actual = [dist, JOYSTICK_MAX_DIST].min
    @thumb_x = @joystick[:x] + dir_vec.x * actual
    @thumb_y = @joystick[:y] + dir_vec.y * actual

    @joystick[:a] = @joystick[:a].lerp(200, 0.15)
  end

  def tick_buttons(finger)
    now_repel    = finger && in_circle?(finger.x, finger.y, REPEL_BTN[:cx],    REPEL_BTN[:cy],    REPEL_BTN[:r])
    now_interact = finger && in_circle?(finger.x, finger.y, INTERACT_BTN[:cx], INTERACT_BTN[:cy], INTERACT_BTN[:r])
    now_pause    = finger && in_circle?(finger.x, finger.y, PAUSE_BTN[:cx],    PAUSE_BTN[:cy],    PAUSE_BTN[:r])

    @repel_held    = !!now_repel
    @interact_held = !!now_interact
    @interact_tap  = !!(now_interact && !@interact_was)
    @pause_tap     = !!(now_pause    && !@pause_was)

    @repel_was    = now_repel
    @interact_was = now_interact
    @pause_was    = now_pause
  end

  def in_circle?(px, py, cx, cy, r)
    dx = px - cx; dy = py - cy
    dx * dx + dy * dy <= r * r
  end

  def render_joystick(args)
    return unless @joystick
    a = @joystick[:a].to_i

    # Base ring
    d = JOYSTICK_MAX_DIST * 2 + 24
    args.outputs.sprites << {
      x: @joystick[:x], y: @joystick[:y], w: d, h: d,
      path: CIRCLE, anchor_x: 0.5, anchor_y: 0.5,
      r: 120, g: 90, b: 200, a: (a * 0.45).to_i
    }

    # Thumb
    args.outputs.sprites << {
      x: @thumb_x, y: @thumb_y, w: 50, h: 50,
      path: CIRCLE, anchor_x: 0.5, anchor_y: 0.5,
      r: 210, g: 195, b: 245, a: a
    }
  end

  def render_button(args, btn, label, active, small: false)
    r  = btn[:r]
    cr = active ? 230 : 160
    cg = active ? 180 : 120
    cb = active ? 255 : 210
    ba = active ? 200 : 90

    args.outputs.sprites << {
      x: btn[:cx], y: btn[:cy], w: r * 2, h: r * 2,
      path: CIRCLE, anchor_x: 0.5, anchor_y: 0.5,
      r: 14, g: 8, b: 32, a: ba
    }
    args.outputs.sprites << {
      x: btn[:cx], y: btn[:cy], w: r * 2 - 8, h: r * 2 - 8,
      path: CIRCLE, anchor_x: 0.5, anchor_y: 0.5,
      r: cr, g: cg, b: cb, a: (ba * 0.35).to_i
    }
    args.outputs.labels << {
      x: btn[:cx], y: btn[:cy] + 6,
      text: label, alignment_enum: 1,
      size_enum: small ? -2 : 1,
      r: cr, g: cg, b: cb, a: 240
    }
  end
end
