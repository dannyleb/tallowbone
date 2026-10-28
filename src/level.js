import { TILE } from "./config.js";

// Levels are ASCII maps, one character per tile (see levels/canal.js for
// the legend). Markers for things that aren't tiles (spawns, lamps,
// signs, pickups) are pulled out at load and their cells become air.
const SOLID = new Set(["#", "V"]);
const ENEMY_MARKS = { c: "communicant", h: "hound" };
const PICKUP_MARKS = { v: "vial", b: "bullets" };

export function parseLevel(def) {
  const tiles = def.map.map((row) => row.split(""));
  const h = tiles.length, w = tiles[0].length;
  const spawns = { player: null, enemies: [], lamps: [], signs: [], pickups: [] };

  for (let r = 0; r < h; r++) {
    if (tiles[r].length !== w) throw new Error(`${def.name}: row ${r} is ${tiles[r].length} wide, not ${w}`);
    for (let c = 0; c < w; c++) {
      const ch = tiles[r][c];
      // Markers sit in the cell just above the floor; x is the cell's
      // centre, y its bottom edge (where feet go).
      const x = (c + 0.5) * TILE, y = (r + 1) * TILE;
      if (ch === "P") spawns.player = { x, y };
      else if (ch === "L") spawns.lamps.push({ x, y, lit: false, id: spawns.lamps.length });
      else if (ENEMY_MARKS[ch]) spawns.enemies.push({ type: ENEMY_MARKS[ch], x, y, gorged: 0 });
      else if (PICKUP_MARKS[ch]) spawns.pickups.push({ kind: PICKUP_MARKS[ch], x, y, taken: false });
      else if (ch >= "1" && ch <= "9") spawns.signs.push({ x, y, text: def.signs[ch] });
      else continue;
      tiles[r][c] = ".";
    }
  }
  if (!spawns.player) throw new Error(`${def.name}: no player spawn (P)`);

  const at = (c, r) => (c < 0 || c >= w || r >= h ? "#" : r < 0 ? "." : tiles[r][c]);

  // Cells with stone somewhere above them are indoors or underground: they
  // get a back wall instead of the sky. Worked out once, from the map as
  // authored (burning a veil doesn't let the sky in).
  const roof = tiles.map(() => new Array(w).fill(false));
  for (let c = 0; c < w; c++) {
    let covered = false;
    for (let r = 0; r < h; r++) {
      roof[r][c] = covered;
      if (SOLID.has(tiles[r][c])) covered = true;
    }
  }

  return {
    name: def.name, w, h, tiles, spawns,
    pxW: w * TILE, pxH: h * TILE,
    at,
    solid: (c, r) => SOLID.has(at(c, r)),
    oneWay: (c, r) => at(c, r) === "=",
    hazard: (c, r) => at(c, r) === "~",
    roofed: (c, r) => r >= 0 && r < h && c >= 0 && c < w && roof[r][c],
    // Burns any veil touching the rect, and the rest of that veil with it
    // (the fire spreads through connected veil tiles). Returns the burnt
    // cells.
    burn(rect) {
      const out = [], todo = [];
      for (let r = Math.floor(rect.y / TILE); r <= Math.floor((rect.y + rect.h) / TILE); r++)
        for (let c = Math.floor(rect.x / TILE); c <= Math.floor((rect.x + rect.w) / TILE); c++) todo.push([c, r]);
      while (todo.length) {
        const [c, r] = todo.pop();
        if (at(c, r) !== "V") continue;
        tiles[r][c] = ".";
        out.push({ c, r });
        todo.push([c + 1, r], [c - 1, r], [c, r + 1], [c, r - 1]);
      }
      return out;
    },
  };
}
