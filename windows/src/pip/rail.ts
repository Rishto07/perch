// The agent rail — one perched bird per agent Pip is watching.
//
// The old mini bots gave each agent its own BotEngine canvas and the island's
// frame loop ticked all of them at 60 fps. A token is one SVG glyph whose
// state is a CSS animation, so the rail costs the frame loop nothing and
// never clones Pip's face.
//
// The glyph is drawn in the Pip mark's language — crown spike, oval eye,
// beak, teardrop body, legs on the rail — so every agent reads as a Perch
// bird, not a generic icon.

import { svg } from "../views/dom";
import { ICONS } from "../views/icons";
import type { AgentTask } from "../core/state";

export interface TokenOptions {
  /** Bird width in CSS px. Defaults to 24 (overview). */
  size?: number;
  /** Name shown under the rail. Omit for the compact rail. */
  label?: string;
  /** Focus this agent when the token is clicked. */
  onSelect?: () => void;
}

// Hand-drawn perched bird paths (24 × 24 design box). One closed silhouette,
// one wing vane, one eye dot, and the legs that grip the rail.
const BODY =
  "M12.5 5.2C14 4.2 15.5 4.2 16.6 4.6L19.2 0.7 19.9 5C19.9 6 20.7 6.8 20.7 7.6" +
  "C21.5 8.6 22.2 9.2 23 9.7 21.8 10.6 20.6 10.9 19.8 11" +
  "C18.5 12.5 17.8 13.8 16.5 15 14.5 17.5 12.8 18.5 11 18.6" +
  "C8.5 18.9 7.2 18.6 6 18.2 4.8 17.2 4.2 16 3.9 14.6" +
  "C5.5 13 6.2 12.5 7 12 8.5 10.5 9.5 9 10.5 8 11 6.5 11.5 5.8 12.5 5.2Z";
const WING =
  "M9.2 10.2C11.5 9.4 14 10 15.2 11.2 15.6 13 15.4 14.8 14.6 15.8" +
  "C12.5 17 10.5 17.2 9 16.4 7.6 14.5 7.8 11.5 9.2 10.2Z";
const LEGS = "M11 18.3 11 21.2M14.2 18.5 14.2 21.2M10 21.2 12 21.2M13.2 21.2 15.2 21.2";

function perchedBird(): SVGSVGElement {
  const el = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  el.setAttribute("viewBox", "0 0 24 24");
  el.setAttribute("aria-hidden", "true");
  el.classList.add("bird");
  el.innerHTML =
    `<path class="legs" d="${LEGS}"/>` +
    `<path class="body" d="${BODY}"/>` +
    `<path class="wing" d="${WING}"/>` +
    `<ellipse class="eye" cx="17.2" cy="7" rx="1.25" ry="1.25"/>`;
  return el;
}

interface BadgeStyle {
  color: string;
  icon: string;
  stroke: number;
}

const BADGES: Record<NonNullable<AgentTask["pillBadge"]>, BadgeStyle> = {
  approval: { color: "#F5A524", icon: ICONS.bang, stroke: 0 },
  finished: { color: "#22C55E", icon: ICONS.check, stroke: 3 },
  error: { color: "#F4505E", icon: ICONS.xmark, stroke: 0 },
};

function paintBadge(el: HTMLElement, badge: NonNullable<AgentTask["pillBadge"]>) {
  const style = BADGES[badge];
  const inner = el.firstElementChild as HTMLElement;
  inner.style.background = style.color;
  inner.replaceChildren(svg(style.icon, 6, { stroke: style.stroke }));
  el.style.boxShadow = `0 0 4px ${style.color}99`;
}

/** Builds one token. Call `syncToken` whenever the task changes. */
export function createToken(task: AgentTask, opts: TokenOptions = {}): HTMLElement {
  const el = document.createElement("div");
  el.className = "token";
  el.dataset.id = task.id;
  el.title = opts.label ?? task.name;

  const glyph = perchedBird();
  const size = opts.size ?? 24;
  glyph.style.width = `${size}px`;
  glyph.style.height = `${size}px`;
  el.append(glyph);

  if (opts.label) {
    const label = document.createElement("span");
    label.className = "lbl";
    label.textContent = opts.label;
    el.append(label);
  }

  if (opts.onSelect) el.addEventListener("click", opts.onSelect);

  syncToken(el, task);
  return el;
}

/** Pushes state, colour and badge onto an existing token. */
export function syncToken(el: HTMLElement, task: AgentTask) {
  el.dataset.state = task.state;
  el.style.color = task.color;
  el.dataset.badge = task.pillBadge ?? "";

  let badge = el.querySelector<HTMLElement>(":scope > .token-badge");
  if (!task.pillBadge) {
    badge?.remove();
    return;
  }
  if (!badge) {
    badge = document.createElement("span");
    badge.className = "token-badge";
    badge.append(document.createElement("i"));
    el.append(badge);
  }
  paintBadge(badge, task.pillBadge);
}
