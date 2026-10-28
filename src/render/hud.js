import { STATS, VIEW } from "../config.js";
import { lastDevice } from "../controls.js";
import { levelCost } from "../game.js";
import { currentForm } from "../player.js";
import { ARMS } from "../arms.js";
import { C, FONT, FONT_NUM, FONT_SC } from "./palette.js";

// Everything drawn over the scene, in view units (0..viewW, 0..360).

const KEY = {
  keyboard: { interact: "E", confirm: "Enter", back: "Esc" },
  gamepad: { interact: "D-pad ↑", confirm: "A", back: "B" },
};
const keyName = (k) => KEY[lastDevice][k];

export function drawHud(ctx, game, viewW) {
  const p = game.player;
  const H = VIEW.height;

  // Health: oxblood, with the pale rally stretch after it.
  const per = 1.5, bw = p.maxHp * per, x = 14, y = 14;
  ctx.fillStyle = "rgba(0, 0, 0, 0.55)";
  ctx.fillRect(x - 2, y - 2, bw + 4, 11);
  ctx.fillStyle = C.blood;
  ctx.fillRect(x, y, Math.max(0, p.hp) * per, 7);
  ctx.fillStyle = C.bloodBright;
  ctx.fillRect(x, y, Math.max(0, p.hp) * per, 2);
  if (p.rally > 0) {
    ctx.fillStyle = C.rally;
    ctx.globalAlpha = p.rallyHold > 0 ? 0.85 : 0.55 + 0.25 * Math.sin(game.time * 14);
    ctx.fillRect(x + p.hp * per, y, p.rally * per, 7);
    ctx.globalAlpha = 1;
  }
  ctx.strokeStyle = C.boneDim;
  ctx.lineWidth = 0.75;
  ctx.strokeRect(x - 2, y - 2, bw + 4, 11);

  // Vials and bullets.
  ctx.font = `11px ${FONT_NUM}`;
  ctx.textBaseline = "middle";
  let ix = x;
  ctx.fillStyle = C.bloodBright;
  ctx.beginPath(); ctx.ellipse(ix + 4, y + 22, 3.5, 4.5, 0, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = C.bone;
  ctx.fillRect(ix + 3, y + 15, 2, 3);
  ctx.fillText(`${p.vials}`, ix + 11, y + 22);
  ix += 32;
  ctx.fillStyle = "#c9a34a";
  ctx.fillRect(ix + 2, y + 18, 3, 8);
  ctx.beginPath(); ctx.arc(ix + 3.5, y + 18, 1.5, Math.PI, 0); ctx.fill();
  ctx.fillStyle = p.bullets ? C.bone : C.bloodBright;
  ctx.fillText(`${p.bullets}`, ix + 10, y + 22);

  // The weapon and its current form.
  ctx.font = `10px ${FONT_SC}`;
  ctx.fillStyle = C.boneDim;
  ctx.fillText(`${ARMS[p.arm].name}  ·  ${currentForm(p).label}`, x, y + 38);

  // Tallow, bottom right.
  ctx.textAlign = "right";
  ctx.font = `16px ${FONT_NUM}`;
  ctx.fillStyle = C.tallow;
  ctx.fillText(`${game.tallow}`, viewW - 16, H - 20);
  if (game.gained) {
    ctx.globalAlpha = 1 - game.gained.t / 1.6;
    ctx.font = `11px ${FONT_NUM}`;
    ctx.fillText(`+${game.gained.amount}`, viewW - 16, H - 38 - game.gained.t * 8);
    ctx.globalAlpha = 1;
  }
  ctx.font = `9px ${FONT_SC}`;
  ctx.fillStyle = C.boneDim;
  ctx.fillText("tallow", viewW - 16, H - 8);
  ctx.textAlign = "left";

  if (game.prompt && !game.menu) {
    const px = game.prompt.x - game.cam.x, py = game.prompt.y - game.cam.y;
    pill(ctx, `${keyName("interact")}  ${game.prompt.text}`, px, py);
  }
  if (game.sign && !game.menu) signBox(ctx, game.sign.text, viewW, H);
  if (game.fx.notice) notice(ctx, game.fx.notice, viewW);
  if (game.fx.banner) banner(ctx, game.fx.banner, viewW, H);
  if (game.menu) menu(ctx, game, viewW, H);
}

function pill(ctx, text, cx, cy) {
  ctx.font = `10px ${FONT}`;
  const w = ctx.measureText(text).width + 14;
  ctx.fillStyle = "rgba(10, 9, 14, 0.75)";
  ctx.fillRect(cx - w / 2, cy - 8, w, 16);
  ctx.strokeStyle = C.boneDim;
  ctx.lineWidth = 0.5;
  ctx.strokeRect(cx - w / 2, cy - 8, w, 16);
  ctx.fillStyle = C.bone;
  ctx.textAlign = "center";
  ctx.fillText(text, cx, cy + 0.5);
  ctx.textAlign = "left";
}

function wrap(ctx, text, maxW) {
  const lines = [];
  for (const para of text.split("  ")) {
    let line = "";
    for (const word of para.split(" ")) {
      const next = line ? `${line} ${word}` : word;
      if (ctx.measureText(next).width > maxW && line) { lines.push(line); line = word; }
      else line = next;
    }
    lines.push(line);
  }
  return lines;
}

function signBox(ctx, text, viewW, H) {
  ctx.font = `12px ${FONT}`;
  const w = Math.min(viewW - 40, 440), lines = wrap(ctx, text, w - 28);
  const h = lines.length * 16 + 18, x = (viewW - w) / 2, y = H - h - 34;
  ctx.fillStyle = "rgba(14, 12, 16, 0.88)";
  ctx.fillRect(x, y, w, h);
  ctx.strokeStyle = "rgba(232, 223, 207, 0.35)";
  ctx.lineWidth = 0.75;
  ctx.strokeRect(x + 3, y + 3, w - 6, h - 6);
  ctx.fillStyle = C.bone;
  ctx.textBaseline = "middle";
  lines.forEach((l, i) => ctx.fillText(l, x + 14, y + 17 + i * 16));
}

function notice(ctx, n, viewW) {
  const a = Math.min(1, n.t * 3, (n.dur - n.t) * 2);
  ctx.globalAlpha = Math.max(0, a);
  ctx.font = `italic 12px ${FONT}`;
  ctx.fillStyle = C.bone;
  ctx.textAlign = "center";
  ctx.fillText(n.text, viewW / 2, 64);
  ctx.textAlign = "left";
  ctx.globalAlpha = 1;
}

const TONES = { death: "#b3262a", lamp: "#ffcf7a", tallow: "#f0bd62", pale: "#e8dfcf" };

function banner(ctx, b, viewW, H) {
  const a = Math.max(0, Math.min(1, b.t * 2.5, (b.dur - b.t) * 1.5));
  const y = H * 0.4;
  // A dark band behind the words.
  const g = ctx.createLinearGradient(0, y - 34, 0, y + 34);
  g.addColorStop(0, "rgba(0, 0, 0, 0)");
  g.addColorStop(0.5, `rgba(0, 0, 0, ${0.55 * a})`);
  g.addColorStop(1, "rgba(0, 0, 0, 0)");
  ctx.fillStyle = g;
  ctx.fillRect(0, y - 34, viewW, 68);
  ctx.globalAlpha = a;
  ctx.textAlign = "center";
  ctx.font = `${b.tone === "death" ? 30 : 24}px ${FONT_SC}`;
  ctx.fillStyle = TONES[b.tone] || C.bone;
  ctx.fillText(b.text.split("").join(String.fromCharCode(8202)), viewW / 2, y);
  if (b.sub) {
    ctx.font = `italic 12px ${FONT}`;
    ctx.fillStyle = C.bone;
    ctx.fillText(b.sub, viewW / 2, y + 22);
  }
  ctx.textAlign = "left";
  ctx.globalAlpha = 1;
}

function menu(ctx, game, viewW, H) {
  const w = 260, h = 168, x = (viewW - w) / 2, y = (H - h) / 2 + 10;
  ctx.fillStyle = "rgba(10, 9, 13, 0.92)";
  ctx.fillRect(x, y, w, h);
  ctx.strokeStyle = "rgba(255, 207, 122, 0.45)";
  ctx.lineWidth = 0.75;
  ctx.strokeRect(x + 4, y + 4, w - 8, h - 8);

  const cost = levelCost(game), afford = game.tallow >= cost;
  ctx.textBaseline = "middle";
  ctx.font = `15px ${FONT_SC}`;
  ctx.fillStyle = C.lamp;
  ctx.fillText("The lamp burns", x + 18, y + 22);
  ctx.font = `9px ${FONT_NUM}`;
  ctx.fillStyle = C.boneDim;
  ctx.fillText(`Level ${game.levelNo}   ·   next ${cost} tallow`, x + 18, y + 40);
  ctx.textAlign = "right";
  ctx.font = `13px ${FONT_NUM}`;
  ctx.fillStyle = C.tallow;
  ctx.fillText(`${game.tallow}`, x + w - 18, y + 22);
  ctx.textAlign = "left";

  const rows = [...STATS.map((s) => ({ label: s.label, n: game.stats[s.id], note: s.note, buy: true })), { label: "Leave", note: "" }];
  rows.forEach((r, i) => {
    const ry = y + 62 + i * 22, sel = i === game.menu.index;
    if (sel) {
      ctx.fillStyle = "rgba(255, 207, 122, 0.12)";
      ctx.fillRect(x + 10, ry - 9, w - 20, 18);
    }
    ctx.font = `12px ${FONT}`;
    ctx.fillStyle = r.buy && !afford ? "rgba(232, 223, 207, 0.4)" : sel ? C.lamp : C.bone;
    const label = `${sel ? "›" : " "} ${r.label}`;
    ctx.fillText(label, x + 16, ry);
    if (r.buy) {
      const lw = ctx.measureText(label).width;
      ctx.font = `10px ${FONT_NUM}`;
      ctx.fillText(`${r.n}`, x + 22 + lw, ry + 0.5);
    }
    ctx.font = `italic 10px ${FONT}`;
    ctx.fillStyle = C.boneDim;
    ctx.textAlign = "right";
    ctx.fillText(r.note, x + w - 16, ry);
    ctx.textAlign = "left";
  });
  ctx.font = `9px ${FONT}`;
  ctx.fillStyle = C.boneDim;
  ctx.fillText(`${keyName("confirm")} choose   ·   ${keyName("back")} leave`, x + 18, y + h - 12);
}
