/** DOM helpers: toast, focus preserve, offline banner, pin trap, skeleton. */

let toastTimer = null;

export function toast(text) {
  let el = document.querySelector(".toast");
  if (!el) {
    el = document.createElement("div");
    el.className = "toast";
    document.body.appendChild(el);
  }
  el.textContent = text;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.remove(), 2400);
}

export function escapeHtml(text) {
  return String(text)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

export function escapeAttr(text) {
  return escapeHtml(text).replaceAll('"', "&quot;");
}

export function val(id) {
  return document.getElementById(id)?.value?.trim() || "";
}

export function captureFocus() {
  const ae = document.activeElement;
  if (!ae || !ae.id || !["INPUT", "TEXTAREA", "SELECT"].includes(ae.tagName)) return null;
  return {
    id: ae.id,
    start: ae.selectionStart ?? null,
    end: ae.selectionEnd ?? null,
    value: ae.value,
  };
}

export function restoreFocus(snap) {
  if (!snap?.id) return;
  const el = document.getElementById(snap.id);
  if (!el) return;
  if (snap.value != null && "value" in el && el.value !== snap.value) {
    // Keep what user had typed before full replace wiped the field.
    el.value = snap.value;
  }
  el.focus();
  if (typeof snap.start === "number" && typeof el.setSelectionRange === "function") {
    try {
      el.setSelectionRange(snap.start, snap.end ?? snap.start);
    } catch {
      /* type=number etc */
    }
  }
}

export function setOfflineBanner(online, message) {
  let el = document.getElementById("offline-banner");
  if (online && !message) {
    el?.classList.add("hidden");
    if (el) el.textContent = "";
    return;
  }
  if (!el) {
    el = document.createElement("div");
    el.id = "offline-banner";
    el.className = "offline-banner";
    el.setAttribute("role", "status");
    document.body.prepend(el);
  }
  el.textContent = message || "Офлайн — показаны локальные данные, облако недоступно";
  el.classList.remove("hidden");
}

export function setSkeleton(on) {
  document.body.classList.toggle("is-refreshing", Boolean(on));
  const stage = document.querySelector(".stage");
  stage?.classList.toggle("skeleton-pulse", Boolean(on));
}

export function setCompactStage(compact) {
  document.body.classList.toggle("stage-compact", Boolean(compact));
}

export function updateTabA11y(activeTab) {
  document.querySelectorAll(".tabs button").forEach((b) => {
    const on = b.dataset.tab === activeTab;
    b.classList.toggle("active", on);
    b.setAttribute("aria-selected", on ? "true" : "false");
    b.setAttribute("role", "tab");
  });
}

export function showPinGate(show) {
  const gate = document.getElementById("pin-gate");
  if (!gate) return;
  gate.classList.toggle("hidden", !show);
  gate.setAttribute("aria-hidden", show ? "false" : "true");
  if (show) {
    const input = document.getElementById("hub-pin");
    input?.focus();
    trapFocus(gate);
  } else {
    releaseFocusTrap();
  }
}

let trapHandler = null;

function trapFocus(container) {
  releaseFocusTrap();
  const focusables = () =>
    [...container.querySelectorAll("input, button, textarea, select, [tabindex]:not([tabindex='-1'])")].filter(
      (el) => !el.disabled && el.offsetParent !== null,
    );
  trapHandler = (e) => {
    if (e.key !== "Tab") return;
    const list = focusables();
    if (!list.length) return;
    const first = list[0];
    const last = list[list.length - 1];
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
  };
  document.addEventListener("keydown", trapHandler);
}

function releaseFocusTrap() {
  if (trapHandler) document.removeEventListener("keydown", trapHandler);
  trapHandler = null;
}

export function setRefreshStatus(text, isError = false) {
  const el = document.getElementById("refresh-status");
  if (!el) return;
  el.textContent = text || "";
  el.classList.toggle("error", Boolean(isError));
}
