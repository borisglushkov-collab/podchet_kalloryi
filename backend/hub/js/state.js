import {
  defaultProfile,
  emptyDay,
  todayIso,
} from "./logic.js";

export const STORAGE_DAYS = "hub.days.v1";
export const STORAGE_PROFILE = "hub.profile.v1";
export const STORAGE_CHAT = "hub.chat.v1";

export function loadJson(key, fallback) {
  try {
    const raw = localStorage.getItem(key);
    return raw ? JSON.parse(raw) : fallback;
  } catch {
    return fallback;
  }
}

export function saveJson(key, value) {
  localStorage.setItem(key, JSON.stringify(value));
}

export const state = {
  date: todayIso(),
  tab: "today",
  morePane: "sources", // sources | profile
  days: loadJson(STORAGE_DAYS, {}),
  profile: { ...defaultProfile(), ...loadJson(STORAGE_PROFILE, {}) },
  chat: loadJson(STORAGE_CHAT, []),
  sending: false,
  collectorStatus: {},
  xiaomi2fa: null,
  fatsecretSession: null,
  refreshing: false,
  weekSeries: null,
  weekReport: "",
  unlocked: false,
  pinRequired: false,
  online: typeof navigator === "undefined" ? true : navigator.onLine,
  lastError: null,
  coachReportOpen: false,
  assetVersion: document.querySelector('meta[name="hub-version"]')?.content || "dev",
};

export function day() {
  if (!state.days[state.date]) state.days[state.date] = emptyDay(state.date);
  return state.days[state.date];
}

export function dayFor(date) {
  if (!state.days[date]) state.days[date] = emptyDay(date);
  return state.days[date];
}

export function persistLocal() {
  saveJson(STORAGE_DAYS, state.days);
  saveJson(STORAGE_PROFILE, state.profile);
  saveJson(STORAGE_CHAT, state.chat);
}
