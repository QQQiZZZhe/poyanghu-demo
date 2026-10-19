extends CanvasLayer
## 评审视频演示导演
## 用法（录制）：godot --path <工程> res://scenes/demo.tscn --write-movie <目录>/f.png --fixed-fps 30
## 说明：只调用 main.gd 的既有入口与真实 UI，不修改玩法逻辑、不伪造数据。
## 演示流程按评审片分镜走：片头 → 立意（主菜单/知识卡图鉴）→ 开局 → 玩法 → 技术 → 结尾。

var main: Node
var _sub: Label
var _bar: Panel
var _chapter_root: Control
var _chapter_title: Label
var _chapter_sub: Label
var _tick: Label
var _chapter_tween: Tween
var _bar_tween: Tween
var _speak_id := 0
var _quit_when_done := true
var _time_scale := 1.0
var _skip_intro := false

const NORMAL := 1

func _ready() -> void:
	main = get_parent().get_node_or_null("Main/Game")
	if main == null:
		push_error("demo: Main/Game not found")
		return
	_remove_record_button()
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a == "--no-quit":
			_quit_when_done = false
		elif a == "--fast":
			_time_scale = 0.08
		elif a == "--skip-intro":
			_skip_intro = true
	_build_overlay()
	_ensure_knowledge_state()
	var movie := _is_movie_mode()
	if not movie:
		await _countdown(3)
	print("[demo] begin")
	await _run()
	print("[demo] done t=", Time.get_ticks_msec()/1000.0)
	if movie:
		if _quit_when_done:
			get_tree().quit(0)
	else:
		# 从开始页点按钮进来的：先打一张「演示结束」，再回开始页，方便接着录第二遍
		await _card("演示结束", "回到开始页可以重录一遍", 2.0)
		get_tree().set_meta("demo_from_button", false)
		get_tree().change_scene_to_file("res://scenes/main.tscn")


func _is_movie_mode() -> bool:
	# 别用命令行判断：--write-movie 是引擎参数，OS.get_cmdline_args() 里有时拿不到，
	# 误判会让录完的片子又切回开始页、无限重录一遍。改由开始页那颗按钮打标记，
	# 没有标记就是命令行录制。
	return not bool(get_tree().get_meta("demo_from_button", false))


## 点按钮进来先数三秒，给录屏软件留出点「开始录制」的时间；自动录制时跳过。
func _countdown(sec: int) -> void:
	_chapter_title.text = "录制演示"
	for i in range(sec, 0, -1):
		_chapter_sub.text = "%d 秒后开始 · 先把录屏点开" % i
		_chapter_root.visible = true
		_chapter_root.modulate.a = 1.0
		await get_tree().create_timer(1.0).timeout
	_chapter_root.visible = false

## demo 场景里也会实例化一份 main（连同开始页那颗「录制演示」按钮），
## 录进片子会露在右下角，所以一进来就把它删掉。
func _remove_record_button() -> void:
	if main.menu_root == null:
		return
	for n in main.menu_root.get_children():
		if str(n.name).begins_with("RecordDemo"):
			n.queue_free()


## 录制用的图鉴状态：除彩蛋「狄鑫斛」外全部点亮，彩蛋保持未解锁。
## 放在导演里而不是一次性改存档，是为了清过档之后重录也能自己恢复。
func _ensure_knowledge_state() -> void:
	for kid in Knowledge.all_ids():
		var sid := str(kid)
		if sid == "egg_dixinhu":
			continue
		Knowledge.unlock(sid)
	if Knowledge.is_collected("egg_dixinhu"):
		Knowledge._collected.erase("egg_dixinhu")
		Knowledge._save()
	print("[demo] knowledge ", Knowledge.collected_count(), "/", Knowledge.total_count())


# ---------------- 覆盖层 ----------------

func _build_overlay() -> void:
	layer = 120
	var root := Control.new()
	root.name = "DemoUI"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# 顶部解说条：避让手牌与左右两侧 HUD
	_bar = Panel.new()
	_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bar.offset_left = -450
	_bar.offset_right = 450
	_bar.offset_top = -150
	_bar.offset_bottom = -98
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.06, 0.09, 0.86)
	sb.border_color = Color(0.86, 0.78, 0.50, 0.40)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("panel", sb)
	_bar.modulate.a = 0.0
	root.add_child(_bar)

	_sub = Label.new()
	_sub.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.add_theme_font_size_override("font_size", 21)
	_sub.add_theme_color_override("font_color", Color(0.97, 0.96, 0.91))
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_sub)

	# 章节卡
	_chapter_root = Control.new()
	_chapter_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chapter_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chapter_root.visible = false
	root.add_child(_chapter_root)
	var bg := ColorRect.new()
	bg.color = Color(0.025, 0.06, 0.085, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chapter_root.add_child(bg)
	var glow := ColorRect.new()
	glow.color = Color(0.55, 0.72, 0.60, 0.05)
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chapter_root.add_child(glow)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 20)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chapter_root.add_child(box)
	_chapter_title = Label.new()
	_chapter_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chapter_title.add_theme_font_size_override("font_size", 44)
	_chapter_title.add_theme_color_override("font_color", Color(0.91, 0.81, 0.52))
	box.add_child(_chapter_title)
	_chapter_sub = Label.new()
	_chapter_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chapter_sub.add_theme_font_size_override("font_size", 19)
	_chapter_sub.add_theme_color_override("font_color", Color(0.78, 0.85, 0.87))
	box.add_child(_chapter_sub)

	_tick = Label.new()
	_tick.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_tick.offset_left = -170
	_tick.offset_top = 18
	_tick.offset_right = -18
	_tick.offset_bottom = 44
	_tick.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tick.add_theme_font_size_override("font_size", 13)
	_tick.add_theme_color_override("font_color", Color(0.75, 0.82, 0.80, 0.55))
	_tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_tick)

# ---------------- 基础节拍 ----------------

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec * _time_scale).timeout

func _say(text: String, hold := 3.0) -> void:
	_speak_id += 1
	var my := _speak_id
	_sub.text = text
	await get_tree().process_frame
	_fit_sub_bar()
	if _bar_tween and _bar_tween.is_valid():
		_bar_tween.kill()
	_bar_tween = create_tween()
	_bar_tween.tween_property(_bar, "modulate:a", 1.0, 0.28)
	await _wait(hold)
	if my != _speak_id:
		return
	if _bar_tween and _bar_tween.is_valid():
		_bar_tween.kill()
	_bar_tween = create_tween()
	_bar_tween.tween_property(_bar, "modulate:a", 0.0, 0.22)

func _mute_sub() -> void:
	_speak_id += 1
	_bar.modulate.a = 0.0

## 解说条高度按文字行数长：一句能放进 900px 就还是 52px 一条，
## 长句换行后条子跟着变高，否则第二行会溢出条外压到卡面上（实测 44 字那条就这样）。
func _fit_sub_bar() -> void:
	var text_h: float = _sub.get_combined_minimum_size().y
	var h: float = clampf(text_h + 22.0, 52.0, 128.0)
	_bar.offset_bottom = _bar.offset_top + h


## 解说条避让：菜单与图鉴放屏幕下缘（不压标题），局内放上缘（不压手牌）
func _sub_at_top(on_top: bool) -> void:
	if on_top:
		_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_bar.offset_left = -390
		_bar.offset_right = 390
		_bar.offset_top = 86
		_bar.offset_bottom = 138
	else:
		_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_bar.offset_left = -450
		_bar.offset_right = 450
		_bar.offset_top = -150
		_bar.offset_bottom = -98

## 章节卡。cut_out = true 时这张卡不淡出，画面留在卡上等下一张——两张都是纯文字卡时
## 这样切换是硬切：底下的深色底一直是满不透明，只换字，中间不会漏出游戏画面。
func _card(title: String, sub: String, hold := 2.2, cut_out := false) -> void:
	var seamless := _chapter_root.visible and _chapter_root.modulate.a > 0.99
	if _chapter_tween and _chapter_tween.is_valid():
		_chapter_tween.kill()
	_chapter_title.text = title
	_chapter_sub.text = sub
	_chapter_root.visible = true
	if not seamless:
		_chapter_root.modulate.a = 0.0
		_chapter_tween = create_tween()
		_chapter_tween.tween_property(_chapter_root, "modulate:a", 1.0, 0.40)
	await _wait(hold)
	if cut_out:
		_chapter_root.modulate.a = 1.0
		return
	_chapter_tween = create_tween()
	_chapter_tween.tween_property(_chapter_root, "modulate:a", 0.0, 0.40)
	await _wait(0.45)
	_chapter_root.visible = false

# ---------------- 驱动 main ----------------

## 图鉴往下翻一屏，停在彩蛋那张（最后一行那颗格子）还在视口下面的位置。
## 原来的写法是滚到 4000（等于滚到底），最后一行会露出来，也就是那张灰底「？」。
## 卡本身留在图鉴里，只是演示的镜头不翻到那儿去。
func _scroll_knowledge_one_screen() -> void:
	var sc: ScrollContainer = main.knowledge_scroll
	if sc == null or main.knowledge_grid == null:
		return
	var ids: Array = Knowledge.all_ids()
	var views: Array = main.knowledge_grid.get_children()
	for i in mini(ids.size(), views.size()):
		if str(ids[i]) != "egg_dixinhu":
			continue
		# 视口坐标差 + 当前滚动量 = 这张格子在滚动内容里的纵向位置（不受缩放动画影响）
		var egg_y: float = views[i].get_global_transform().origin.y - sc.get_global_transform().origin.y + float(sc.scroll_vertical)
		var one_screen: float = float(sc.scroll_vertical) + sc.size.y - 40.0
		var stop: float = maxf(minf(one_screen, egg_y - sc.size.y), float(sc.scroll_vertical))
		var tw := create_tween()
		tw.tween_property(sc, "scroll_vertical", stop, 2.2)
		return


## 彩蛋卡有 0.5% 的随机掉率（GameState.DIXINHU_RANDOM_CHANCE），录片时万一掉出来就是直接点名。
## 每次点弹窗之前把队列里的它摘掉，宁可这一回合不出知识卡。
func _scrub_egg() -> void:
	var q: Array = GameState.pending_knowledge
	for i in range(q.size() - 1, -1, -1):
		if str(q[i]) == "egg_dixinhu":
			q.remove_at(i)


func _dismiss_any() -> bool:
	_scrub_egg()
	if main.crisis_root != null and main.crisis_root.visible:
		main._on_crisis_dismiss()
		return true
	if main.popup_root != null and main.popup_root.visible:
		main._on_popup_button()
		main._on_popup_button()
		return true
	return false

func _dismiss_all(max_times := 8) -> void:
	for i in max_times:
		if not _dismiss_any():
			break
		await _wait(0.42)

func _wait_popup(timeout := 12.0) -> bool:
	var t := 0.0
	while t < timeout:
		if (main.popup_root != null and main.popup_root.visible) or (main.crisis_root != null and main.crisis_root.visible):
			return true
		await _wait(0.15)
		t += 0.15
	return false

func _wait_allocate(timeout := 30.0) -> bool:
	var t := 0.0
	while t < timeout:
		await _dismiss_all(6)
		if main._current_phase == "allocate" and main.hand_panel != null and main.hand_panel.visible:
			await _wait(0.5)
			return true
		await _wait(0.3)
		t += 0.3
	push_warning("demo: allocate timeout")
	return false

func _stage(idx: int) -> void:
	var infos: Array = main.card_infos
	if idx < 0 or idx >= infos.size():
		return
	var info: Dictionary = infos[idx]
	if info.get("selected", false):
		return
	info["selected"] = true
	info["tier"] = main.play_tier
	info["staged_by_drag"] = true
	info["stage_order"] = main._next_stage_order()
	info["stage_zone"] = "board"
	info["preview_left"] = 0.0
	main._apply_gold_frame(info["panel"])
	main._update_card_face(info)
	main._layout_fan(true)
	main._update_selected_label()
	main.play_sfx("land", 1.1, -12.0)

func _execute() -> void:
	main._finish_turn()
	await _wait_popup(22.0)

# ---------------- 段落 ----------------

## 片内时间轴：片头卡亮起算 0 秒。每段开头 _sync_to(N) 把段落起点压回目标时间，
## 操作本身的耗时波动靠它吸收，不会一段一段往下漂。
var _demo_t0 := 0.0
var _clock := 0.0

## 片内时钟用累加的 delta，而不是墙钟：--write-movie --fixed-fps 30 时引擎全速跑，
## 墙钟 200 秒会对应 344 秒逻辑时间，两者混用会把片长拉长近一倍。
func _process(delta: float) -> void:
	_clock += delta

func _sync_to(target: float) -> void:
	if _time_scale < 1.0 or _demo_t0 <= 0.0:
		return
	var elapsed := _clock - _demo_t0
	var d := target - elapsed
	if d > 0.05:
		await _wait(d)
	elif d < -0.6:
		print("[demo] late %.2fs (target %.2f, elapsed %.2f)" % [-d, target, elapsed])

func _run() -> void:
	await _wait(0.4)
	_demo_t0 = _clock
	if not _skip_intro:
		await _card("鄱阳归翎 · 生态修复手记", "鄱阳湖。候鸟的家园。现在，也交到了你手上。", 4.2)
		await _menu_part()
		await _knowledge_part()
	else:
		_demo_t0 = _clock - 41.0
	await _start_part()
	await _board_part()
	await _first_turn_part()
	await _deck_part()
	await _more_turns_part()
	await _board_close_part()
	await _outro_part()

func _menu_part() -> void:
	print("[demo] part _menu_part t=", Time.get_ticks_msec()/1000.0, " frame=", Engine.get_process_frames())
	await _sync_to(6.0)
	await _say("丰茂的水草，成群的候鸟。这片湿地，值得年年归来。", 5.0)
	await _sync_to(12.0)
	await _say("但守护不会自动发生。站长，现在由你接手：十六个回合，跨越四年。", 6.0)
	await _sync_to(19.0)
	await _say("孩子和家长，都能在这里接受挑战：预算有限，如何取舍？", 4.2)
	_mute_sub()
	await _wait(0.3)

func _knowledge_part() -> void:
	print("[demo] part _knowledge_part t=", Time.get_ticks_msec()/1000.0, " frame=", Engine.get_process_frames())
	await _sync_to(24.0)
	main._open_knowledge_viewer()
	await _wait(0.7)
	await _say("退耕还湿，增殖放流，禁渔巡护。", 2.5)
	await _say("你的行动卡，取材于真实的保护行动。现在，把它们付诸实践。", 3.9)
	await _sync_to(33.0)
	await _scroll_knowledge_one_screen()
	await _wait(0.5)
	await _say("认识这里的物种，了解它们的栖息地。", 3.0)
	await _say("每张知识卡，都有实拍照片与说明。收藏跨局保留，你对这片湖的了解也是。", 5.0)
	main._close_knowledge_viewer()
	await _wait(0.6)
	_mute_sub()

func _start_part() -> void:
	print("[demo] part _start_part t=", Time.get_ticks_msec()/1000.0, " frame=", Engine.get_process_frames())
	await _sync_to(41.0)
	main._on_title_start()
	await _wait(0.9)
	await _sync_to(42.0)
	await _say("四档难度，逐级收紧的生态红线。站长，请根据经验，选择你的挑战。", 5.2)
	main._on_difficulty_pick(NORMAL)
	await _sync_to(49.0)
	main.seed_input.text = "20261018"
	await _wait(0.5)
	await _say("同一个种子，同一局起点。想知道另一种选择的结果？再来一次，亲自验证。", 4.6)
	main._on_start_pressed()
	await _wait(1.6)
	await _sync_to(55.5)
	if main.popup_root != null and main.popup_root.visible:
		await _say("开局随机零到三条天赋。新条件已经就位，轮到你调整方案。", 5.0)
		await _dismiss_all(4)
	await _wait_allocate()
	_mute_sub()

func _board_part() -> void:
	print("[demo] part _board_part t=", Time.get_ticks_msec()/1000.0, " frame=", Engine.get_process_frames())
	await _sync_to(62.0)
	_sub_at_top(true)
	await _say("左边，查看资金与季节。右边，六项生态监测。站长，请掌握全局。", 5.2)
	await _sync_to(68.0)
	await _say("候鸟、水草、房屋，随指标增减。你的决策，正在改变眼前的湖。", 3.6)
	await _sync_to(72.0)
	await _say("水位不会直接判负。可旱与涝的代价，一笔也不会少。", 3.6)
	_mute_sub()
	await _wait(0.3)

func _first_turn_part() -> void:
	print("[demo] part _first_turn_part t=", Time.get_ticks_msec()/1000.0, " frame=", Engine.get_process_frames())
	await _sync_to(76.0)
	await _say("七张手牌，等待部署。拖入待执行区，选择投入档位。", 3.2)
	_stage(0)
	await _wait(0.85)
	_stage(2)
	await _wait(0.85)
	_stage(4)
	await _wait(0.6)
	await _say("请记住：你的决心，可以很大；预算，只有这么多。", 3.0)
	await _wait(0.4)
	await _sync_to(85.0)
	await _execute()
	await _say("执行。逐张结算。牌加成、协同、演化、危机——每一笔变化，都有来源可查。", 4.6)
	await _sync_to(93.0)
	if main.popup_root != null and main.popup_root.visible:
		await _say("看清变化，查明原因。下一次出牌，你就多一分把握。", 3.4)
		await _dismiss_all(4)
	await _sync_to(98.0)
	if main.popup_root != null and main.popup_root.visible:
		await _say("达成特定组合，解锁知识卡。行动之后，再认识一位湖中的邻居。", 2.6)
		await _dismiss_all(4)
	await _wait_allocate()
	_mute_sub()

func _more_turns_part() -> void:
	print("[demo] part _more_turns_part t=", Time.get_ticks_msec()/1000.0, " frame=", Engine.get_process_frames())
	await _sync_to(133.0)
	await _say("警报响起，并不意味着一切已经来不及。危机先预警，再在下一回合爆发。", 4.2)
	main.score_speed = 3.0
	for round_i in 3:
		if main._current_phase != "allocate":
			await _wait_allocate()
		var picks: Array = [0, 1, 3] if round_i % 2 == 0 else [0, 2, 5]
		for p in picks:
			_stage(p)
			await _wait(0.3)
		await _wait(0.3)
		await _execute()
		if round_i == 0:
			await _say("趁后果到来之前，调整你的部署。", 2.4)
		if round_i == 1:
			await _say("资金该花在哪里？哪项指标必须优先照顾？站长，接下来这几轮，让你的选择回答。", 5.2)
		if main.popup_root != null and main.popup_root.visible:
			await _dismiss_all(4)
		await _wait(0.45)
		await _wait_allocate()
	main.score_speed = 1.0
	_mute_sub()

## 牌库与卡牌厚度。2026-10-19 第二次调整：从原来的「技术段」整体前移到
## 「知识卡弹窗」之后、「危机快剪」之前，开完这里就关掉牌库回到局内。
func _deck_part() -> void:
	print("[demo] part _deck_part t=", Time.get_ticks_msec()/1000.0, " frame=", Engine.get_process_frames())
	await _sync_to(101.0)
	await _say("五十五张行动卡，四十一张知识卡。", 3.0)
	# 上一段如果残留了「牌库已开」的状态，_open_deck_viewer 会直接 return，画面就不换。
	if main._deck_open:
		main._close_deck_viewer()
		await _wait(0.3)
	main._open_deck_viewer()
	await _wait(0.6)
	await _wait(1.4)
	await _say("牌库、手牌与知识卡，共用一套卡面绘制。数量增加，视觉依然统一，每一张都清晰就位。", 5.6)
	var view: Control = null
	if main.deck_viewer_grid.get_child_count() > 1:
		view = main.deck_viewer_grid.get_child(1)
	if view != null:
		main._show_card_detail(view, view.get_meta("card"))
	await _wait(1.6)
	_sub_at_top(false)
	await _say("移动鼠标，倾斜卡面。透视随之变化，投影跟着移动。", 3.6)
	var big: Control = main._detail_big_card
	var t := 0.0
	while t < 10.0:
		if big != null and is_instance_valid(big):
			var a: float = sin(t * 1.15) * 0.30
			var b: float = sin(t * 0.83 + 1.1) * 0.26
			main._step_card_gyro(big, Vector2(a, b), 0.05)
		await get_tree().process_frame
		t += get_process_delta_time()
	await _say("卡牌的厚度与立体感，都在二维画布里完成，文字依然清晰。", 4.4)
	main._close_card_detail()
	await _wait(0.6)
	main._close_deck_viewer()
	_sub_at_top(true)
	await _wait(0.4)
	_mute_sub()

## 局内沙盘与手牌同框。原来挂在技术段末尾，现在单独成段，接在危机快剪之后，
## 说完就硬接收尾卡——中间那段只有通关才播的短片按用户要求去掉了。
func _board_close_part() -> void:
	print("[demo] part _board_close_part t=", Time.get_ticks_msec()/1000.0, " frame=", Engine.get_process_frames())
	await _sync_to(170.0)
	_sub_at_top(true)
	await _say("三维沙盘，二维卡牌。同一帧画面里，行动与结果相遇。", 5.0)
	_mute_sub()
	await _wait(0.3)

func _outro_part() -> void:
	print("[demo] part _outro_part t=", Time.get_ticks_msec()/1000.0, " frame=", Engine.get_process_frames())
	await _sync_to(176.0)
	await _card("鄱阳归翎 · 生态修复手记", "候鸟即将归来。站长，轮到你出牌了。鄱阳归翎，等待你的选择。", 3.4, true)
	await _card("谢谢观看", "16 回合 / 四季 / 6 项指标 / 55 张行动卡 / 41 张知识卡", 2.4, true)
