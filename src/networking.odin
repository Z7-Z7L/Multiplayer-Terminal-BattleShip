package battleship

import "core:fmt"
import "core:net"
import "core:strconv"
import "core:strings"
import "core:time"

PlaceShipCommand :: struct {
  ship_type: int, // 0-4
  x,y: int,
  rotation: string
}

HitCommand :: struct {
  x,y: int,
}

Command :: union {
	PlaceShipCommand,
	HitCommand,
}

// From the terminal input create a command
CreateCommand :: proc(input: [dynamic]string) -> Command{
	com: Command;

	if (game.phase == .Placing_Ships) {
		c: PlaceShipCommand;
		// Set PlaceShipCommand variables
		c.ship_type = strconv.atoi(input[0]);
		c.x         = strconv.atoi(input[1]);
		c.y         = strconv.atoi(input[2]);
		c.rotation  = input[3];

		com = c;
	}
	else if (game.phase == .Battle) {
		c: HitCommand;
		// Set HitCommand variables
		c.x = strconv.atoi(input[0]);
		c.y = strconv.atoi(input[1]);

		com = c;
	}

	return com;
}

// input_player: is the player that will exectute the command
ExecuteCommand :: proc(com: Command, p1,p2: ^Player, input_player: int) -> Error {
	switch c in com {
		case PlaceShipCommand:
			if (input_player == 1) {
				return PlaceShip(p1, c.ship_type, c.x, c.y, c.rotation);
			}
			else if (input_player == 2) {
				return PlaceShip(p2, c.ship_type, c.x, c.y, c.rotation);
			}
		case HitCommand:
			if (input_player == 1) {
				err := Hit(p1,p2, c.x, c.y);
				if (err == .NONE || err == nil) {
					game.turn += 1;
					game.current_player = .Player2;
				}
				else {return err}


			}
			else if (input_player == 2) {
				err := Hit(p2,p1, c.x, c.y);
				if (err == .NONE || err == nil) {
					game.turn += 1;
					game.current_player = .Player1;
				}
				else {return err}

			}

		case:
			return .UNKNOWN_COMMAND;
	}
	return .NONE;
}

PORT :: 8080;
endpoint: net.Endpoint;

GetRadminVpnIp :: proc() -> net.IP4_Address{
	ip: net.IP4_Address;

	interfaces, err := net.enumerate_interfaces();
	defer net.destroy_interfaces(interfaces);
	if err != nil {
		fmt.eprintln(err);
		return {};
	}

	for iface in interfaces {
		if (strings.contains(iface.friendly_name, "Radmin")) {
			for lease in iface.unicast {
				if ip4, ok := lease.address.(net.IP4_Address); ok && ip4[0] == 26 {
					return ip4;
				}
			}
		}
	}

	return {};
}

EncodeIP4 :: proc(ip: net.IP4_Address) -> string {
 k: [4]string;

 for a, i in ip {
 	k[i] = fmt.tprintf("%x", a);
 }

 key := strings.join(k[:], "-")
 return key;
}

DecodeIP4 :: proc(key: string) -> net.IP4_Address {
	ip: net.IP4_Address;

	list: [8]rune;
	for s,i in key {
		list[i] = s;
	}

	key_str := fmt.tprintf("%v%v-%v%v-%v%v-%v%v",
		list[0],list[1],list[2],list[3],list[4],list[5],list[6],list[7]);
	k := strings.split(key_str, "-");
	for s,i in k {
		num, ok := strconv.parse_int(s, 16);
		if ok {
			ip[i] = u8(num);
		}
	}

	return ip;
}

HostClientSendCommand :: proc(input: [dynamic]string) {
	// Listens for client/host and then take it command and run it
	inp := strings.join(input[:], "|");
	msg := transmute([]byte)inp;
	net.send_tcp(host_client_sock, msg);
}

UserType :: enum {Host, Client}
user_type: UserType = nil;

// Recives the sent data from the Host/Client and then run it as a command
UpdateNetworking :: proc(page: Page, p1,p2:^Player) {
	input:[dynamic]string;

	buf: [1024]byte;
	bytes_read, err := net.recv_tcp(host_client_sock, buf[:]);

	if (bytes_read > 0) {
		msg_byte := buf[:bytes_read];
		msg := string(msg_byte);
		str_input := strings.split(msg, "|");

		for i in str_input {
			append(&input, i);
		}
	}
	else {
		time.sleep(1000000);
	}

	if (len(input) != 0) {
		if (user_type == .Host) {
			com := CreateCommand(input);
			ExecuteCommand(com, p1,p2, 2);
			clear(&input);
		}
		else if (user_type == .Client) {
			com := CreateCommand(input);
			ExecuteCommand(com, p1,p2, 1);
			clear(&input);
		}
	}

}
