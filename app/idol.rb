class Idol
  attr_accessor :x, :y

  def initialize(x: 0.0, y: 0.0, placed: false)
    @x = x.to_f
    @y = y.to_f
    @placed = placed
  end

  def placed?
    @placed
  end

  def pickup!
    @placed = false
  end

  def place_at(x, y)
    @x = x.to_f
    @y = y.to_f
    @placed = true
  end

  def distance_sq_to(px, py)
    dx = @x - px
    dy = @y - py
    dx * dx + dy * dy
  end

  def near?(px, py, r)
    distance_sq_to(px, py) < r * r
  end

  def signature
    @placed ? [@x.to_i, @y.to_i] : nil
  end
end
