package battleship

Error :: enum {
  NONE,
  OUT_OF_RANGE,
  ON_TOP_OF_ANOTHER_SHIP,
  INCORRECT_INPUT,
  SHIP_IS_ALREADY_PLACED,
  TILE_HAD_BEEN_HITTED_BEFORE,
  UNKNOWN_COMMAND,
}

// Symbols
WATER :: rune('≈') // Empty water
SHIP  :: rune('S') // Ship
HIT   :: rune('H') // Hit
MISS  :: rune('M') // Miss
SUNK  :: rune('X') // Sunk

Players :: enum {None, Player1, Player2}

GamePhase :: enum {None, Placing_Ships, Battle, GameOver}

InputStep :: enum {
	None,
  SelectShip,
  SelectTile,
  SelectX,
  SelectY,
  SelectOrientation,
}

GameState :: struct {
  winner: Players,
  turn: int,
  current_player: Players, // current player turn
  phase: GamePhase,

  input_step: InputStep,
  buffer: [dynamic]string,

  // Game Log
  log: [dynamic]string,
}

CheckWinner :: proc(p1, p2: Player) {
  if (len(p1.ships) == 0) {game.winner = .Player2;}
  else if (len(p2.ships) == 0) {game.winner = .Player1;}
}

Ships :: enum {
  Carrier,
  Battleship,
  Cruiser,
  Submarine,
  Destroyer,
}

Position :: struct {
  x,y: int
}

Ship :: struct {
  length: int,
  sunk: bool,

  // If len(tiles) == 0 -> ship.sunk = true
  tiles:     map[int]Position, // stores ship tiles and when tile is hit remove it from the map and replace the tile to HIT
  old_tiles: map[int]Position, // stores old tiles pos so when ship is sunk set HIT tiles to SUNK
}

Player :: struct {
  target_grid: [10][10]rune,
  ocean_grid:  [10][10]rune,

  unplaced_ships: map[Ships]int,
  ships: map[Ships]Ship,
}

CreatePlayer :: proc() -> Player {
  p: Player;

  for &i in p.ocean_grid {
    for &j in i {j = WATER;}
  }

  for &i in p.target_grid {
    for &j in i {j = WATER;}
  }

  p.unplaced_ships[.Carrier]     = 0;
  p.unplaced_ships[.Battleship]  = 1;
  p.unplaced_ships[.Cruiser]     = 2;
  p.unplaced_ships[.Submarine]   = 3;
  p.unplaced_ships[.Destroyer]   = 4;

  p.ships[.Carrier]     = {length = 5, sunk = false}
  p.ships[.Battleship]  = {length = 4, sunk = false}
  p.ships[.Cruiser]     = {length = 3, sunk = false}
  p.ships[.Submarine]   = {length = 3, sunk = false}
  p.ships[.Destroyer]   = {length = 2, sunk = false}

  return p;
}

// Fix this later
// Contains :: proc(list: []$T, target: T) -> bool {
//   for item in list {
//     if (item == target) {return true;}
//   }
//   return false;
// }

StoreTilesInShip :: proc(tiles, old_tiles: ^map[int]Position, index: int, pos: Position) {
  tiles[index] = pos;
  old_tiles[index] = pos;
}

// The Ship is `int` cause it will be from the player input
PlaceShip :: proc(p: ^Player, ship, x, y: int, rotation: string) -> Error {
  type: Ships;
  switch ship {
    case 0: type = .Carrier;
    case 1: type = .Battleship;
    case 2: type = .Cruiser;
    case 3: type = .Submarine;
    case 4: type = .Destroyer;
    case: return .INCORRECT_INPUT;
  }

  length := p.ships[type].length;

  // If ship is already placed show this error
  // if (!Contains(p.unplaced_ships[:], ship)) {return .SHIP_IS_ALREADY_PLACED;}

  // Here just choose the way to place the ship
  if (rotation == "H" || rotation == "h") {
    if (x + length > 10) {return .OUT_OF_RANGE;}

    for i in 0..<length {
      if (p.ocean_grid[y][x+i] == SHIP) {return .ON_TOP_OF_ANOTHER_SHIP;}
    }

    for i in 0..<length {
      p.ocean_grid[y][x+i] = SHIP;
      _ship := &p.ships[type]
      StoreTilesInShip(&_ship.tiles, &_ship.old_tiles, i, {x+i,y});
    }
  }
  else if (rotation == "V" || rotation == "v") {
    if (y + length > 10) {return .OUT_OF_RANGE;}

    for i in 0..<length {
      if (p.ocean_grid[y+i][x] == SHIP) {return .ON_TOP_OF_ANOTHER_SHIP;}
    }

    for i in 0..<length {
      p.ocean_grid[y+i][x] = SHIP;
      _ship := &p.ships[type]
      StoreTilesInShip(&_ship.tiles, &_ship.old_tiles, i, {x,y+i});
    }
  }
  else {
    return .INCORRECT_INPUT;
  }

  delete_key(&p.unplaced_ships, type);

  return .NONE;
}

// Checks the hitted tile is from what ship and apply damage to it
ApplyDamageToShip :: proc(p, sP: ^Player, x,y: int) {
  tile_pos := Position{x,y};

  for ship_key, &ship in p.ships {
    for tile_index, t_pos in ship.tiles {
      if (tile_pos == t_pos) {
        delete_key(&ship.tiles, tile_index);
        if (len(ship.tiles) == 0) {
          ship.sunk = true;
        }
      }
    }
    // Set SUNK
    if (len(ship.tiles) == 0 && ship.sunk == true) {
      for _,_tile in ship.old_tiles {
        p.ocean_grid[_tile.y][_tile.x] = SUNK;
        sP.target_grid[_tile.y][_tile.x] = SUNK;
      }
      append(&game.log, "A ship has been sunk!");
      delete_key(&p.ships, ship_key);
    }

  }
}

// Sender Player and Reciver Player
// sP sends the rocket to rP grid
Hit :: proc(sP, rP: ^Player, x, y: int) -> Error {
  s_tile := &rP.ocean_grid[y][x]; // Sender Grid Tile
  t_tile := &sP.target_grid[y][x]; // Target Grid Tile

  if (x < 0 || x >= 10 || y < 0 || y >= 10) {return .OUT_OF_RANGE;}

  switch s_tile^ {
    case WATER: {
      s_tile^ = MISS;
      t_tile^ = MISS;
    }
    case SHIP: {
      s_tile^ = HIT;
      t_tile^ = HIT;

      ApplyDamageToShip(rP,sP, x,y);
      CheckWinner(sP^, rP^);
    }
    case HIT: {
      return .TILE_HAD_BEEN_HITTED_BEFORE;
    }
    case: {return .INCORRECT_INPUT;}
  }

  return .NONE;
}
