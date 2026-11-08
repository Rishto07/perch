// Drop zone, upload progress and the "what do you want to do with it" card —
// ports of UploadView / UploadingView / ChooseView from IslandViewContent.swift.
//
// Sending a file by email is not in the Windows v1, so `choose` offers the one
// action the spec asks for: ask a question about it.

import { h, clear } from "./dom";
import { State } from "../core/state";
import type { ViewActions, ViewHost } from "./views";

/** Dashed rounded rect drawn as SVG so the dashes can march like on macOS. */
function dashedFrame(): SVGSVGElement {
  const ns = "http://www.w3.org/2000/svg";
  const el = document.createElementNS(ns, "svg");
  el.setAttribute("class", "drop-frame");
  el.setAttribute("preserveAspectRatio", "none");
  const rect = document.createElementNS(ns, "rect");
  rect.setAttribute("x", "0.75");
  rect.setAttribute("y", "0.75");
  rect.setAttribute("width", "calc(100% - 1.5px)");
  rect.setAttribute("height", "calc(100% - 1.5px)");
  rect.setAttribute("rx", "20");
  rect.setAttribute("fill", "none");
  rect.setAttribute("stroke-width", "1.5");
  rect.setAttribute("stroke-dasharray", "6 5");
  el.append(rect);
  return el;
}

export function buildUpload(): ViewHost {
  const frame = dashedFrame();
  const title = h("div", { class: "drop-title", text: "Drop your files here" });
  const hint = h("div", {
    class: "drop-hint",
    text: "or click anywhere in the box to browse",
    style: "font-size:10.5px;color:#6b7079;margin-top:2px",
  });
  // File picker fallback so the zone works everywhere (browser preview has no
  // Tauri OLE drag-drop; some users simply prefer clicking).
  const input = document.createElement("input");
  input.type = "file";
  input.multiple = true;
  input.style.display = "none";

  const emitFiles = (files: FileList | File[]) => {
    if (!files.length) return;
    const ev = new CustomEvent<File[]>("perch:browser-files", {
      detail: Array.from(files as ArrayLike<File>),
    });
    window.dispatchEvent(ev);
  };

  const setAccept = (kind: string) => {
    input.accept =
      kind === "PDF" ? "application/pdf"
      : kind === "Images" ? "image/*"
      : kind === "Code" ? "text/*,.ts,.tsx,.js,.jsx,.rs,.swift,.go,.py,.java,.cs,.cpp,.h,.html,.css,.json,.toml,.yaml,.yml,.md"
      : kind === "Docs" ? ".txt,.md,.doc,.docx,.odt,.rtf,.xls,.xlsx,.ppt,.pptx,.csv"
      : "";
    input.click();
  };

  const tags = h(
    "div",
    { class: "drop-tags" },
    ...["PDF", "Images", "Code", "Docs"].map((t) => {
      const tag = h("span", { text: t, role: "button" });
      tag.style.cursor = "pointer";
      tag.title = `Pick a ${t.toLowerCase()} file`;
      tag.addEventListener("click", (e) => {
        e.stopPropagation();
        setAccept(t);
      });
      return tag;
    }),
  );
  const card = h(
    "div",
    { class: "card drop-card" },
    frame,
    h("div", { class: "drop-body" }, title, hint, tags),
  );
  input.addEventListener("change", () => {
    if (input.files?.length) emitFiles(input.files);
    input.value = "";
  });
  card.addEventListener("click", (e) => {
    if ((e.target as HTMLElement).closest(".drop-tags")) return;
    setAccept("");
  });
  for (const ev of ["dragover", "dragenter", "dragleave", "drop"] as const) {
    card.addEventListener(ev, (e) => {
      e.preventDefault();
      if (ev === "dragover" || ev === "dragenter") card.classList.add("over");
      if (ev === "dragleave" || ev === "drop") card.classList.remove("over");
      if (ev === "drop") {
        const dt = (e as DragEvent).dataTransfer;
        if (dt?.files?.length) emitFiles(dt.files);
      }
    });
  }
  card.append(input);
  const el = h("div", { class: "view" }, card);

  return {
    el,
    sync() {
      card.classList.toggle("over", State.fileDragOver);
    },
  };
}

export function buildUploading(): ViewHost {
  const label = h("span", { class: "up-name" });
  const percent = h("span", { class: "up-pct" });
  const fill = h("div", { class: "up-fill" });
  const glow = h("div", { class: "up-glow" });
  const card = h(
    "div",
    { class: "card up-card" },
    h("div", { class: "up-row" }, label, percent),
    h("div", { class: "up-track" }, fill, glow),
  );
  const el = h("div", { class: "view" }, card);

  return {
    el,
    sync() {
      const done = State.uploadProgress >= 0.999;
      const pct = Math.round(State.uploadProgress * 100);
      label.textContent = done
        ? `✓  ${State.droppedFile?.name ?? "File"}`
        : `Uploading ${State.droppedFile?.name ?? "file"}`;
      label.classList.toggle("done", done);
      percent.textContent = done ? "" : `${pct} %`;
      const w = State.uploadProgress * 526;
      fill.style.width = `${w}px`;
      glow.style.transform = `translateX(${Math.max(0, w - 14)}px)`;
      glow.style.opacity = State.uploadProgress > 0.01 ? "1" : "0";
      card.classList.toggle("done", done);
    },
  };
}

export function buildChoose(actions: ViewActions): ViewHost {
  const title = h("div", { class: "title" });
  const sub = h("div", { class: "sub", text: "What do you want to do with it?" });
  const row = h(
    "div",
    { class: "actions" },
    h("button", {
      class: "btn primary",
      text: "Ask a question",
      onclick: () => actions.setView("prompt"),
    }),
    h("button", {
      class: "btn secondary",
      text: "Cancel",
      onclick: () => actions.setView(State.defaultView()),
    }),
  );
  const el = h(
    "div",
    { class: "view" },
    h(
      "div",
      { class: "card" },
      h("div", { class: "stack", style: "padding:0 18px 0 98px" }, title, sub, row),
    ),
  );

  return {
    el,
    sync() {
      clear(title);
      title.append(
        h("b", { text: State.droppedFile?.name ?? "file" }),
        document.createTextNode(" is ready."),
      );
    },
  };
}
