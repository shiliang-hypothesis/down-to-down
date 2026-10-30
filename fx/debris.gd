extends RigidBody2D
## 撞击溅出的碎石：随机图集帧、随机朝向，几秒后淡出回收。
## 它会被地面和彼此碰撞，所以能滚、能落、能堆 —— 免费的物理可信度。

@export var life_time: float = 3.0
@export var fade_time: float = 0.6

func _ready() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		var frames := maxi(1, sprite.hframes * sprite.vframes)
		sprite.frame = randi() % frames
		sprite.rotation = randf() * TAU

	var tween := create_tween()
	tween.tween_interval(life_time)
	tween.tween_property(self, "modulate:a", 0.0, fade_time)
	tween.tween_callback(queue_free)
