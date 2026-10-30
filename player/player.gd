class_name Player
extends CharacterBody2D
## 小小灯火：被陨石砸来砸去的那块地面上，唯一会走动的东西。
##
## 这一版只留下这款游戏需要的两件事：
##   1) 走 / 跳 —— 小人不会被陨石炸死，所以没有血量、受伤、击飞、死亡；
##   2) 带来视野 —— 身上的灯照亮夜色，视野半径由 Game 的星光进度决定。
##
## 动画仍然由 AnimationPlayer 里的 idle / running / jump / fall / landing 负责，
## 脚本只决定"什么时候播哪一段"，不碰关键帧、贴图和道具资源。

enum State {
	IDLE,
	RUNNING,
	JUMP,
	FALL,
	LANDING,
}

const GROUND_STATE := [State.IDLE, State.RUNNING, State.LANDING] # 在地面的状态
const RUN_SPEED := 150.0 # 跑速
const FLOOR_ACCELERATION := RUN_SPEED / 0.14 # 地面加速度
const AIR_ACCELERATION := RUN_SPEED / 0.45 # 空中加速度
const JUMP_VELOCITY := -340.0 # 跳跃量
const JUMP_CUT := 0.45 # 松开跳跃键后保留多少上升速度
const VIEW_MARGIN := 24.0 # 小人离画面边缘至少这么远
const FALL_OUT_MARGIN := 200.0 # 掉出画面这么远就送回出生点
const LIGHT_TEXTURE_RADIUS := 32.0 # glow.png 的半径（像素）：视野半径 = 32 * texture_scale

var default_gravity: float = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
var is_first_tick := false # 跳跃第一帧不加重力，手感更跟手
var spawn_point := Vector2.ZERO

var _light_energy := 1.0
var _lantern_alpha := 1.0
var _flicker := 0.0
var _light_pulse := 0.0
var _vision_tween: Tween

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var coyote_timer: Timer = $CoyoteTimer # 郊狼时间
@onready var jump_request_timer: Timer = $JumpRequestTimer # 跳跃预输入
@onready var graphics: Node2D = $Graphics
@onready var state_machine: StateMachine = $StateMachine

@onready var vision: PointLight2D = $Vision
@onready var lantern: Sprite2D = $Lantern


func _ready() -> void:
	spawn_point = global_position
	_light_energy = vision.energy
	_lantern_alpha = lantern.modulate.a
	_apply_vision(Game.vision_radius, false)
	Game.vision_changed.connect(_on_vision_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		jump_request_timer.start()
	if event.is_action_released("jump") and velocity.y < JUMP_VELOCITY * JUMP_CUT:
		velocity.y = JUMP_VELOCITY * JUMP_CUT


func _process(delta: float) -> void:
	# 灯火呼吸：两种频率叠一点点抖动，小人和光都"活着"
	_flicker += delta * 6.0
	_light_pulse = maxf(0.0, _light_pulse - delta * 2.5)
	var wobble := 1.0 + sin(_flicker) * 0.035 + sin(_flicker * 2.3 + 1.7) * 0.025
	vision.energy = (_light_energy + _light_pulse) * wobble
	lantern.modulate.a = _lantern_alpha * (0.94 + sin(_flicker) * 0.06)


# ---------------------------------------------------------------- 状态机回调

func tick_physics(state: State, delta: float) -> void: # 每帧做的事
	match state:
		State.IDLE, State.RUNNING, State.FALL:
			move(default_gravity, delta)

		State.JUMP:
			move(0.0 if is_first_tick else default_gravity, delta)

		State.LANDING:
			stand(delta)

	is_first_tick = false


func get_next_state(state: State) -> int: # 输入改变
	var can_jump := is_on_floor() or coyote_timer.time_left > 0.0
	var should_jump := can_jump and jump_request_timer.time_left > 0.0
	if should_jump:
		return State.JUMP

	if state in GROUND_STATE and not is_on_floor():
		return State.FALL

	var direction := Input.get_axis("move_left", "move_right")
	var is_still := is_zero_approx(direction) and is_zero_approx(velocity.x)
	match state:
		State.IDLE:
			if not is_still:
				return State.RUNNING

		State.RUNNING:
			if is_still:
				return State.IDLE

		State.JUMP:
			if velocity.y >= 0.0:
				return State.FALL

		State.FALL:
			if is_on_floor():
				return State.LANDING

		State.LANDING:
			if not animation_player.is_playing():
				return State.IDLE

	return StateMachine.KEEP_CURRENT


func transition_state(from: State, to: State) -> void: # 状态改变：from，to
	if from not in GROUND_STATE and to in GROUND_STATE:
		coyote_timer.stop()

	match to:
		State.IDLE:
			animation_player.play("idle")

		State.RUNNING:
			animation_player.play("running")

		State.JUMP:
			animation_player.play("jump")
			velocity.y = JUMP_VELOCITY
			coyote_timer.stop()
			jump_request_timer.stop()

		State.FALL:
			animation_player.play("fall")
			if from in GROUND_STATE:
				coyote_timer.start()

		State.LANDING:
			animation_player.play("landing")

	is_first_tick = true


# ---------------------------------------------------------------- 移动

func move(gravity: float, delta: float) -> void: # 移动
	var direction := Input.get_axis("move_left", "move_right")
	var acceleration := FLOOR_ACCELERATION if is_on_floor() else AIR_ACCELERATION
	velocity.x = move_toward(velocity.x, direction * RUN_SPEED, acceleration * delta)
	velocity.y += gravity * delta

	if not is_zero_approx(direction):
		graphics.scale.x = -1.0 if direction < 0.0 else 1.0

	move_and_slide()
	_keep_inside_view()
	_reset_if_fell_out()


func stand(delta: float) -> void:
	var acceleration := FLOOR_ACCELERATION if is_on_floor() else AIR_ACCELERATION
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.y += default_gravity * delta

	move_and_slide()
	_keep_inside_view()
	_reset_if_fell_out()


# ---------------------------------------------------------------- 视野

func _on_vision_changed(_level: int, radius: float) -> void:
	_apply_vision(radius)
	_light_pulse = 1.8 # 升级的瞬间，灯会突然亮一下


func _apply_vision(radius: float, animate: bool = true) -> void:
	var target := radius / LIGHT_TEXTURE_RADIUS
	if not animate:
		vision.texture_scale = target
		return

	if _vision_tween != null and _vision_tween.is_valid():
		_vision_tween.kill()
	_vision_tween = create_tween()
	_vision_tween.tween_property(vision, "texture_scale", target, 0.8) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- 兜底

func _keep_inside_view() -> void:
	# 这一关只有一屏，把小人拦在画面里：视野始终留在玩家眼前
	var view := _view_world_rect()
	if view.size.x <= 0.0:
		return
	global_position.x = clampf(global_position.x, view.position.x + VIEW_MARGIN, view.end.x - VIEW_MARGIN)


func _reset_if_fell_out() -> void:
	var view := _view_world_rect()
	if view.size.y <= 0.0:
		return
	if global_position.y > view.end.y + FALL_OUT_MARGIN:
		global_position = spawn_point
		velocity = Vector2.ZERO


func _view_world_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport == null:
		return Rect2()
	return viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
