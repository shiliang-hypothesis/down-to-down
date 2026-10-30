extends Node2D
## 世界：点击 → 从天而降陨石 → 撞击地面，破坏地形并触发撞击瞬间反馈。

const IMPACT_FX := preload("res://fx/impact.tscn")
const DEBRIS := preload("res://fx/debris.tscn")

@export var meteor_scene: PackedScene # 把 Meteor.tscn 拖到这里
@export var crater_radius: float = 30.0 # 单次撞击的破坏半径（像素）
@export var spawn_height: float = 120.0 # 在可视区域上方多高处生成陨石
@export var aim_jitter: float = 10.0 # 落点随机偏移，让坑边缘更自然

@export_group("撞击瞬间")
@export var debris_count: int = 6 # 溅出的碎石数量
@export var shake_trauma: float = 0.38 # 震屏强度（0~1）
@export var hitstop_time: float = 0.05 # 顿帧时长（真实秒）
@export var hitstop_scale: float = 0.12 # 顿帧期间的时间缩放

@onready var ground: TileMapLayer = $ground
@onready var camera: Camera2D = $Camera2D

var _hitstop_token := 0

func _ready() -> void:
	# 让 ground 自己有身份，陨石那边既认类型也认组
	ground.add_to_group("ground")
	ground.add_to_group("destructible")

func _exit_tree() -> void:
	# 保险：无论如何都别把游戏留在慢动作里
	Engine.time_scale = 1.0

func _unhandled_input(event: InputEvent) -> void:
	# 使用 _unhandled_input 可以防止鼠标点击 UI 时也发射陨石
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_launch_meteor(get_global_mouse_position())

func _launch_meteor(target: Vector2) -> void:
	if meteor_scene == null:
		push_warning("meteor_scene 没有指定：请在 Test 节点上拖入 meteor.tscn")
		return

	# 出生点 = 点击处的正上方、刚好在画面外
	var spawn := Vector2(target.x, _view_world_rect().position.y - spawn_height)
	var jitter := Vector2(randf_range(-aim_jitter, aim_jitter), randf_range(-aim_jitter, aim_jitter))
	var dir := (target + jitter - spawn).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN

	var meteor := meteor_scene.instantiate()
	meteor.position = spawn
	meteor.direction = dir
	meteor.meteor_impacted.connect(_on_meteor_impacted)
	add_child(meteor)

func _on_meteor_impacted(impact_pos: Vector2, normal: Vector2) -> void:
	# 顺序很重要：先破坏地形，再撒特效/碎屑，否则碎屑会生成在还没挖掉的瓦片里
	_carve(impact_pos, normal, crater_radius)
	_spawn_impact(impact_pos)
	_spawn_debris(impact_pos, normal)
	if camera != null and camera.has_method("add_trauma"):
		camera.add_trauma(shake_trauma)
	_hitstop(hitstop_time, hitstop_scale)

func _spawn_impact(pos: Vector2) -> void:
	var fx: Node2D = IMPACT_FX.instantiate() as Node2D
	if fx == null:
		return
	fx.position = pos
	add_child(fx)

func _spawn_debris(pos: Vector2, normal: Vector2) -> void:
	var eject := normal.normalized()
	if eject == Vector2.ZERO:
		eject = Vector2.UP

	for i in debris_count:
		var chunk: RigidBody2D = DEBRIS.instantiate() as RigidBody2D
		if chunk == null:
			continue
		chunk.position = pos + Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0))
		add_child(chunk)
		var dir := eject.rotated(randf_range(-1.1, 1.1))
		chunk.linear_velocity = dir * randf_range(90.0, 300.0)
		chunk.angular_velocity = randf_range(-9.0, 9.0)

## 顿帧：把时间压慢一瞬间再恢复。叠加调用时用 token 保证只由最后一发负责恢复。
func _hitstop(duration: float, scale_factor: float) -> void:
	_hitstop_token += 1
	var token := _hitstop_token
	Engine.time_scale = scale_factor

	# 第 4 个参数 ignore_time_scale = true 是关键：
	# 否则计时器自己也会被减速，time_scale 就永远恢复不了（jam 经典卡死 bug）
	var timer := get_tree().create_timer(duration, true, false, true)
	timer.timeout.connect(_end_hitstop.bind(token))

func _end_hitstop(token: int) -> void:
	if token != _hitstop_token:
		return
	Engine.time_scale = 1.0

## 以世界坐标为中心，把半径内的瓦片挖掉（边缘带随机抖动，避免完美圆形）
func _carve(world_pos: Vector2, normal: Vector2, radius_px: float) -> void:
	if ground.tile_set == null:
		return
	var tile_size := float(ground.tile_set.tile_size.x)
	if tile_size <= 0.0:
		return

	# 关键：接触点常正好落在瓦片边界上，local_to_map 会向"空气"取整，
	# 导致大半个坑挖在空气里。沿法线往实体里推半格，才是真正的碗形坑。
	var surface_normal := normal.normalized()
	if surface_normal == Vector2.ZERO:
		surface_normal = Vector2.UP
	var center_world := world_pos - surface_normal * (tile_size * 0.5)
	var center := ground.local_to_map(ground.to_local(center_world))

	var radius_cells := radius_px / tile_size
	var reach := int(ceil(radius_cells))

	for x in range(-reach, reach + 1):
		for y in range(-reach, reach + 1):
			if Vector2(x, y).length() <= radius_cells + randf_range(-0.3, 0.3):
				ground.erase_cell(center + Vector2i(x, y))

func _view_world_rect() -> Rect2:
	var viewport := get_viewport()
	return viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
