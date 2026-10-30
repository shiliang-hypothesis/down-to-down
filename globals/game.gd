extends CanvasLayer
## Game —— 全局单例（在 project.godot 的 autoload 里注册）。
##
## 「碰撞」就是这款游戏的资源：每一次陨石撞地，都会变成一点星光；
## 星光攒够，小人身上那盏灯的视野就变大一圈。
## 所以这里只保留三件事：撞击 → 星光 → 视野（外加一次很轻的全屏暖光）。
## 旧的存档 / 切场景 / 世界切换逻辑都删掉了 —— 这一关只有一块地面。
##
## 给其他节点用的接口：
##   Game.register_impact(pos, normal)  # 手动登记一次碰撞
##   Game.add_stardust(amount)          # 直接给/扣星光（以后做升级消费用）
##   Game.stardust                      # 累计星光
##   Game.vision_radius                 # 当前视野半径（像素）
##   Game.progress                      # 0~1，离"心愿完成"还有多远
##   Game.vision_changed.connect(...)   # 视野升级时刷新表现
##   Game.flash()                       # 一次很轻的全屏暖光
##
## 注意：陨石撞击是自动登记的（见 _on_node_added），不需要改 world 的代码；
## 如果以后不想自动登记，把 auto_track_meteors 关掉，手动调 register_impact。

signal impact_registered(impact_pos: Vector2, normal: Vector2)
signal stardust_changed(total: int, gained: int)
signal vision_changed(level: int, radius: float)
signal wish_completed()

@export_group("星光")
@export var stardust_per_impact: int = 1 # 一次撞击给多少星光
@export var stardust_per_vision: int = 3 # 每多少星光，视野升一级
@export var max_vision_level: int = 5 # 最多升几级

@export_group("视野")
@export var vision_base_radius: float = 170.0 # 一级视野半径（像素）
@export var vision_max_radius: float = 430.0 # 满级视野半径（像素）

@export_group("自动收集撞击")
@export var auto_track_meteors: bool = true # 陨石出生时自动监听它的撞击信号

@onready var _flash: ColorRect = get_node_or_null("Flash") as ColorRect

var stardust: int = 0 # 累计星光
var vision_level: int = 0 # 当前视野等级
var vision_radius: float = 0.0 # 当前视野半径（像素）
var progress: float = 0.0 # 0~1 心愿完成度
var wish_granted := false


func _ready() -> void:
	if _flash != null:
		_flash.color = Color(_flash.color.r, _flash.color.g, _flash.color.b, 0.0)

	vision_radius = vision_base_radius
	_refresh_progression()

	if auto_track_meteors:
		get_tree().node_added.connect(_on_node_added)
		for meteor in get_tree().get_nodes_in_group("meteor"):
			_track_meteor(meteor)


## 登记一次碰撞：加星光、发信号、顺便看看要不要升级视野。
func register_impact(impact_pos: Vector2 = Vector2.ZERO, normal: Vector2 = Vector2.UP) -> void:
	var gained := stardust_per_impact
	stardust += gained
	impact_registered.emit(impact_pos, normal)
	stardust_changed.emit(stardust, gained)
	_refresh_progression()


## 直接改变星光数（做升级消费、事件奖励时用）。
func add_stardust(amount: int) -> void:
	stardust = maxi(0, stardust + amount)
	stardust_changed.emit(stardust, amount)
	_refresh_progression()


## 重新开始：清零星光，把视野收回一级。
func reset() -> void:
	stardust = 0
	vision_level = 0
	vision_radius = vision_base_radius
	progress = 0.0
	wish_granted = false
	vision_changed.emit(vision_level, vision_radius)
	stardust_changed.emit(stardust, 0)


## 一次很轻的全屏暖光，用来标一下"升级了"。
func flash(color: Color = Color(1, 0.86, 0.6), duration: float = 0.6, alpha: float = 0.16) -> void:
	if _flash == null:
		return
	_flash.color = Color(color.r, color.g, color.b, 0.0)
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", alpha, duration * 0.2)
	tween.tween_property(_flash, "color:a", 0.0, duration * 0.8)


# ---------------------------------------------------------------- 内部

## 星光 → 视野等级 / 半径 / 进度。整数除法就是"够了几级"。
func _refresh_progression() -> void:
	var level := mini(stardust / maxi(1, stardust_per_vision), max_vision_level)
	if level != vision_level:
		vision_level = level
		var t := float(vision_level) / float(maxi(1, max_vision_level))
		vision_radius = lerpf(vision_base_radius, vision_max_radius, t)
		vision_changed.emit(vision_level, vision_radius)

	var goal := maxi(1, stardust_per_vision * maxi(1, max_vision_level))
	progress = clampf(float(stardust) / float(goal), 0.0, 1.0)
	if progress >= 1.0 and not wish_granted:
		wish_granted = true
		wish_completed.emit()
		flash()


func _on_node_added(node: Node) -> void:
	if node.is_in_group("meteor"):
		_track_meteor(node)


func _track_meteor(meteor: Node) -> void:
	if not meteor.has_signal("meteor_impacted"):
		return
	var callback := Callable(self, "_on_meteor_impacted")
	if not meteor.is_connected("meteor_impacted", callback):
		meteor.connect("meteor_impacted", callback)


func _on_meteor_impacted(impact_pos: Vector2, normal: Vector2) -> void:
	register_impact(impact_pos, normal)
