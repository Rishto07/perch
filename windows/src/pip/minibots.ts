// Mini Pips (pills + compact grid) ΓÇö port of MiniBotCanvasView.
// Each canvas owns a BotEngine; the island's frame loop ticks every live one.

import { BotEngine, hexToRGB } from "./engine";
import { Sound } from "../core/sound";
import type { AgentTask } from "../core/state";

interface MiniBot {
  canvas: HTMLCanvasElement;
  engine: BotEngine;
  cssSize: number;
  taskId: string;
  slot: HTMLElement;
  hovered: boolean;
  clicks: number[];
  lastState: string;
}

const live = new Map<HTMLCanvasElement, MiniBot>();

// Flock ripple: when Pip herself gets excited, minis wake up staggered.
let flockBoost = 0;
export function setFlockBoost(v: number) {
  flockBoost = Math.max(0, Math.min(1, v));
}

// Elite mini-birds: track the real cursor across the island window.
const mouse = { x: -9999, y: -9999, active: false };
let mouseHooked = false;

function hookMouse() {
  if (mouseHooked) return;
  mouseHooked = true;
  window.addEventListener(
    "mousemove",
    (e) => {
      mouse.x = e.clientX;
      mouse.y = e.clientY;
      mouse.active = true;
    },
    { passive: true },
  );
  window.addEventListener(
    "mouseleave",
    () => {
      mouse.active = false;
    },
    { passive: true },
  );
}

/**
 * Creates a mini Pip whose **body** is `bodySize` CSS pixels across.
 *
 * The engine draws the body at 60 % of its canvas, so the canvas is
 * `bodySize / 0.6` and is centred in a `bodySize` slot, overflowing it ΓÇö the
 * same thing SwiftUI does with a `.frame(width: 22/0.6)` inside a
 * `.frame(width: 22)`. Sizing the canvas itself to `bodySize` would shrink the
 * whole drawing to 60 %, which is what used to happen.
 */
export function createMiniBot(task: AgentTask, bodySize: number): HTMLElement {
  const slot = document.createElement("span");
  slot.className = "mini";
  slot.style.width = `${bodySize}px`;
  slot.style.height = `${bodySize}px`;

  const canvas = document.createElement("canvas");
  const engineSize = bodySize / 0.6;
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  canvas.width = Math.round(engineSize * dpr);
  canvas.height = Math.round(engineSize * dpr);
  canvas.style.width = `${engineSize}px`;
  canvas.style.height = `${engineSize}px`;
  slot.append(canvas);

  const engine = new BotEngine();
  engine.isMini = true;
  engine.shape = "bird";
  engine.bodyColor = hexToRGB(task.color);
  engine.setState(task.state, true);
  if (task.emote) engine.setPermanentEmote(task.emote);
  if (task.miniEye) {
    engine.permanentEye = task.miniEye;
    engine.eyeOverride = task.miniEye;
    engine.eyeOverrideUntil = Number.POSITIVE_INFINITY;
  }

  hookMouse();
  // Hover: excitement burst + happy eyes (silent — the pill's click blip is
  // the one sound per action; see Sound.play throttle).
  slot.addEventListener("mouseenter", () => {
    const mb = live.get(canvas);
    if (mb) mb.hovered = true;
    engine.exciteBurst();
  });
  slot.addEventListener("mouseleave", () => {
    const mb = live.get(canvas);
    if (mb) mb.hovered = false;
    engine.exciteCalm();
  });
  slot.addEventListener("mousedown", () => {
    const mb = live.get(canvas);
    engine.poke();
    // Easter egg: 3 rapid pokes → dizzy spin, like Pip's slap.
    if (mb) {
      const t = performance.now() / 1000;
      mb.clicks = mb.clicks.filter((s) => t - s < 1.7);
      mb.clicks.push(t);
      if (mb.clicks.length >= 3) {
        mb.clicks = [];
        engine.doRoll(1300, 2);
        engine.eyeOverride = "spiral";
        engine.eyeOverrideUntil = t + 1.5;
        Sound.play("dizzy");
      }
    }
    // No stopPropagation: the island's own mousedown must still see the click
    // so lastActivity updates and the island stays open.
  });

  slot.title = `${task.name} — ${task.state} · double-click to open`;
  // Hatch-in: new birds pop in excited with a little hop.
  engine.exciteBurst();
  live.set(canvas, { canvas, engine, cssSize: engineSize, taskId: task.id, slot, hovered: false, clicks: [], lastState: task.state });
  return slot;
}

export function releaseMiniBot(canvas: HTMLCanvasElement) {
  live.delete(canvas);
}

/** Drops every canvas no longer in the document (views are rebuilt wholesale). */
export function pruneMiniBots() {
  for (const [canvas] of live) {
    if (!canvas.isConnected) live.delete(canvas);
  }
}

export function syncMiniBotStates(tasks: AgentTask[]) {
  for (const mb of live.values()) {
    const task = tasks.find((t) => t.id === mb.taskId);
    if (!task) continue;
    // Celebration: when an agent finishes, its bird does a happy jump.
    if (task.state === "finished" && mb.lastState !== "finished") {
      mb.engine.triggerEmote("happy");
      mb.engine.exciteBurst();
      Sound.play("finish");
    }
    mb.lastState = task.state;
    mb.engine.setState(task.state);
    mb.engine.bodyColor = hexToRGB(task.color);
    mb.slot.title = `${task.name} — ${task.state}${task.steps.length > 1 ? ` · ${task.stepIndex + 1}/${task.steps.length}` : ""} · double-click to open`;
  }
}

export function tickMiniBots(dt: number) {
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  for (const mb of live.values()) {
    const ctx = mb.canvas.getContext("2d");
    if (!ctx) continue;
    // Cursor-follow: eyes and head chase the mouse; proximity builds excitement.
    if (mouse.active) {
      const r = mb.canvas.getBoundingClientRect();
      const cx = r.left + r.width / 2;
      const cy = r.top + r.height / 2;
      const dx = mouse.x - cx;
      const dy = mouse.y - cy;
      mb.engine.lookX = Math.tanh(dx / 180);
      mb.engine.lookY = -Math.tanh(dy / 140);
      mb.engine.lastCursor = performance.now() / 1000;
      const dist = Math.hypot(dx, dy);
      const prox = Math.max(0, Math.min(1, 1 - dist / 260));
      // Flock ripple + proximity: near birds wake up with Pip.
      const flock = Math.max(0, Math.min(1, flockBoost * prox * 1.4));
      mb.engine.exciteTarget = mb.hovered ? 1 : Math.max(prox * 0.7, flock);
    } else if (!mb.hovered) {
      mb.engine.exciteTarget = 0;
    }
    mb.engine.update(dt);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, mb.cssSize, mb.cssSize);
    mb.engine.draw(ctx, mb.cssSize, mb.cssSize);
  }
}

export const miniBotCount = () => live.size;
