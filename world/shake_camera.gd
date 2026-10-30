extends Camera2D
## 创伤式震屏：累积 trauma，位移/旋转按 trauma² 输出，平滑噪声而不是纯随机抖。
## 用法：camera.add_trauma(0.3)

@export var max_offset := Vector2(13.0, 9.0) # 最大位移（像素）
@export var max_rotation_deg: float = 0.7 # 最大旋转（度）
@export var decay: float = 2.6 # 每秒衰减多少 trauma
@export var noise_speed: float = 26.0 # 抖动快慢

var _trauma := 0.0
var _time := 0.0
var _noise_x := FastNoiseLite.new()
var _noise_y := FastNoiseLite.new()
var _noise_r := FastNoiseLite.new()

func _ready() -> void:
	for noise in [_noise_x, _noise_y, _noise_r]:
		var n := noise as FastNoiseLite
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n.frequency = 1.0
		n.seed = randi()

func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

func _process(delta: float) -> void:
	_time += delta * noise_speed

	if _trauma <= 0.0:
		offset = Vector2.ZERO
		rotation = 0.0
		return

	_trauma = maxf(0.0, _trauma - decay * delta)
	var amount := _trauma * _trauma # 平方衰减：小抖动快消失，大抖动有重量

	offset = Vector2(
		_noise_x.get_noise_1d(_time),
		_noise_y.get_noise_1d(_time)
	) * max_offset * amount
	rotation = deg_to_rad(_noise_r.get_noise_1d(_time) * max_rotation_deg) * amount
