extends TestCase
## Loads the real main scene, so a script error anywhere in the game fails the suite.


func test_main_scene_shows_the_menu_then_plays_solo() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await wait(0.2)
	var session: Session = main.get_node("Session")
	var menu: Menu = main.get_node("Menu")
	check(session.world == null and menu.visible, "starts on the menu")
	check(menu._front.visible and not menu._lobby.visible, "menu shows the front page, not the lobby")
	check(session.host("Tester", 24690) == OK, "can host")
	check(menu._lobby.visible and not menu._front.visible and menu._start.visible, "hosting shows the lobby with a start button")
	session.leave()
	check(menu._front.visible and not menu._lobby.visible, "leaving returns to the front page")
	session.play_solo("Tester")
	await wait(1.0)
	check(session.world != null and session.world.game.phase == Match.Phase.SETUP, "solo match is running")
	check(not main.get_node("Menu").visible and main.get_node("Hud").visible, "menu gives way to the HUD")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
