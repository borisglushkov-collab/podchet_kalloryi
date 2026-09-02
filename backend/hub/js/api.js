/** Unified API client with credentials + structured errors. */

export class ApiError extends Error {
  constructor(message, { status = 0, detail = null, offline = false } = {}) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.detail = detail;
    this.offline = offline;
  }
}

function detailMessage(data, fallback) {
  if (!data) return fallback;
  if (typeof data.detail === "string") return data.detail;
  if (Array.isArray(data.detail)) {
    return data.detail.map((d) => d.msg || JSON.stringify(d)).join("; ") || fallback;
  }
  if (data.detail?.message) return data.detail.message;
  return fallback;
}

export async function api(path, options = {}) {
  const opts = {
    credentials: "same-origin",
    ...options,
    headers: {
      ...(options.body && !(options.body instanceof FormData)
        ? { "Content-Type": "application/json" }
        : {}),
      ...(options.headers || {}),
    },
  };
  let res;
  try {
    res = await fetch(path, opts);
  } catch (err) {
    throw new ApiError(err?.message || "Сеть недоступна", { offline: true });
  }
  let data = null;
  const text = await res.text();
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = { raw: text };
    }
  }
  if (!res.ok) {
    throw new ApiError(detailMessage(data, `Ошибка ${res.status}`), {
      status: res.status,
      detail: data?.detail ?? data,
    });
  }
  return data;
}

export const healthApi = {
  gate: () => api("/api/health/gate"),
  unlock: (pin) => api("/api/health/unlock", { method: "POST", body: JSON.stringify({ pin }) }),
  profile: () => api("/api/health/profile"),
  putProfile: (body) => api("/api/health/profile", { method: "PUT", body: JSON.stringify(body) }),
  day: (date) => api(`/api/health/day/${date}`),
  week: (date, days = 7) => api(`/api/health/week?days=${days}&end=${encodeURIComponent(date)}`),
  collectNow: (date) =>
    api(`/api/health/collect-now?date=${encodeURIComponent(date)}`, { method: "POST" }),
  backfill: (days = 7) => api(`/api/health/backfill?days=${days}`, { method: "POST" }),
  sync: (snapshot) =>
    api("/api/health/sync", { method: "POST", body: JSON.stringify({ snapshot }) }),
  collectorStatus: () => api("/api/health/collector-status"),
  bloodPressure: (reading) =>
    api("/api/health/blood-pressure", { method: "POST", body: JSON.stringify(reading) }),
  importCsv: (csv) =>
    api("/api/health/blood-pressure/import-csv", {
      method: "POST",
      body: JSON.stringify({ csv }),
    }),
  coachChat: (payload) =>
    api("/api/coach-health-chat", { method: "POST", body: JSON.stringify(payload) }),
  xiaomiLogin: (body) =>
    api("/api/health/xiaomi-login", { method: "POST", body: JSON.stringify(body) }),
  xiaomiVerify: (body) =>
    api("/api/health/xiaomi-verify", { method: "POST", body: JSON.stringify(body) }),
  xiaomiTokens: (body) =>
    api("/api/health/xiaomi-tokens", { method: "POST", body: JSON.stringify(body) }),
  fatsecretConnect: () => api("/api/health/fatsecret-auth"),
  fatsecretVerify: (body) =>
    api("/api/health/fatsecret-verify", { method: "POST", body: JSON.stringify(body) }),
  medmLogin: (body) =>
    api("/api/health/medm-login", { method: "POST", body: JSON.stringify(body) }),
  disconnect: (source) =>
    api(`/api/health/disconnect/${source}`, { method: "POST" }),
};
