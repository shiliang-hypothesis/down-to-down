extends Node2D
## 撞击爆发特效：一次性播放，播完自己销毁。
## 三层粒子（火星 / 尘土 / 余烬）+ 三段声音（炸响 / 撕裂 / 石子）+ 瞬时点光 + 一帧闪光。

@export var fx_lifetime: float = 2.0 # 真实时间（不受 time_scale 影响）
@export var flash_grow: float = 0.18
@export var light_fade: float = 0.35

@onready var _light: PointLight2D = get_node_or_null("Light") as PointLight2D
@onready var _flash: Sprite2D = get_node_or_null("Flash") as Sprite2D
@onready var _rattle: AudioStreamPlayer2D = get_node_or_null("Rattle") as AudioStreamPlayer2D

func _ready() -> void:
	# 1. 粒子全部点火
	for child in get_children():
		if child is GPUParticles2D:
			(child as GPUParticles2D).emitting = true

	# 2. 声音：炸响和撕裂立刻响，石子晚 90ms（先炸开，再落地），
	#    每发随机音高/音量，连砸时不会听起来像同一个采样在循环。
	var tree := get_tree()
	for child in get_children():
		if child is AudioStreamPlayer2D:
			var player := child as AudioStreamPlayer2D
			player.pitch_scale = randf_range(0.9, 1.12)
			player.volume_db += randf_range(-1.5, 1.5)
			if player == _rattle:
				continue
			player.play()
	if _rattle != null and tree != null:
		# ignore_time_scale = true：顿帧期间也要照常延迟，否则会拖成 0.75 秒
		tree.create_timer(0.09, true, false, true).timeout.connect(_rattle.play)

	# 3. 闪光：快速放大 + 淡出
	if _flash != null:
		var flash_tween := create_tween().set_parallel(true)
		flash_tween.tween_property(_flash, "scale", _flash.scale * 2.2, flash_grow) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		flash_tween.tween_property(_flash, "modulate:a", 0.0, flash_grow)

	# 4. 点光：能量指数衰减，撞击瞬间照亮周围地面和夜空
	if _light != null:
		var light_tween := create_tween()
		light_tween.tween_property(_light, "energy", 0.0, light_fade) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	# 5. 用信号一次性连接销毁，避免 await 期间对象已被释放导致的报错
	if tree != null:
		tree.create_timer(fx_lifetime, true, false, true).timeout.connect(queue_free)
