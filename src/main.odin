package battleship

import t "termcl"
import tb "termcl/term"

import "core:fmt"
import "core:time"
import "core:net"

// Make it when you run the game in windows it runs on PowerShell instead of CMD

/*
	Each user in code sees him self as p1 and the other user as p2, ONLY IN CODE
	in screen aka current_turn the host will be Player1 and the client will be Player2
*/

ORANGE_COLOR :: t.Color_RGB{250, 160, 30}

game: GameState;

Page :: enum {MainMenu, HostMenu, JoinMenu, Gameplay}

main :: proc() {
	game.current_player = .Player1;

	page: Page = .MainMenu;

	p1 := CreatePlayer();
	p2 := CreatePlayer();

	s := t.init_screen(tb.VTABLE);
	defer t.destroy_screen(&s);

	t.set_term_mode(&s, .Cbreak);

	for {
		t.hide_cursor(true)
		t.clear(&s, .Everything);
		defer t.blit(&s);

		input, input_ok := t.read(&s).(t.Keyboard_Input);
		if (input_ok && input.key == .Escape) {break}

		switch page {
			case .MainMenu: {
				InputMainMenu(&s, &page, input_ok ? input.key : .None);
				DrawMainMenu(&s);
			}
			case .HostMenu: {
				user_type = .Host;
				DrawHostMenu(&s);
				t.blit(&s);
				UpdateHostMenu(&page, &s);
			}
			case .JoinMenu: {
				user_type = .Client;
				InputJoinMenu(&s, &page, input_ok ? input.key : .None);
				DrawJoinMenu(&s);
			}
			case .Gameplay: {
				if (game.phase == .Battle) {
					if ((game.current_player == .Player1 && user_type == .Host) || (game.current_player == .Player2 && user_type == .Client)) {
						InputGameplay(&s, &p1,&p2, input_ok ? input.key : .None);
					}
				}
				else {
					InputGameplay(&s, &p1,&p2, input_ok ? input.key : .None);
				}

				UpdateNetworking(page, &p1,&p2);

				if (user_type == .Host) {DrawGameplay(p1, &s);}
				else {DrawGameplay(p2, &s);}
			}
		}
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
	t.write(s, "1: Host");

	t.set_color_style(s, .Cyan, nil);
	t.move_cursor(s, 2, 0);
	t.write(s, "2: Join");

	t.reset_styles(s);
}
InputMainMenu :: proc(s: ^t.Screen, page: ^Page, key: Maybe(t.Key)) {
	k, ok := key.?;

	if (key == .Num_1) {page^ = .HostMenu}
	if (key == .Num_2) {page^ = .JoinMenu}
	time.sleep(1000000);
}

host_key:string;
listener: net.TCP_Socket;
host_client_sock: net.TCP_Socket;
DrawHostMenu :: proc(s: ^t.Screen) {
	t.set_text_style(s, {.Bold});

	// Title
	t.set_color_style(s, .Blue, nil);
	t.move_cursor(s, 0, 0);
	t.write(s, "===H O S T - M E N U===");

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
UpdateHostMenu :: proc(page: ^Page, s: ^t.Screen) {
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
DrawJoinMenu :: proc(s: ^t.Screen) {
	t.set_text_style(s, {.Bold});

	// Title
	t.set_color_style(s, .Cyan, nil);
	t.move_cursor(s, 0, 0);
	t.write(s, "===J O I N - M E N U===");

	t.set_color_style(s, .Green, nil);
	t.move_cursor(s, 0, 0);
	text := fmt.tprintf("Enter Join Key: %v-%v-%v-%v",
		string(client_key_buffer[:2]), string(client_key_buffer[2:4]),
		string(client_key_buffer[4:6]), string(client_key_buffer[6:8]));
	t.write(s, text);

	t.reset_styles(s);
}
InputJoinMenu :: proc(s: ^t.Screen, page: ^Page, key: Maybe(t.Key)) {
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

			for r, _ in row {
				if (r == WATER) {t.set_color_style(s, .Blue, nil)}
				if (r == SHIP) {t.set_color_style(s, .Green, nil)}
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
			t.set_color_style(s, .Green, nil)
			t.move_cursor(s, 17, 0)
			t.write(s, "Ships:")

			ship_names := [Ships]cstring {
				.Carrier    = "Carrier",
				.Battleship = "Battleship",
				.Cruiser    = "Cruiser",
				.Submarine  = "Submarine",
				.Destroyer  = "Destroyer",
			}

			_line: uint = 18
			for ship_type, i in p.unplaced_ships {
				t.move_cursor(s, _line, 0)
				text := fmt.aprintf(
					"%i: %s (len: %i)",
					i,
					ship_names[ship_type],
					p.ships[ship_type].length,
				)
				t.write(s, text)
				_line += 1
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
				case .SelectShip: t.write(s, "Select a Ship(0-4):");
				case .SelectX: t.write(s, "Select X Position(0-9):");
				case .SelectY: t.write(s, "Select Y Position(0-9):");
				case .SelectOrientation: t.write(s, "Select Ship Rotation(H-V):");
			}
		}
		else if (game.phase == .Battle && (user_type == .Host && game.current_player == .Player1) || (user_type == .Client && game.current_player == .Player2)) {
			t.set_color_style(s, ORANGE_COLOR, nil);
			t.move_cursor(s, 17, 0);
			t.write(s, "Enter Coordinates To Fire!")
			t.move_cursor(s, 18, 0);
			#partial switch game.input_step {
				case .SelectX: t.write(s, "Select X Position(0-9):");
				case .SelectY: t.write(s, "Select Y Position(0-9):");
			}
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
InputGameplay :: proc(s: ^t.Screen, p1,p2: ^Player, key: Maybe(t.Key)) {
	if (len(p1.unplaced_ships) != 0 && game.phase != .Placing_Ships) {
		game.phase = .Placing_Ships;
		game.input_step = .SelectShip;
	}

	if (game.phase == .Placing_Ships) {
		if (len(p1.unplaced_ships) == 0 && len(p2.unplaced_ships) == 0) {
			game.input_step = .SelectX;
			game.phase = .Battle;
		}

		k, ok := key.?;
		if !ok || game.phase != .Placing_Ships { return }

		val := KeyToString(k);
		if val == "" {return}

		if (len(p1.unplaced_ships) != 0 && user_type == .Client && len(p2.unplaced_ships) == 0) {
			append(&game.log, "Player1 is still placeing his ships.");
			return
		}
		else if (len(p2.unplaced_ships) != 0 && user_type == .Host && len(p1.unplaced_ships) == 0) {
			append(&game.log, "Player2 is still placeing his ships.");
			return
		}



		#partial switch game.input_step {
			case .SelectShip:
				append(&game.buffer, val);
				game.input_step = .SelectX;
			case .SelectX:
				append(&game.buffer, val);
				game.input_step = .SelectY;
			case .SelectY:
				append(&game.buffer, val);
				game.input_step = .SelectOrientation;
			case .SelectOrientation:
				append(&game.buffer, val);

				// Create & Execute Command
				if (len(game.buffer) == 4) {
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
					game.input_step = .SelectX;
					clear(&game.buffer);
				}

				if (len(p1.unplaced_ships) == 0 && len(p2.unplaced_ships) == 0) {
					game.phase = .Battle;
				}
				else {
					game.input_step = .SelectX;
					game.input_step = .SelectShip;
				}
		}

	}
	else if (game.phase == .Battle) {
		k, ok := key.?;
		if !ok || game.phase != .Battle { return }

		val := KeyToString(k);
		if val == "" {return}

		#partial switch game.input_step {
			case .SelectX:
				append(&game.buffer, val);
				game.input_step = .SelectY;
			case .SelectY:
				append(&game.buffer, val);

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

				game.input_step = .SelectX;
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
