package battleship

import t "termcl"
import tb "termcl/term"

import "core:fmt"
import "core:time"
import "core:net"

ORANGE_COLOR :: t.Color_RGB{250, 160, 30}

game: GameState;

Page :: enum {MainMenu, RadminHostMenu, RadminJoinMenu, LocalHostMenu, LocalJoinMenu, Gameplay}

// Based on the mouse position and game phase it will either use the ocean_board or target_board
GetTilePosFromMouse :: proc(s: ^t.Screen, mouse: t.Mouse_Input) -> Position {
	if (mouse.key == .Left && .Pressed in mouse.event) {
		if (game.phase == .Placing_Ships) {
			// Check if the mouse is inside the ocean_grid and then get the tile pos to place the ship
			// first tile x:3, y:5
			// last tile x:21, y:14

			if (mouse.coord.x >= 3 && mouse.coord.x <= 21) {
				if (mouse.coord.y >= 5 && mouse.coord.y <= 14) {
					// Convert the pos from screen to tile pos, Example(3,5 -> 0,0)
					t_: Position = {int(mouse.coord.x) - 3, int(mouse.coord.y) - 5};
					if (t_.x % 2 == 1) {return {-1,-1}}
					if (t_.x >= 2) {t_.x = t_.x/2}

					return t_;
				}
			}

		}
		else if (game.phase == .Battle) {
			// Check if the mouse is inside the target_grid and then get the tile pos to hit
			// first tile x:40, y:5
			// last tile x:58, y:14

			if (mouse.coord.x >= 40 && mouse.coord.x <= 58) {
				if (mouse.coord.y >= 5 && mouse.coord.y <= 14) {
					// Convert the pos from screen to tile pos, Example(40,58 -> 0,0)
					t_: Position = {int(mouse.coord.x) - 40, int(mouse.coord.y) - 5};
					if (t_.x % 2 == 1) {return {-1,-1}}
					if (t_.x >= 2) {t_.x = t_.x/2}

					return t_;
				}
			}
		}
	}

	return {-1,-1};
}


main :: proc() {
	game.current_player = .Player1;

	page: Page = .MainMenu;

	p1 := CreatePlayer();
	p2 := CreatePlayer();

	s := t.init_screen(tb.VTABLE);
	defer t.destroy_screen(&s);

	t.set_term_mode(&s, .Raw);

	mouse_input: t.Mouse_Input;
	cursor_bg: t.Any_Color;

	selected_ship: Ships;

	for {
		t.hide_cursor(true)
		t.clear(&s, .Everything);
		defer t.blit(&s);

		raw_input, has_raw_input := tb.read_raw(&s);

		// input, input_ok := t.read(&s).(t.Keyboard_Input);
		input, input_ok := tb.parse_keyboard_input(raw_input);
		if (input_ok && input.key == .Escape) {break}


		m_input, mouse_has_input := tb.parse_mouse_input(raw_input);
		if (mouse_has_input) {mouse_input = m_input;}

		switch page {
			case .MainMenu: {
				InputMainMenu(&s, &page, mouse_input);
				DrawMainMenu(&s);
			}
			case .RadminHostMenu: {
				user_type = .Host;
				DrawRadminHostMenu(&s);
				t.blit(&s);
				UpdateRadminHostMenu(&page, &s);
			}
			case .RadminJoinMenu: {
				user_type = .Client;
				InputRadminJoinMenu(&s, &page, input_ok ? input.key : .None);
				DrawRadminJoinMenu(&s);
			}
			case .LocalHostMenu: {
				user_type = .Host;
				DrawLocalHostMenu(&s);
				t.blit(&s);
				UpdateLocalHostMenu(&page, &s);
			}
			case .LocalJoinMenu: {
				user_type = .Client;
				UpdateLocalJoinMenu(&s, &page);
				DrawLocalJoinMenu(&s);
			}
			case .Gameplay: {
				if (game.phase == .Battle) {
					if ((game.current_player == .Player1 && user_type == .Host) || (game.current_player == .Player2 && user_type == .Client)) {
						InputGameplay(&s, &p1,&p2, mouse_input, input_ok ? input.key : .None);
					}
				}
				else {
					InputGameplay(&s, &p1,&p2, mouse_input, input_ok ? input.key : .None);
				}

				UpdateNetworking(page, &p1,&p2);

				if (user_type == .Host) {DrawGameplay(p1, &s);}
				else {DrawGameplay(p2, &s);}
			}
		}

		if (mouse_input.key == .Left && .Pressed in mouse_input.event) {cursor_bg = nil;}
		else {cursor_bg = .White}

		t.set_color_style(&s, nil, cursor_bg);
		t.move_cursor(&s, mouse_input.coord.y, mouse_input.coord.x);
		t.write(&s, " ");

		t.reset_styles(&s);
	}
}

DrawMainMenu :: proc(s: ^t.Screen) {
	t.set_text_style(s, {.Bold});

	// Title
	t.set_color_style(s, ORANGE_COLOR, nil);
	t.move_cursor(s, 0, 0);
	t.write(s, "===B A T T L E S H I P===");

	// Host & Join Options
	t.set_color_style(s, .Blue, nil);
	t.move_cursor(s, 1, 0);
	t.write(s, "Radmin Host");

	t.set_color_style(s, .Cyan, nil);
	t.move_cursor(s, 2, 0);
	t.write(s, "Radmin Join");

	t.set_color_style(s, ORANGE_COLOR, nil);
	t.move_cursor(s, 3, 0);
	t.write(s, "Local Host");

	t.set_color_style(s, .Yellow, nil);
	t.move_cursor(s, 4, 0);
	t.write(s, "Local Join");

	t.reset_styles(s);
}

InputMainMenu :: proc(s: ^t.Screen, page: ^Page, mouse: t.Mouse_Input) {
	if (mouse.key == .Left && .Pressed in mouse.event) {
		if (mouse.coord.y == 1 && mouse.coord.x <= 10) {page^ = .RadminHostMenu;}
		if (mouse.coord.y == 2 && mouse.coord.x <= 10) {page^ = .RadminJoinMenu;}
		if (mouse.coord.y == 3 && mouse.coord.x <= 9) {page^ = .LocalHostMenu;}
		if (mouse.coord.y == 4 && mouse.coord.x <= 9) {page^ = .LocalJoinMenu;}
	}

	time.sleep(1000000);
}

host_key:string;
listener: net.TCP_Socket;
host_client_sock: net.TCP_Socket;

// Radmin Multiplayer
DrawRadminHostMenu :: proc(s: ^t.Screen) {
	t.set_text_style(s, {.Bold});

	// Title
	t.set_color_style(s, .Blue, nil);
	t.move_cursor(s, 0, 0);
	t.write(s, "===R A D M I N - H O S T - M E N U===");

	// Generate Join Key
	// Try to get the key for 5 times

	if (host_key == "") {
		for i in 0..<5 {
			ip := GetRadminVpnIp()
			endpoint = {ip, PORT};
			host_key = EncodeIP4(ip)
		}
	}

	t.set_color_style(s, .Green, nil);
	t.move_cursor(s, 1, 0);
	text := fmt.tprintf("Join Key: %v", host_key);
	t.write(s, text);

	t.reset_styles(s);
}
UpdateRadminHostMenu :: proc(page: ^Page, s: ^t.Screen) {
	if (listener == 0 && host_client_sock == 0) {
		listener, _ = net.listen_tcp(endpoint);
		net.set_blocking(listener, false);
	}

	sock, _,err := net.accept_tcp(listener);
	if (err == nil) {
		host_client_sock = sock;
		net.set_blocking(host_client_sock, false);

		// FOR TEST ONLY
		append(&game.log, "Host Is Connected!");
		page^ = .Gameplay;
	}
	time.sleep(1000000);
}

// Store each key character here and the ability to press backspace to remove last character
// either by setting it to 0
client_key_buffer: [8]u8;
client_key_pressed_num: int;
DrawRadminJoinMenu :: proc(s: ^t.Screen) {
	t.set_text_style(s, {.Bold});

	// Title
	t.set_color_style(s, .Cyan, nil);
	t.move_cursor(s, 0, 0);
	t.write(s, "===R A D M I N - J O I N - M E N U===");

	t.set_color_style(s, .Green, nil);
	t.move_cursor(s, 1, 0);
	text := fmt.tprintf("Enter Join Key: %v-%v-%v-%v",
		string(client_key_buffer[:2]), string(client_key_buffer[2:4]),
		string(client_key_buffer[4:6]), string(client_key_buffer[6:8]));
	t.write(s, text);

	t.reset_styles(s);
}
InputRadminJoinMenu :: proc(s: ^t.Screen, page: ^Page, key: Maybe(t.Key)) {
	k, ok := key.?;

	// Convert client_key_buffer to net.IP4_Address
	// Then try connect to the given address
	if (k == .Enter && client_key_pressed_num >= 8) {
		decoded_ip := DecodeIP4(string(client_key_buffer[:]));
		endpoint = {decoded_ip, PORT};

		t.clear(s, .Everything);
		t.move_cursor(s,0,0);
		t.write(s, "Connecting to host...");
		t.blit(s);

		sock, err := net.dial_tcp(endpoint);

		if (err == nil) {
			host_client_sock = sock;
			net.set_blocking(host_client_sock, false);
			// FOR TEST ONLY
			append(&game.log, "Client Is Connected!");
			page^ = .Gameplay;
		}
	}
	else if (k == .Backspace) { // Remove last written character
		if (client_key_pressed_num != 0) {
			client_key_buffer[client_key_pressed_num-1] = 0;
			client_key_pressed_num -= 1;
		}
	}

	// Adds the pressed key to client_key_buffer
	pressed_key, pressed := KeyToU8(k);

	if (pressed_key != 0 && client_key_pressed_num < 8) {
		client_key_buffer[client_key_pressed_num] = pressed_key;
		client_key_pressed_num += 1;
	}
	time.sleep(1000000);
}

// Local Multiplayer
DrawLocalHostMenu :: proc(s: ^t.Screen) {
	t.set_text_style(s, {.Bold});

	// Title
	t.set_color_style(s, ORANGE_COLOR, nil);
	t.move_cursor(s, 0, 0);
	t.write(s, "===L O C A L - H O S T - M E N U===");

	t.set_color_style(s, .Green, nil);
	t.move_cursor(s, 1, 0);
	t.write(s, "Waiting for client to join...");

	t.reset_styles(s);
}
UpdateLocalHostMenu :: proc(page: ^Page, s: ^t.Screen) {
	if (listener == 0 && host_client_sock == 0) {
		endpoint = {net.IP4_Any, PORT};
		listener, _ = net.listen_tcp(endpoint);
		net.set_blocking(listener, false);

		SpawnBroadcastBeacon();
	}

	sock, _,err := net.accept_tcp(listener);
	if (err == nil) {
		host_client_sock = sock;
		net.set_blocking(host_client_sock, false);

		// FOR TEST ONLY
		append(&game.log, "Host Is Connected!");
		page^ = .Gameplay;
	}
	time.sleep(1000000);
}

disc_sock_created: bool;
disc_sock: net.UDP_Socket;
disc_sock_err: net.Network_Error;
DrawLocalJoinMenu :: proc(s: ^t.Screen) {
	t.set_text_style(s, {.Bold});

	// Title
	t.set_color_style(s, .Yellow, nil);
	t.move_cursor(s, 0, 0);
	t.write(s, "===L O C A L - J O I N - M E N U===");

	t.set_color_style(s, .Green, nil);
	t.move_cursor(s, 1, 0);
	t.write(s, "Connecting to host...");

	t.reset_styles(s);
}
UpdateLocalJoinMenu :: proc(s: ^t.Screen, page: ^Page) {
	if (!disc_sock_created) {
		disc_sock, disc_sock_err = net.make_bound_udp_socket(net.IP4_Any, PORT_DISCOVERY);
		net.set_blocking(disc_sock, false);

		if (disc_sock_err == net.Create_Socket_Error.None || disc_sock_err == nil) {
			disc_sock_created = true;
		}
	}


	buf: [128]u8;
	n, remote_ep, recv_err := net.recv_udp(disc_sock, buf[:]);


	if (recv_err == nil && n > 0) {
		if (string(buf[:n]) == "BATTLESHIP_HOST_ALIVE") {
			host_ip := remote_ep.address.(net.IP4_Address);
			game_ep := net.Endpoint{address = host_ip, port = PORT};

			sock, dial_err := net.dial_tcp(game_ep);
			if (dial_err == nil) {
				host_client_sock = sock;
				net.set_blocking(host_client_sock, false);
				// FOR TEST ONLY
				append(&game.log, "Client Is Connected!");
				page^ = .Gameplay;
			}
		}
	}

	time.sleep(1000000);
}

Carrier_bg:    t.Any_Color;
Battleship_bg: t.Any_Color;
Cruiser_bg:    t.Any_Color;
Submarine_bg:  t.Any_Color;
Destroyer_bg:  t.Any_Color;

DrawGameplay :: proc(p: Player, s: ^t.Screen) {
	t.set_text_style(s, {.Bold})

	if (game.winner == .None) {
		// Draw Ocean Grid
		// Title
		t.set_color_style(s, ORANGE_COLOR, nil)
		t.move_cursor(s, 0, 18)
		t.write(s, "===B A T T L E S H I P===")

		// Ocean Grid Text
		t.set_color_style(s, .Cyan, nil)
		t.move_cursor(s, 2, 3)
		t.write(s, "═══Local Waters═══")

		// Grid border and numbers
		t.set_color_style(s, .White, nil)
		t.move_cursor(s, 3, 0)
		t.write(s, "╔══════════════════════╗")
		t.move_cursor(s, 4, 3)
		t.write(s, "₀ ₁ ₂ ₃ ₄ ₅ ₆ ₇ ₈ ₉")
		t.move_cursor(s, 15, 0)
		t.write(s, "╚══════════════════════╝")

		// Vertical Grid Numbers
		for i in 0 ..< 10 {
			t.move_cursor(s, uint(i + 5), 1)
			num := fmt.aprint(i)
			t.write(s, num)
		}

		// Tiles
		for row, i in p.ocean_grid {
			t.move_cursor(s, uint(i + 5), 3)

			for r, j in row {
				if (r == WATER) {t.set_color_style(s, .Blue, nil)}
				if (r == SHIP) {
					for pp, _ship in p.ships {
						switch pp {
							case .Carrier:
								for _, _pos in _ship.tiles {
									if (_pos == {j,i}) {
										t.set_color_style(s, .Red, nil)
									}
								}
							case .Battleship:
								for _, _pos in _ship.tiles {
									if (_pos == {j,i}) {
										t.set_color_style(s, .Green, nil)
									}
								}
							case .Cruiser:
								for _, _pos in _ship.tiles {
									if (_pos == {j,i}) {
										t.set_color_style(s, .Yellow, nil)
									}
								}
							case .Submarine:
								for _, _pos in _ship.tiles {
									if (_pos == {j,i}) {
										t.set_color_style(s, ORANGE_COLOR, nil)
									}
								}
							case .Destroyer:
								for _, _pos in _ship.tiles {
									if (_pos == {j,i}) {
										t.set_color_style(s, .Magenta, nil)
									}
								}
						}
					}

				}
				if (r == HIT)  {t.set_color_style(s, .Yellow, nil)}
				if (r == SUNK) {t.set_color_style(s, .Red, nil)}
				if (r == MISS) {t.set_color_style(s, .Magenta, nil)}

				t.write(s, r)
				t.write(s, ' ')
			}
		}

		// Seperater Line
		t.set_color_style(s, .White, nil)
		for i in 0 ..< 14 {
			t.move_cursor(s, 2 + uint(i), 30)
			t.write(s, '║')
		}

		// Draw Target Grid
		t.set_color_style(s, .Red, nil)
		t.move_cursor(s, 2, 40)
		t.write(s, "═══Enemy Waters═══")

		// Horizontal Grid border and numbers
		t.set_color_style(s, .White, nil)
		t.move_cursor(s, 3, 37)
		t.write(s, "╔══════════════════════╗")
		t.move_cursor(s, 4, 40)
		t.write(s, "₀ ₁ ₂ ₃ ₄ ₅ ₆ ₇ ₈ ₉")
		t.move_cursor(s, 15, 37)
		t.write(s, "╚══════════════════════╝")

		// Vertical Grid Numbers
		for i in 0 ..< 10 {
			t.move_cursor(s, uint(i + 5), 38)
			num := fmt.aprint(i)
			t.write(s, num)
		}

		// Tiles
		t.set_color_style(s, .Blue, nil)
		for row, i in p.target_grid {
			t.move_cursor(s, uint(i + 5), 40)

			for r, _ in row {
				if (r == WATER) {t.set_color_style(s, .Blue, nil)}
				if (r == HIT)  {t.set_color_style(s, .Yellow, nil)}
				if (r == SUNK) {t.set_color_style(s, .Red, nil)}
				if (r == MISS) {t.set_color_style(s, .Magenta, nil)}

				t.write(s, r)
				t.write(s, ' ')
			}
		}

		// Tiles explain
		t.set_color_style(s, .Yellow, nil)

		t.move_cursor(s, 7, 67)
		t.write(
			s,
			"╚═════════════════════════════════════╝",
		)

		t.set_color_style(s, .Blue, nil)
		t.move_cursor(s, 4, 72)
		t.write(s, "≈: Water")

		t.set_color_style(s, .Green, nil)
		t.move_cursor(s, 4, 84)
		t.write(s, "S: Ship")

		t.set_color_style(s, .Yellow, nil)
		t.move_cursor(s, 4, 95)
		t.write(s, "H: Hit")

		t.set_color_style(s, .Magenta, nil)
		t.move_cursor(s, 6, 76)
		t.write(s, "M: Miss")

		t.set_color_style(s, .Red, nil)
		t.move_cursor(s, 6, 90)
		t.write(s, "X: Sunk")

		t.set_color_style(s, .Yellow, nil)
		for i in 0 ..< 4 {
			t.move_cursor(s, 3 + uint(i), 67)
			t.write(s, '║')
			t.move_cursor(s, 3 + uint(i), 105)
			t.write(s, '║')
		}

		// Unplaced Ships
		if (len(p.unplaced_ships) != 0) {
			t.set_color_style(s, .White, nil)
			t.move_cursor(s, 17, 0)
			t.write(s, "Ships:")

			for _ship in p.unplaced_ships {
				switch _ship {
					case .Carrier: {
						t.set_color_style(s, .Red, Carrier_bg);
						t.move_cursor(s, 18, 0);
						t.writef(s, " %s (len: %i)", Ships.Carrier, p.ships[.Carrier].length);
					}
					case .Battleship: {
						t.set_color_style(s, .Green, Battleship_bg);
						t.move_cursor(s, 19, 0);
						t.writef(s, " %s (len: %i)", Ships.Battleship, p.ships[.Battleship].length);
					}
					case .Cruiser: {
						t.set_color_style(s, .Yellow, Cruiser_bg);
						t.move_cursor(s, 20, 0);
						t.writef(s, " %s (len: %i)", Ships.Cruiser, p.ships[.Cruiser].length);
					}
					case .Submarine: {
						t.set_color_style(s, ORANGE_COLOR, Submarine_bg);
						t.move_cursor(s, 21, 0);
						t.writef(s, " %s (len: %i)", Ships.Submarine, p.ships[.Submarine].length);
					}
					case .Destroyer: {
						t.set_color_style(s, .Magenta, Destroyer_bg);
						t.move_cursor(s, 22, 0);
						t.writef(s, " %s (len: %i)", Ships.Destroyer, p.ships[.Destroyer].length);
					}
				}
			}

		}

		// Turn number and Current Player Turn
		t.set_color_style(s, .Yellow, nil)
		t.move_cursor(s, 0, 67)
		t.write(
			s,
			"╔═════════════════════════════════════╗",
		)
		t.move_cursor(s, 3, 67)
		t.write(
			s,
			"║═════════════════════════════════════║",
		)

		for i: uint = 0; i < 2; i += 1 {
			t.move_cursor(s, 1 + i, 67)
			t.write(s, '║')
			t.move_cursor(s, 1 + i, 105)
			t.write(s, '║')
		}

		turn_text := fmt.aprintf("Turn: %i", game.turn)
		current_player_text := fmt.aprintf("Current Player: %v", game.current_player)

		t.set_color_style(s, .Blue, nil)
		t.move_cursor(s, 1, 83)
		t.write(s, turn_text)

		t.set_color_style(s, .Cyan, nil)
		t.move_cursor(s, 2, 75)
		t.write(s, current_player_text)

		// Place Ship Phase & Battle Phase
		if (game.phase == .Placing_Ships && len(p.unplaced_ships) != 0) {
			t.set_color_style(s, ORANGE_COLOR, nil);
			t.move_cursor(s, 24, 0);

			#partial switch game.input_step {
				case .SelectShip: t.write(s, "Select a Ship");
				case .SelectTile: t.write(s, "Select a Tile");
				case .SelectOrientation: t.write(s, "Select Ship Rotation(H-V):");
			}
		}
		else if (game.phase == .Battle && (user_type == .Host && game.current_player == .Player1) || (user_type == .Client && game.current_player == .Player2)) {
			t.set_color_style(s, ORANGE_COLOR, nil);
			t.move_cursor(s, 17, 0);
			t.write(s, "Target a tile to fire!")
		}

		// Game Log
		t.set_color_style(s, .Magenta, nil);
		t.move_cursor(s, 9, 82);
		t.write(s, "GAME LOG");
		t.move_cursor(s, 10, 67);
		t.write(s, "╔═════════════════════════════════════╗");
		t.move_cursor(s, 18, 67);
		t.write(s, "╚═════════════════════════════════════╝");

		for i in 1..<8 {
			t.move_cursor(s, 10 + uint(i), 67);
			t.write(s, "║");
			t.move_cursor(s, 10 + uint(i), 105);
			t.write(s, "║");
		}

		// Write last 7 logs in the game log box
		start_index := max(0, len(game.log) - 7);
		for m,i in game.log[start_index:] {
			t.move_cursor(s, 11 + uint(i), 69);
			t.write(s, m);
		}
	}
	else { // Winner Window
		t.clear(s, .Everything);
		t.set_color_style(s, .Green, nil);
		t.move_cursor(s,0,0);
		_text: string = fmt.aprintf("Winner Player: %v", game.winner);
		t.write(s, _text);
		t.blit(s);
	}


	t.reset_styles(s)
}

InputGameplay :: proc(s: ^t.Screen, p1,p2: ^Player, mouse: t.Mouse_Input, key: Maybe(t.Key)) {
	if (len(p1.unplaced_ships) != 0 && game.phase != .Placing_Ships) {
		game.phase = .Placing_Ships;
		game.input_step = .SelectShip;
	}

	if (game.phase == .Placing_Ships) {
		if (len(p1.unplaced_ships) == 0 && len(p2.unplaced_ships) == 0) {
			game.phase = .Battle;
		}

		t_pos := GetTilePosFromMouse(s, mouse);

		k, ok := key.?;

		val := KeyToString(k);

		#partial switch game.input_step {
			case .SelectShip:
				if (mouse.key == .Left && .Pressed in mouse.event) {
					switch mouse.coord.y {
						case 18:
							append(&game.buffer, fmt.tprint(0));
							game.input_step = .SelectTile;
							Carrier_bg = .White;
						case 19:
							append(&game.buffer, fmt.tprint(1));
							game.input_step = .SelectTile;
							Battleship_bg = .White;
						case 20:
							append(&game.buffer, fmt.tprint(2));
							game.input_step = .SelectTile;
							Cruiser_bg = .White;
						case 21:
							append(&game.buffer, fmt.tprint(3));
							game.input_step = .SelectTile;
							Submarine_bg = .White;
						case 22:
							append(&game.buffer, fmt.tprint(4));
							game.input_step = .SelectTile;
							Destroyer_bg = .White;
					}
				}

				if (mouse.key == .Left && .Pressed in mouse.event || val != "") {
					if (len(p1.unplaced_ships) != 0 && user_type == .Client && len(p2.unplaced_ships) == 0) {
						append(&game.log, "Player1 is still placeing his ships.");
						game.input_step = .None;
					}
					else if (len(p2.unplaced_ships) != 0 && user_type == .Host && len(p1.unplaced_ships) == 0) {
						append(&game.log, "Player2 is still placeing his ships.");
						game.input_step = .None;
					}
				}
			case .SelectTile:
				if (t_pos != {-1,-1}) {
					append(&game.buffer, fmt.tprint(t_pos.x));
					append(&game.buffer, fmt.tprint(t_pos.y));

					game.input_step = .SelectOrientation;
				}
			case .SelectOrientation:
				if (val != "") {
					append(&game.buffer, val);
				}

				// Create & Execute Command
				if (len(game.buffer) == 4) {
					com := CreateCommand(game.buffer);
					if (user_type == .Host) {
						err := ExecuteCommand(com, p1,p2, 1);
						if (err != .NONE) {
							append(&game.log, fmt.aprint(err));
							Carrier_bg = nil;
							Battleship_bg = nil;
							Cruiser_bg = nil;
							Submarine_bg = nil;
							Destroyer_bg = nil;
						}
						else if (err == .NONE || err == nil) {
							HostClientSendCommand(game.buffer);
						}
						game.input_step = .SelectShip;
					}
					else {
						err := ExecuteCommand(com, p1,p2, 2);
						if (err != .NONE) {
							append(&game.log, fmt.aprint(err));
							Carrier_bg = nil;
							Battleship_bg = nil;
							Cruiser_bg = nil;
							Submarine_bg = nil;
							Destroyer_bg = nil;
						}
						else if (err == .NONE || err == nil) {
							HostClientSendCommand(game.buffer);
						}
						game.input_step = .SelectShip;
					}

					clear(&game.buffer);
				}

				if (len(p1.unplaced_ships) == 0 && len(p2.unplaced_ships) == 0) {
					game.phase = .Battle;
				}
		}

	}
	else if (game.phase == .Battle) {
		t_pos := GetTilePosFromMouse(s, mouse);

		if (t_pos != {-1,-1}) {
			append(&game.buffer, fmt.tprint(t_pos.x));
			append(&game.buffer, fmt.tprint(t_pos.y));

			// Create & Execute Command
			com := CreateCommand(game.buffer);
			if (user_type == .Host) {
				err := ExecuteCommand(com, p1,p2, 1);
				if (err != .NONE) {
					append(&game.log, fmt.aprint(err));
				}
				else if (err == .NONE || err == nil) {
					HostClientSendCommand(game.buffer);
				}
			}
			else {
				err := ExecuteCommand(com, p1,p2, 2);
				if (err != .NONE) {
					append(&game.log, fmt.aprint(err));
				}
				else if (err == .NONE || err == nil) {
					HostClientSendCommand(game.buffer);
				}
			}

			clear(&game.buffer);
		}

	}
}

KeyToString :: proc(key: t.Key) -> string {

	#partial switch key {
		case .Num_0: return "0"
		case .Num_1: return "1"
		case .Num_2: return "2"
		case .Num_3: return "3"
		case .Num_4: return "4"
		case .Num_5: return "5"
		case .Num_6: return "6"
		case .Num_7: return "7"
		case .Num_8: return "8"
		case .Num_9: return "9"

		case .H: return "h"
		case .V: return "v"
		case: return ""
	}

	return "";
}
// Returns the key pressed and one if the key is pressed
KeyToU8 :: proc(key: t.Key) -> (u8, int) {
	#partial switch key {
		case .Num_1: return '1', 1
		case .Num_2: return '2', 1
		case .Num_3: return '3', 1
		case .Num_4: return '4', 1
		case .Num_5: return '5', 1
		case .Num_6: return '6', 1
		case .Num_7: return '7', 1
		case .Num_8: return '8', 1
		case .Num_9: return '9', 1
		case .Num_0: return '0', 1
		case .A: return 'a', 1
		case .B: return 'b', 1
		case .C: return 'c', 1
		case .D: return 'd', 1
		case .E: return 'e', 1
		case .F: return 'f', 1
		case .G: return 'g', 1
		case .H: return 'h', 1
		case .I: return 'i', 1
		case .J: return 'j', 1
		case .K: return 'k', 1
		case .L: return 'l', 1
		case .M: return 'm', 1
		case .N: return 'n', 1
		case .O: return 'o', 1
		case .P: return 'p', 1
		case .Q: return 'q', 1
		case .R: return 'r', 1
		case .S: return 's', 1
		case .T: return 't', 1
		case .U: return 'u', 1
		case .V: return 'v', 1
		case .W: return 'w', 1
		case .X: return 'x', 1
		case .Y: return 'y', 1
		case .Z: return 'z', 1
	}
	return 0,0;
}
