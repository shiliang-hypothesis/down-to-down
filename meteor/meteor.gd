extends Area2D
## 陨石：从画面上方砸向目标点，撞到可破坏物体后发出信号并销毁。
## 拖尾（Trail/Line2D）是 top_level 的世界空间折线，不跟随陨石旋转/平移。

signal meteor_impacted(impact_pos: Vector2, normal: Vector2) # 撞击点 + 表面法线（朝外）

@export var speed: float = 800.0
@export var offscreen_margin: float = 320.0 # 超出可视区域多远才回收
@export var trail_max_points: int = 18 # 拖尾最多保留多少个采样点（决定拖尾长度）
@export var trail_fade_time: float = 0.3 # 撞击后残留拖尾的淡出时间

var direction: Vector2 = Vector2.DOWN

var _impacted := false

@onready var _trail: Line2D = get_node_or_null("Trail") as Line2D

func _ready() -> void:
	# 1. 让陨石朝向飞行方向
	rotation = direction.angle()

	# 2. 开启粒子发射
	var particles := get_node_or_null("GPUParticles2D") as GPUParticles2D
	if particles != null:
		particles.emitting = true

	# 3. 破空声：每颗陨石的音高略有差异，连砸时不会像同一个采样在循环
	var whoosh := get_node_or_null("AudioStreamPlayer2D") as AudioStreamPlayer2D
	if whoosh != null:
		whoosh.pitch_scale = randf_range(0.88, 1.12)
		whoosh.play()

	# 4. 拖尾：脱离父级变换，点坐标即世界坐标，否则折线会跟着石头一起平移
	if _trail != null:
		_trail.top_level = true
		_trail.global_transform = Transform2D.IDENTITY
		_trail.clear_points()
		_trail.add_point(global_position)

func _physics_process(delta: float) -> void:
	if _impacted:
		return

	# 用射线扫过这一帧的位移，避免高速穿过薄瓦片（隧穿）
	var from := global_position
	var to := from + direction * speed * delta
	var query := PhysicsRayQueryParameters2D.create(from, to, collision_mask, [get_rid()])
	query.hit_from_inside = true # 万一出生在实体里也能立刻判定
	var hit := get_world_2d().direct_space_state.intersect_ray(query)

	if not hit.is_empty():
		# 注意：Dictionary.get() 返回 Variant，这里必须显式标注类型
		# 否则 Godot 4.6 会按 "inference_from_variant" 报错（该警告默认视为错误）
		var collider: Object = hit.get("collider")
		if _is_destructible(collider):
			var impact_pos: Vector2 = hit.get("position", global_position)
			var impact_normal: Vector2 = hit.get("normal", Vector2.UP)
			global_position = impact_pos
			_push_trail_point()
			_impact(impact_pos, impact_normal)
			return
		# 打到不可破坏的东西就穿过去，不在这里处理

	global_position = to
	_push_trail_point()

	# 越界回收：必须用"世界坐标"的可视矩形，不能用屏幕坐标的 get_viewport_rect()
	if not _view_world_rect().grow(offscreen_margin).has_point(global_position):
		_release_trail()
		queue_free()

## 把当前世界坐标压进拖尾，并丢掉过老的尾点
func _push_trail_point() -> void:
	if _trail == null:
		return
	_trail.add_point(global_position)
	while _trail.get_point_count() > maxi(2, trail_max_points):
		_trail.remove_point(0)

## 撞击/回收时，把拖尾留在世界里自己淡出，而不是跟着陨石一起消失
func _release_trail() -> void:
	if _trail == null or not is_instance_valid(_trail):
		return
	var trail := _trail
	_trail = null

	if trail.get_point_count() < 2:
		trail.queue_free()
		return

	var parent := get_parent()
	if parent == null:
		trail.queue_free()
		return

	# 换父亲但保持世界坐标，这样拖尾的线段位置不变
	trail.reparent(parent, true)

	# 注意：tween 必须挂在 SceneTree 上。挂在陨石（self.create_tween）上会随陨石
	# queue_free 一起被销毁，拖尾就会瞬间消失。
	var tree := get_tree()
	if tree == null:
		trail.queue_free()
		return
	var tween := tree.create_tween()
	tween.tween_property(trail, "modulate:a", 0.0, trail_fade_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(trail.queue_free)

func _is_destructible(body: Object) -> bool:
	if body == null:
		return false
	# TileMapLayer 的瓦片碰撞会以它自身作为 body 上报，所以先看类型
	if body is TileMapLayer:
		return true
	var node := body as Node
	return node != null and (node.is_in_group("ground") or node.is_in_group("destructible"))

func _impact(pos: Vector2, normal: Vector2) -> void:
	if _impacted:
		return
	_impacted = true
	_release_trail()
	meteor_impacted.emit(pos, normal)
	queue_free()

func _view_world_rect() -> Rect2:
	var viewport := get_viewport()
	return viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
