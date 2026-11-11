class_name Menu
extends CanvasLayer
## The only menu: play solo, host, or join, then a lobby where the host starts the match.

var session: Session:
	set(value):
		session = value
		session.members_changed.connect(_refresh)
		session.ended.connect(func(reason: String) -> void: show_message(reason))
		_refresh()

var _name := LineEdit.new()
var _address := LineEdit.new()
var _status := Label.new()
var _front := VBoxContainer.new()   # solo / host / join
var _lobby := VBoxContainer.new()   # player list / switch / start / leave
var _members := Label.new()
var _start: Button


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 360
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.text = "SWAT 2v2"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	column.add_child(title)
	column.add_child(_front)
	column.add_child(_lobby)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)

	_name.text = "Player"
	_name.placeholder_text = "Your name"
	_name.max_length = 16
	_front.add_child(_name)
	_front.add_child(_button("Play solo with bots", func() -> void: session.play_solo(_name.text)))
	_front.add_child(_button("Host a game", _on_host))
	_address.text = "127.0.0.1"
	_address.placeholder_text = "Host IP address"
	_front.add_child(_address)
	_front.add_child(_button("Join", _on_join))

	_lobby.add_child(_members)
	_lobby.add_child(_button("Switch team", func() -> void: session.switch_roster()))
	_start = _button("Start match", func() -> void: session.start_match())
	_lobby.add_child(_start)
	_lobby.add_child(_button("Leave", func() -> void: session.leave()))
	_refresh()


func show_message(text: String) -> void:
	_status.text = text
	_refresh()


func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(pressed)
	return button


func _on_host() -> void:
	var error := session.host(_name.text)
	show_message("Hosting on port %d. Others join with your IP address." % Session.PORT if error == OK
			else "Could not host (is port %d already in use?)." % Session.PORT)


func _on_join() -> void:
	var error := session.join(_address.text.strip_edges(), _name.text)
	show_message("Connecting to %s..." % _address.text if error == OK else "That address did not work.")


func _refresh() -> void:
	var in_lobby := session != null and session.in_lobby()
	_front.visible = not in_lobby
	_lobby.visible = in_lobby
	if not in_lobby or _start == null:
		return
	_start.visible = session.is_host()
	var lines: Array[String] = []
	for roster in 2:
		lines.append("Team %s (%s first)" % ["A" if roster == 0 else "B", Team.NAMES[roster]])
		for peer: int in session.members:
			var member: Dictionary = session.members[peer]
			if member.roster == roster:
				lines.append("    %s%s" % [member.name, "  (host)" if peer == 1 else ""])
	lines.append("\nEmpty slots are filled with bots.")
	if in_lobby and not session.is_host():
		lines.append("Waiting for the host to start.")
	_members.text = "\n".join(lines)
