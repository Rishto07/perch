// Settings window — the place where anything that writes to disk is confirmed.
// Stage 2 covers the Claude Code hooks and the general preferences; API keys and
// integrations land here too in a later stage.

import "./settings.css";
import { Bridge, onEvent, type AgentStatus, type HookStatus, type ProviderInfo } from "../core/bridge";
import { DEFAULT_SETTINGS, type Settings } from "../core/state";
import { h, clear } from "../views/dom";

let settings: Settings = { ...DEFAULT_SETTINGS };
let version = "";

const root = document.getElementById("settings-root")!;

async function save() {
  await Bridge.saveSettings(settings);
}

// ── Reusable bits ─────────────────────────────────────────────────────────────

function toggle(on: boolean, onChange: (v: boolean) => void): HTMLElement {
  const el = h("button", { class: on ? "switch on" : "switch", "aria-pressed": on });
  el.addEventListener("click", () => {
    const next = !el.classList.contains("on");
    el.classList.toggle("on", next);
    onChange(next);
  });
  return el;
}

function statusDot(ok: boolean): HTMLElement {
  return h("i", { class: "dot", style: `background:${ok ? "#22c55e" : "#f4505e"}` });
}

function renderDiff(text: string): HTMLElement {
  const box = h("div", { class: "diff" });
  for (const line of text.split("\n")) {
    const cls = line.startsWith("+") ? "add" : line.startsWith("-") ? "del" : "ctx";
    box.append(h("div", { class: cls, text: line }));
  }
  return box;
}

// ── Claude Code section ───────────────────────────────────────────────────────

function claudeSection(status: HookStatus): HTMLElement {
  const body = h("div", { style: "display:flex;flex-direction:column;gap:12px" });
  const section = h(
    "section",
    {},
    h("h2", {}, statusDot(status.installed), h("span", { text: "Claude Code" })),
    body,
  );

  const rebuild = async () => {
    const fresh = await Bridge.hooksStatus();
    if (fresh) Object.assign(status, fresh);
    clear(body);
    draw();
    const head = section.querySelector("h2")!;
    clear(head);
    head.append(statusDot(status.installed), h("span", { text: "Claude Code" }));
  };

  function draw() {
    body.append(
      h("div", {
        class: "hint",
        text: status.installed
          ? "Perch is hooked into your coding-agent sessions. Tool calls, questions and permission requests show up in the island, and you can answer them there."
          : "Install the hooks to see your Claude Code sessions in the island and approve permissions without leaving what you are doing.",
      }),
      h("div", { class: "row" },
        h("label", { text: "settings.json" }),
        h("span", { class: "path", text: status.settingsPath }),
      ),
      h("div", { class: "row" },
        h("label", { text: "Relay" }),
        h("span", { class: "path", text: status.hookPath }),
        statusDot(status.hookReady),
      ),
    );

    if (!status.hookReady) {
      body.append(h("div", {
        class: "notice warn",
        text: "perch-hook.exe is not in place yet. Restart Perch; if it still fails, build it with `cargo build -p perch-hook`.",
      }));
    }

    const actions = h("div", { class: "row" });
    const install = h("button", {
      class: "primary",
      text: status.installed ? "Reinstall hooks…" : "Install hooks…",
      onclick: () => showPreview(true),
    });
    // Writing hook commands that point at a relay which isn't there would give
    // every Claude Code session a broken hook and nothing to show for it.
    if (!status.hookReady) {
      install.disabled = true;
      install.title = "The relay isn't installed yet.";
    }
    actions.append(install);
    if (status.installed) {
      actions.append(h("button", {
        class: "danger",
        text: "Uninstall hooks…",
        onclick: () => showPreview(false),
      }));
    }
    body.append(actions);
  }

  async function showPreview(install: boolean) {
    let preview;
    try {
      preview = await Bridge.hooksPreview(install);
    } catch (err) {
      // An unreadable or invalid settings.json stops here rather than being
      // treated as empty and written over.
      clear(body);
      body.append(
        h("div", { class: "notice err", text: String(err).replace(/^Error:\s*/, "") }),
        h("div", { class: "row" }, h("button", {
          text: "Back",
          onclick: () => { clear(body); draw(); },
        })),
      );
      return;
    }
    if (!preview) return;
    clear(body);
    body.append(
      h("div", {
        class: "hint",
        text: install
          ? "This is exactly what will change in your settings.json. Your own hooks are left untouched."
          : "This removes Perch's entries only. Your own hooks are left untouched.",
      }),
      renderDiff(preview.diff),
      h("div", { class: "row" },
        h("span", { class: "path", text: `Backup → ${preview.backup}` }),
      ),
    );
    const confirm = h("button", {
      class: install ? "primary" : "danger",
      text: install ? "Back up and write" : "Back up and remove",
    });
    confirm.addEventListener("click", async () => {
      confirm.disabled = true;
      try {
        const backup = await Bridge.hooksApply(install, preview.fingerprint);
        clear(body);
        body.append(h("div", {
          class: "notice ok",
          text: `Done. Previous settings saved as ${backup}. Open a new Claude Code session to pick the hooks up.`,
        }));
        window.setTimeout(() => void rebuild(), 2600);
      } catch (err) {
        confirm.disabled = false;
        body.append(h("div", { class: "notice err", text: `Could not write: ${String(err)}` }));
      }
    });
    body.append(h("div", { class: "row" }, confirm, h("button", {
      text: "Cancel",
      onclick: () => { clear(body); draw(); },
    })));
  }

  draw();
  return section;
}

// ── Other coding agents ─────────────────────────────────────────────────────

function agentsSection(initial: AgentStatus[]): HTMLElement {
  let statuses = initial;
  const body = h("div", { style: "display:flex;flex-direction:column;gap:12px" });
  const section = h(
    "section",
    {},
    h("h2", {}, h("span", { text: "Other coding agents" })),
    body,
  );

  const rebuild = async () => {
    const fresh = await Bridge.agentsStatus();
    if (fresh) statuses = fresh;
    clear(body);
    draw();
  };

  function draw() {
    body.append(h("div", {
      class: "hint",
      text: "Each agent gets its own pill in the island. Only Claude Code can ask for approvals from the notch — the rest are watched, never blocked.",
    }));
    for (const st of statuses) {
      const row = h("div", { class: "row" },
        statusDot(st.installed || st.processActive),
        h("span", { text: st.name, style: "min-width:90px;font-weight:600" }),
        h("span", { class: "hint", text: st.detail }),
      );
      body.append(row);
      // Integration method + live process state, so the user can tell native
      // hooks apart from process monitoring at a glance.
      body.append(h("div", { class: "row" },
        h("span", { class: "hint", text: `Method: ${st.integrationMethod}` }),
        statusDot(st.processActive),
        h("span", { class: "hint", text: st.processActive ? "CLI running" : "No CLI running" }),
      ));
      if (!st.canAuto) continue;
      const actions = h("div", { class: "row" });
      const install = h("button", {
        class: "primary",
        text: st.installed ? "Reinstall…" : "Install…",
        onclick: () => showPreview(st, true),
      });
      if (!st.hookReady) {
        install.disabled = true;
        install.title = "The relay isn't installed yet.";
      }
      actions.append(install);
      if (st.installed) {
        actions.append(h("button", {
          class: "danger",
          text: "Uninstall…",
          onclick: () => showPreview(st, false),
        }));
      }
      body.append(actions);
    }
    const pending = statuses.filter((s) => s.canAuto && !s.installed && (s.cliDetected || s.id === "opencode"));
    if (pending.length > 0) {
      const all = h("button", {
        class: "primary",
        text: `Connect all (${pending.map((s) => s.name).join(", ")})…`,
        onclick: async () => {
          for (const st of pending) {
            try {
              const preview = await Bridge.agentsPreview(st.id, true);
              await Bridge.agentsApply(st.id, true, preview.fingerprint);
            } catch (err) {
              body.append(h("div", {
                class: "notice err",
                text: `${st.name}: ${String(err).replace(/^Error:\s*/, "")}`,
              }));
            }
          }
          void rebuild();
        },
      });
      // Connect-all skips the per-agent diff on purpose: it only ever *adds*
      // Perch entries (dated backups first) and reports failures inline.
      // Anything already installed is left untouched.
      body.append(h("div", { class: "row" }, all));
    }
  }

  async function showPreview(st: AgentStatus, install: boolean) {
    let preview;
    try {
      preview = await Bridge.agentsPreview(st.id, install);
    } catch (err) {
      clear(body);
      body.append(
        h("div", { class: "notice err", text: String(err).replace(/^Error:\s*/, "") }),
        h("div", { class: "row" }, h("button", {
          text: "Back",
          onclick: () => { clear(body); draw(); },
        })),
      );
      return;
    }
    clear(body);
    body.append(
      h("div", {
        class: "hint",
        text: install
          ? `${st.name}: exactly what will change. Your own entries are left untouched.`
          : `${st.name}: this removes Perch's entries only.`,
      }),
      renderDiff(preview.diff),
      h("div", { class: "row" },
        h("span", { class: "path", text: `Backup → ${preview.backup}` }),
      ),
    );
    const confirm = h("button", {
      class: install ? "primary" : "danger",
      text: install ? "Back up and write" : "Back up and remove",
    });
    confirm.addEventListener("click", async () => {
      confirm.disabled = true;
      try {
        const backup = await Bridge.agentsApply(st.id, install, preview.fingerprint);
        clear(body);
        body.append(h("div", {
          class: "notice ok",
          text: `Done${backup ? `. Previous settings saved as ${backup}` : ""}. Open a new ${st.name} session to pick it up.`,
        }));
        window.setTimeout(() => void rebuild(), 2600);
      } catch (err) {
        confirm.disabled = false;
        body.append(h("div", { class: "notice err", text: `Could not write: ${String(err)}` }));
      }
    });
    body.append(h("div", { class: "row" }, confirm, h("button", {
      text: "Cancel",
      onclick: () => { clear(body); draw(); },
    })));
  }

  draw();
  return section;
}

// ── Chat section ──────────────────────────────────────────────────────────────

function chatSection(providers: ProviderInfo[], present: Record<string, boolean>): HTMLElement {
  if (providers.length === 0) {
    return h("section", {}, h("h2", {}, h("span", { text: "Chat" })),
      h("div", { class: "notice err", text: "No chat providers available." }));
  }
  const body = h("div", { style: "display:flex;flex-direction:column;gap:12px" });

  function activeProvider(): ProviderInfo {
    return providers.find((p) => p.id === settings.llmProvider) ?? providers[0];
  }

  async function draw() {
    const provider = activeProvider();
    const key = provider.credentialKey;
    const hasKey = key ? (present[key] ?? false) : false;

    clear(body);

    body.append(
      h("div", {
        class: "hint",
        text: provider.webSearch
          ? "Claude answers with live web search. Choose a provider below — each one keeps its own conversation."
          : `${provider.name} answers without web search. Choose a provider below — each one keeps its own conversation.`,
      }),
    );

    // Provider dropdown.
    const providerSelect = h("select", {}) as HTMLSelectElement;
    for (const p of providers) providerSelect.append(h("option", { value: p.id, text: p.name }));
    providerSelect.value = provider.id;
    providerSelect.addEventListener("change", () => {
      const next = providers.find((p) => p.id === providerSelect.value) ?? providers[0];
      settings.llmProvider = next.id;
      settings.model = next.models[0].id;
      void save();
      void draw();
    });
    body.append(h("div", { class: "row" }, h("label", { text: "Provider" }), providerSelect));

    // Model dropdown — the active provider's list.
    const model = h("select", {}) as HTMLSelectElement;
    for (const m of provider.models) model.append(h("option", { value: m.id, text: m.label }));
    if (!provider.models.some((m) => m.id === settings.model)) {
      model.append(h("option", { value: settings.model, text: settings.model }));
    }
    model.value = settings.model;
    model.addEventListener("change", () => {
      settings.model = model.value;
      void save();
    });
    body.append(h("div", { class: "row" }, h("label", { text: "Model" }), model));

    // API key (or endpoint for Ollama, which needs no key).
    if (key) {
      const dot = statusDot(hasKey);
      const state = h("span", {
        class: "hint",
        text: hasKey ? "Key saved in the Windows Credential Manager." : "No key yet — this provider needs one.",
      });
      const field = h("input", {
        type: "password",
        placeholder: hasKey ? "••••••••••••  (stored)" : provider.keyHint,
        style: "flex:1 1 auto;min-width:0",
        autocomplete: "off",
        spellcheck: "false",
      }) as HTMLInputElement;
      const saveBtn = h("button", { class: "primary", text: "Save key" });
      const clearBtn = h("button", { class: "danger", text: "Remove" });
      const feedback = h("div", {});
      clearBtn.style.display = hasKey ? "" : "none";

      saveBtn.addEventListener("click", async () => {
        const value = field.value.trim();
        if (!value) return;
        clear(feedback);
        try {
          await Bridge.secretSet(key, value);
          present[key] = true;
          field.value = "";
          field.placeholder = "••••••••••••  (stored)";
          dot.style.background = "#22c55e";
          state.textContent = "Key saved in the Windows Credential Manager.";
          clearBtn.style.display = "";
          feedback.append(h("div", { class: "notice ok", text: "Saved. It never touches disk." }));
        } catch (err) {
          feedback.append(h("div", { class: "notice err", text: `Could not save: ${String(err)}` }));
        }
      });

      clearBtn.addEventListener("click", async () => {
        clear(feedback);
        try {
          await Bridge.secretClear(key);
          present[key] = false;
          field.placeholder = provider.keyHint;
          dot.style.background = "#f4505e";
          state.textContent = "No key yet — this provider needs one.";
          clearBtn.style.display = "none";
          feedback.append(h("div", { class: "notice ok", text: "Key removed." }));
        } catch (err) {
          feedback.append(h("div", { class: "notice err", text: `Could not remove: ${String(err)}` }));
        }
      });

      body.append(
        h("div", { class: "row" }, h("label", { text: "API key" }), field, saveBtn, clearBtn),
        h("div", { class: "row" }, dot, state),
        feedback,
      );
    } else if (provider.urlKey) {
      // Ollama runs locally — an editable endpoint, not a key.
      const urlKey = provider.urlKey;
      const hasUrl = present[urlKey] ?? false;
      const field = h("input", {
        type: "text",
        placeholder: hasUrl ? "••••  (stored)" : "http://localhost:11434",
        style: "flex:1 1 auto;min-width:0",
        autocomplete: "off",
        spellcheck: "false",
      }) as HTMLInputElement;
      const saveBtn = h("button", { class: "primary", text: "Save URL" });
      const feedback = h("div", {});
      saveBtn.addEventListener("click", async () => {
        const value = field.value.trim();
        if (!value) return;
        clear(feedback);
        try {
          await Bridge.secretSet(urlKey, value);
          present[urlKey] = true;
          field.value = "";
          field.placeholder = "••••  (stored)";
          feedback.append(h("div", { class: "notice ok", text: "Endpoint saved." }));
        } catch (err) {
          feedback.append(h("div", { class: "notice err", text: `Could not save: ${String(err)}` }));
        }
      });
      body.append(
        h("div", { class: "row" }, h("label", { text: "Endpoint" }), field, saveBtn),
        h("div", { class: "hint", text: "Ollama needs no API key. Start it with `ollama serve` and pull the model you picked." }),
        feedback,
      );
    }

    if (provider.webSearch) {
      body.append(h("div", { class: "hint", text: "Web search and the server-side fallback model are Claude-only for now." }));
    }
  }

  void draw();
  return h("section", {}, h("h2", {}, h("span", { text: "Chat" })), body);
}

// ── Integrations section ──────────────────────────────────────────────────────

interface IntegrationDef {
  id: string;
  name: string;
  color: string;
  /** Credential Manager keys, in the order they are shown. */
  fields: { key: string; label: string; placeholder: string; secret: boolean }[];
}

const INTEGRATIONS: IntegrationDef[] = [
  { id: "integration_stripe", name: "Stripe", color: "#0570DE",
    fields: [{ key: "stripe-api-key", label: "Secret key", placeholder: "sk_live_…", secret: true }] },
  { id: "integration_github", name: "GitHub", color: "#F4505E",
    fields: [{ key: "github-token", label: "Token", placeholder: "ghp_…", secret: true }] },
  { id: "integration_vercel", name: "Vercel", color: "#7C5CFF",
    fields: [{ key: "vercel-token", label: "Token", placeholder: "…", secret: true }] },
  { id: "integration_n8n", name: "n8n", color: "#F29B38",
    fields: [
      { key: "n8n-url", label: "Instance URL", placeholder: "https://n8n.example.com", secret: false },
      { key: "n8n-api-key", label: "API key", placeholder: "…", secret: true },
    ] },
  { id: "integration_resend", name: "Resend", color: "#22C55E",
    fields: [{ key: "resend-api-key", label: "API key", placeholder: "re_…", secret: true }] },
  { id: "integration_notion", name: "Notion", color: "#8C8C8C",
    fields: [{ key: "notion-api-key", label: "Integration token", placeholder: "ntn_…", secret: true }] },
  { id: "integration_calcom", name: "Cal.com", color: "#C9956A",
    fields: [{ key: "calcom-api-key", label: "API key", placeholder: "cal_…", secret: true }] },
];

const MAX_ACTIVE = 4;

function integrationsSection(present: Record<string, boolean>): HTMLElement {
  const note = h("div", { class: "hint" });
  const list = h("div", { style: "display:flex;flex-direction:column;gap:14px" });

  function updateNote() {
    const used = settings.activeIntegrations.length;
    note.textContent = `Pick up to ${MAX_ACTIVE} pills to show next to Pip — ${used}/${MAX_ACTIVE} in use. Keys are stored in the Windows Credential Manager, never on disk.`;
  }

  for (const def of INTEGRATIONS) {
    const active = settings.activeIntegrations.includes(def.id);
    const sw = h("button", { class: active ? "switch on" : "switch" });
    sw.addEventListener("click", () => {
      const on = settings.activeIntegrations.includes(def.id);
      if (on) {
        settings.activeIntegrations = settings.activeIntegrations.filter((x) => x !== def.id);
      } else {
        if (settings.activeIntegrations.length >= MAX_ACTIVE) return;
        settings.activeIntegrations = [...settings.activeIntegrations, def.id];
      }
      sw.classList.toggle("on", !on);
      updateNote();
      void save();
    });

    const rows = h("div", { style: "display:flex;flex-direction:column;gap:6px;flex:1 1 auto;min-width:0" });
    for (const field of def.fields) {
      const input = h("input", {
        type: field.secret ? "password" : "text",
        placeholder: present[field.key] ? "••••••••  (stored)" : field.placeholder,
        autocomplete: "off",
        spellcheck: "false",
        style: "flex:1 1 auto;min-width:0",
      }) as HTMLInputElement;
      const saveBtn = h("button", { text: "Save" });
      const dotEl = statusDot(present[field.key] ?? false);
      saveBtn.addEventListener("click", async () => {
        const value = input.value.trim();
        try {
          await Bridge.secretSet(field.key, value);
          present[field.key] = value.length > 0;
          input.value = "";
          input.placeholder = value ? "••••••••  (stored)" : field.placeholder;
          dotEl.style.background = value ? "#22c55e" : "#f4505e";
        } catch {
          dotEl.style.background = "#f5a524";
        }
      });
      rows.append(
        h("div", { class: "row" },
          h("label", { style: "min-width:104px", text: field.label }),
          input, saveBtn, dotEl,
        ),
      );
    }

    list.append(
      h("div", { style: "display:flex;gap:12px;align-items:flex-start" },
        h("div", { style: "display:flex;align-items:center;gap:8px;min-width:132px;padding-top:4px" },
          sw,
          h("i", { class: "dot", style: `background:${def.color}` }),
          h("span", { style: "font-size:12.5px", text: def.name }),
        ),
        rows,
      ),
    );
  }

  updateNote();
  return h("section", {}, h("h2", {}, h("span", { text: "Integrations" })), note, list);
}

// ── General section ───────────────────────────────────────────────────────────

function generalSection(): HTMLElement {
  const volume = h("input", {
    type: "range", min: "0", max: "0.2", step: "0.005",
    value: String(settings.soundVolume),
  }) as HTMLInputElement;
  volume.addEventListener("input", () => {
    settings.soundVolume = Number(volume.value);
    void save();
  });

  const autoClose = h("input", {
    type: "number", min: "5", max: "120", step: "1",
    value: String(Math.round(settings.autoCloseInterval)),
    style: "width:72px",
  }) as HTMLInputElement;
  autoClose.addEventListener("change", () => {
    settings.autoCloseInterval = Math.max(5, Math.min(120, Number(autoClose.value) || 15));
    autoClose.value = String(settings.autoCloseInterval);
    void save();
  });

  const screen = h("select", {}) as HTMLSelectElement;
  screen.append(
    h("option", { value: "primary", text: "Main display" }),
    h("option", { value: "cursor", text: "Display under the cursor" }),
  );
  screen.value = settings.screen;
  screen.addEventListener("change", () => {
    settings.screen = screen.value as Settings["screen"];
    void save();
  });

  return h(
    "section",
    {},
    h("h2", {}, h("span", { text: "General" })),
    h("div", { class: "row" },
      h("label", { text: "Sound" }),
      toggle(settings.soundEnabled, (v) => { settings.soundEnabled = v; void save(); }),
      volume,
    ),
    h("div", { class: "row" },
      h("label", { text: "Auto-close" }),
      autoClose,
      h("span", { class: "hint", text: "seconds after you leave the island" }),
    ),
    h("div", { class: "row" },
      h("label", { text: "Island lives on" }),
      screen,
    ),
    h("div", { class: "row" },
      h("label", { text: "Launch at startup" }),
      toggle(settings.autostart, (v) => { settings.autostart = v; void save(); }),
    ),
  );
}

// ── Boot ──────────────────────────────────────────────────────────────────────

async function main() {
  const boot = await Bridge.boot();
  if (boot) {
    settings = { ...settings, ...boot.settings };
    version = boot.version;
  }
  const status = (await Bridge.hooksStatus()) ?? {
    installed: false, settingsPath: "", hookPath: "", hookReady: false,
  };

  const agentStatuses = (await Bridge.agentsStatus()) ?? [];

  const providers = (await Bridge.chatProviders()) ?? [];

  const keys = [
    "stripe-api-key", "github-token", "vercel-token",
    "n8n-url", "n8n-api-key", "resend-api-key", "notion-api-key", "calcom-api-key",
    ...providers.flatMap((p) => [p.credentialKey, p.urlKey]).filter((k): k is string => !!k),
  ];
  const present: Record<string, boolean> = {};
  for (const k of [...new Set(keys)]) present[k] = (await Bridge.secretPresent(k)) ?? false;

  clear(root);
  root.append(
    h("h1", {}, h("span", { text: "Perch" }), h("span", { class: "version", text: version })),
    claudeSection(status),
    agentsSection(agentStatuses),
    chatSection(providers, present),
    integrationsSection(present),
    generalSection(),
    h("div", {
      class: "hint",
      text: "No telemetry. Network requests only go to the services you configure yourself.",
    }),
  );

  void onEvent<Settings>("settings-changed", (s) => {
    settings = { ...settings, ...s };
  });
}

void main();
