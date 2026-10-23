# ============================================================================
# SpriteLib — 像素精灵加载（静态工具，非 autoload）
# 职责：按「类别 + id」加载 assets/sprites/ 下的角色/敌人/地面/武器/被动精灵，
#       供敌人渲染（Sprite2D）、玩家渲染、HUD 图标共用。
# 数据源：assets/sprites/{category}/{id}.png（由 tools/generate_pixel_sprites.py 生成）
# 资源加载：ResourceLoader 优先（导出包内只有导入产物），干净检出回退
#           Image.load_from_file()（绕过 .import 直接读 PNG），与 PixelSkin 同策略
# 缓存：静态字典缓存已加载 Texture2D；release_cache() 供顶层场景退出时释放，
#       避免静态缓存比引擎纹理清理晚一步而报 "Texture ... leaked"。
# 红线：只按 id 查表加载，不写任何数值；缺资源返回 null 由调用方回退。
# ============================================================================
extends RefCounted

const _ROOT: String = "res://assets/sprites/"

static var _tex_cache: Dictionary = {}


func _init() -> void:
	return  # 静态工具类，禁止实例化（调用静态方法即可）


## 按类别 + id 加载精灵（category: enemies/player/ground/weapons/passives/ui）
static func sprite(category: String, id: String) -> Texture2D:
	if id == "":
		return null
	var path: String = _ROOT + category + "/" + id + ".png"
	return texture_path(path)


## 加载完整 res:// 路径的精灵
static func texture_path(path: String) -> Texture2D:
	if path == "":
		return null
	if _tex_cache.has(path):
		return _tex_cache[path] as Texture2D
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = ResourceLoader.load(path) as Texture2D
	if tex == null:
		var img: Image = Image.load_from_file(path)
		if img != null:
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		# 不 push_warning：机检里大量探测不存在的 id 会刷屏；需要严格时用 has_sprite
		_tex_cache[path] = null
		return null
	_tex_cache[path] = tex
	return tex


## 精灵是否存在（严格模式：不想静默回退时用）
static func has_sprite(category: String, id: String) -> bool:
	return texture_path(_ROOT + category + "/" + id + ".png") != null


## 敌人精灵（供 EnemyBase._apply_visual 用；id 回退到 prototype_id 由调用方处理）
static func enemy(id: String) -> Texture2D:
	return sprite("enemies", id)


static func player(id: String) -> Texture2D:
	return sprite("player", id)


static func ground(id: String) -> Texture2D:
	return sprite("ground", id)


static func weapon(id: String) -> Texture2D:
	return sprite("weapons", id)


static func passive(id: String) -> Texture2D:
	return sprite("passives", id)


## 召唤物精灵（武器 summon 块引用；水母/信天翁，24 逻辑 px）
static func summon(id: String) -> Texture2D:
	return sprite("summons", id)


## 世界装饰精灵（灯塔塔楼 / 竞技场礁石界桩；assets/sprites/world/）
static func world(id: String) -> Texture2D:
	return sprite("world", id)


## 释放静态缓存（顶层场景 _exit_tree 调用；同 PixelSkin.release_cache 的理由）
static func release_cache() -> void:
	_tex_cache.clear()


## 机检用：清空缓存
static func reset_cache_for_test() -> void:
	release_cache()