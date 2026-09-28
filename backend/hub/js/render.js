import {
  MEAL_RU,
  buildHealthTiles,
  formatSleepDuration,
  hasManualLocks,
  latestBpReading,
  nutritionTotals,
  sleepQualityLabel,
  sortBpNewestFirst,
  weekGoalStats,
  syncTone,
} from "./logic.js";
import { state, day } from "./state.js";
import { escapeHtml, escapeAttr } from "./ui.js";

const TILE_ICONS = {
  sleep: `<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M4.5 14.5c0-3.7 3-6.7 6.7-6.7.7 0 1.4.1 2 .3A5.8 5.8 0 0 0 9.2 12a5.8 5.8 0 0 0 5.7 5.8c1.8 0 3.4-.8 4.5-2.1.4.9.6 1.9.6 2.9A6.8 6.8 0 0 1 13.2 21.5 6.8 6.8 0 0 1 6.5 14.8c0-.1 0-.2 0-.3Z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><path d="M15.2 5.2c.3 1.1 1.2 2 2.3 2.3-.1.3-.1.5 0 .8-.1.2-.1.4 0 .6-1.1.3-2 1.2-2.3 2.3-.3-.1-.5-.1-.8 0-.2-.1-.4-.1-.6 0-.3-1.1-1.2-2-2.3-2.3.1-.3.1-.5 0-.8.1-.2.1-.4 0-.6 1.1-.3 2-1.2 2.3-2.3.3.1.5.1.8 0 .2.1.4.1.6 0Z" fill="currentColor"/></svg>`,
  steps: `<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M7 17.5c1.2-2.4 2-4.8 2-7.2C9 7.4 10.3 5.5 12.4 5.5c1.5 0 2.5 1 3.1 2.4.5 1.2.8 2.7 1.2 4.1.3 1.2.9 2.3 1.8 3.1" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><path d="M6.5 20.2h3.2M14.2 20.2h3.3" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>`,
  heart: `<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M12 19.2s-6.2-3.9-6.2-8.1A3.7 3.7 0 0 1 12 8.4a3.7 3.7 0 0 1 6.2 2.7c0 4.2-6.2 8.1-6.2 8.1Z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><path d="M5.5 12.2h2.2l1.4-2.4 2.2 4.2 1.5-2.5H15" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
  activity: `<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M4.5 14.5 8 8.8l3.2 6.2 2.6-4.3 2.5 3.8 3.2-5.7" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
  bp: `<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M12 20.2c3.8-3.2 5.8-5.9 5.8-8.6A3.8 3.8 0 0 0 12 8.2a3.8 3.8 0 0 0-5.8 3.4c0 2.7 2 5.4 5.8 8.6Z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><path d="M10.2 11.6h3.6M12 9.8v3.6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>`,
  weight: `<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><rect x="4.5" y="6.5" width="15" height="11" rx="3.2" stroke="currentColor" stroke-width="1.7"/><path d="M9.2 11.2c.6-1.4 1.5-2.2 2.8-2.2s2.2.8 2.8 2.2" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/><circle cx="12" cy="12.4" r="1.1" fill="currentColor"/></svg>`,
  workouts: `<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M7.2 9.2 5 11.4l2.2 2.2M16.8 9.2 19 11.4l-2.2 2.2M8.4 11.4h7.2" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/><path d="M10.2 7.5l1.8 3.9 1.8-3.9" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
};

function dateLabelRu(isoDate) {
  if (!isoDate) return "";
  try {
    return new Date(`${isoDate}T12:00:00`).toLocaleDateString("ru-RU", {
      day: "numeric",
      month: "long",
    });
  } catch {
    return isoDate;
  }
}

function renderTileViz(tile) {
  const viz = tile.viz || "none";
  const data = tile.vizData || {};
  if (viz === "sleep-scale") {
    const pct = data.pct ?? 50;
    const stages = data.stages;
    const bar = stages
      ? `<div class="tile-stages" aria-hidden="true">
          <span class="st-deep" style="flex:${stages.deep}"></span>
          <span class="st-light" style="flex:${stages.light}"></span>
          <span class="st-rem" style="flex:${stages.rem}"></span>
        </div>`
      : `<div class="tile-progress" aria-hidden="true"><span style="width:${pct}%"></span></div>`;
    return `<div class="tile-viz">
      ${bar}
      <div class="tile-scale">
        <span class="tile-needle" style="left:${pct}%"></span>
      </div>
      <div class="tile-axis"><span>${escapeHtml(data.labels?.[0] || "Плохо")}</span><span>${escapeHtml(data.labels?.[1] || "Превосходно")}</span></div>
    </div>`;
  }
  if (viz === "progress") {
    const pct = data.pct ?? 0;
    return `<div class="tile-viz">
      <div class="tile-progress" aria-hidden="true"><span style="width:${pct}%"></span></div>
      <div class="tile-axis"><span>${escapeHtml(data.left || "0")}</span><span>${escapeHtml(data.right || "")}</span></div>
    </div>`;
  }
  if (viz === "range" && data.min != null && data.max != null) {
    const min = Number(data.min);
    const max = Number(data.max);
    const mid = Number(data.mid ?? min);
    const span = Math.max(max - min, 1);
    const left = Math.round(((mid - min) / span) * 100);
    return `<div class="tile-viz">
      <div class="tile-range" aria-hidden="true">
        <span class="tile-range-track"></span>
        <span class="tile-range-dot" style="left:${left}%"></span>
      </div>
      <div class="tile-axis"><span>${min}</span><span>${max}</span></div>
    </div>`;
  }
  if (viz === "bp-mark") {
    const high = !!data.high;
    return `<div class="tile-viz">
      <div class="tile-progress ${high ? "warn" : ""}" aria-hidden="true"><span style="width:${high ? 82 : 45}%"></span></div>
      <div class="tile-axis"><span>${escapeHtml(data.left || "")}</span><span>${escapeHtml(data.right || "")}</span></div>
    </div>`;
  }
  return `<div class="tile-viz tile-viz-empty" aria-hidden="true"><div class="tile-progress"><span style="width:0%"></span></div></div>`;
}

export function renderHealthTiles(d) {
  const miConnected = Boolean(state.collectorStatus?.connections?.xiaomi?.connected);
  const tiles = buildHealthTiles(d, {
    miConnected,
    dateLabel: dateLabelRu(d.date || state.date),
  });
  return `<div class="health-grid" role="list">
    ${tiles.map((tile) => `
      <button type="button" class="health-tile tone-${escapeAttr(tile.tone)}${tile.empty ? " is-empty" : ""}"
        data-health-tile="${escapeAttr(tile.id)}" role="listitem"
        aria-label="${escapeAttr(tile.title)}: ${escapeAttr(tile.value)}">
        <span class="tile-ico" aria-hidden="true">${TILE_ICONS[tile.id] || TILE_ICONS.activity}</span>
        <span class="tile-title">${escapeHtml(tile.title)}</span>
        <span class="tile-value">${escapeHtml(tile.value)}</span>
        <span class="tile-sub">${escapeHtml(tile.sub)}</span>
        ${renderTileViz(tile)}
        <span class="tile-chev" aria-hidden="true">›</span>
      </button>`).join("")}
  </div>`;
}

function detailRows(rows) {
  const filled = rows.filter(([, v]) => v != null && v !== "" && v !== "—");
  if (!filled.length) return `<p class="empty-hint">Пока нет подробностей за этот день.</p>`;
  return `<dl class="detail-dl">${filled.map(([k, v]) => `
    <div class="detail-row"><dt>${escapeHtml(k)}</dt><dd>${escapeHtml(String(v))}</dd></div>`).join("")}</dl>`;
}

export function renderHealthDetail(id, d) {
  const titles = {
    sleep: "Сон",
    steps: "Шаги",
    heart: "Пульс",
    activity: "Активность",
    bp: "Давление",
    weight: "Вес",
    workouts: "Тренировки",
  };
  const title = titles[id] || "Здоровье";
  let body = "";
  if (id === "sleep") {
    const q = sleepQualityLabel(d.sleep_min);
    body = detailRows([
      ["Длительность", formatSleepDuration(d.sleep_min)],
      ["Оценка", q],
      ["Глубокий", d.sleep_deep_min != null ? `${d.sleep_deep_min} мин` : null],
      ["Лёгкий", d.sleep_light_min != null ? `${d.sleep_light_min} мин` : null],
      ["REM", d.sleep_rem_min != null ? `${d.sleep_rem_min} мин` : null],
      ["В кровати", formatSleepDuration(d.sleep_in_bed_min)],
      ["Пульс сна", d.sleep_avg_hr != null ? `${d.sleep_avg_hr} уд/мин` : null],
    ]);
  } else if (id === "steps") {
    const distKm = d.steps_distance_m != null ? `${(Number(d.steps_distance_m) / 1000).toFixed(1)} км` : null;
    body = detailRows([
      ["Шаги", d.steps],
      ["Дистанция", distKm],
      ["Ккал активности", d.steps_calories],
      ["Источник", "Mi Fitness"],
    ]);
  } else if (id === "heart") {
    const hr = d.heart_rate || {};
    body = detailRows([
      ["Средний", hr.avg != null ? `${hr.avg} уд/мин` : null],
      ["Минимум", hr.min != null ? `${hr.min}` : null],
      ["Максимум", hr.max != null ? `${hr.max}` : null],
      ["Замеров", hr.samples],
    ]);
  } else if (id === "activity") {
    const distKm = d.steps_distance_m != null ? `${(Number(d.steps_distance_m) / 1000).toFixed(1)} км` : null;
    const workouts = d.workouts || [];
    body = detailRows([
      ["Ккал", d.steps_calories],
      ["Дистанция", distKm],
      ["Шаги", d.steps],
      ["Тренировок", workouts.length || null],
    ]);
    if (workouts.length) {
      body += `<ul class="list compact">${workouts.map((w) => {
        const sub = [
          w.duration_min && `${w.duration_min} мин`,
          w.distance_m && `${(Number(w.distance_m) / 1000).toFixed(1)} км`,
          w.calories && `${w.calories} ккал`,
          w.avg_hr && `пульс ${w.avg_hr}`,
        ].filter(Boolean).join(" · ");
        return `<li><span>${escapeHtml(w.name || "Тренировка")}${sub ? ` — ${escapeHtml(sub)}` : ""}</span></li>`;
      }).join("")}</ul>`;
    }
  } else if (id === "bp") {
    const bp = latestBpReading(d.bp);
    const avg = (() => {
      const cutoff = new Date();
      cutoff.setDate(cutoff.getDate() - 7);
      const all = Object.values(state.days).flatMap((x) => x.bp || []);
      const window = all.filter((r) => new Date(r.measured_at) >= cutoff);
      if (!window.length) return null;
      const sys = window.reduce((s, r) => s + Number(r.systolic), 0) / window.length;
      const dia = window.reduce((s, r) => s + Number(r.diastolic), 0) / window.length;
      return { systolic: Math.round(sys), diastolic: Math.round(dia) };
    })();
    body = detailRows([
      ["Последнее", bp ? `${bp.systolic}/${bp.diastolic}` : null],
      ["Пульс", bp?.pulse],
      ["Среднее 7д", avg ? `${avg.systolic}/${avg.diastolic}` : null],
      ["Замеров сегодня", (d.bp || []).length || null],
    ]);
    const list = sortBpNewestFirst(d.bp);
    if (list.length) {
      body += `<ul class="list compact">${list.map((r) => {
        const t = String(r.measured_at || "");
        const hh = t.includes("T") ? t.split("T")[1].slice(0, 5) : "";
        return `<li><span>${r.systolic}/${r.diastolic}${r.pulse ? ` · ${r.pulse}` : ""}${hh ? ` · ${hh}` : ""}${r.source ? ` · ${escapeHtml(r.source)}` : ""}</span></li>`;
      }).join("")}</ul>`;
    }
  } else if (id === "weight") {
    const bc = d.body_composition;
    const weightVal = bc?.weight_kg ?? d.weight_kg;
    body = detailRows([
      ["Вес", weightVal != null ? `${weightVal} кг` : null],
      ["ИМТ", bc?.bmi],
      ["Жир", bc?.body_fat_pct != null ? `${bc.body_fat_pct}%` : null],
      ["Мышцы", bc?.muscle_kg != null ? `${bc.muscle_kg} кг` : null],
      ["Вода", bc?.water_pct != null ? `${bc.water_pct}%` : null],
      ["Кость", bc?.bone_kg != null ? `${bc.bone_kg} кг` : null],
      ["Висц. жир", bc?.visceral_fat],
      ["Возраст тела", bc?.body_age],
      ["BMR", bc?.bmr_kcal != null ? `${bc.bmr_kcal} ккал` : null],
      ["Оценка", bc?.body_score],
      ["Источник", bc?.source || null],
    ]);
  } else if (id === "workouts") {
    const workouts = d.workouts || [];
    if (!workouts.length) {
      body = `<p class="empty-hint">За этот день тренировок нет.</p>`;
    } else {
      body = `<ul class="list">${workouts.map((w) => {
        const sub = [
          w.duration_min && `${w.duration_min} мин`,
          w.distance_m && `${(Number(w.distance_m) / 1000).toFixed(1)} км`,
          w.calories && `${w.calories} ккал`,
          w.avg_hr && `пульс ${w.avg_hr}`,
        ].filter(Boolean).join(" · ");
        return `<li><span><strong>${escapeHtml(w.name || "Тренировка")}</strong>${sub ? `<br><span class="sub">${escapeHtml(sub)}</span>` : ""}</span></li>`;
      }).join("")}</ul>`;
    }
  } else {
    body = `<p class="empty-hint">Нет данных.</p>`;
  }

  return `
    <div class="health-sheet" id="health-sheet" role="dialog" aria-modal="true" aria-labelledby="health-sheet-title">
      <div class="health-sheet-backdrop" data-health-close="1"></div>
      <div class="health-sheet-panel">
        <div class="health-sheet-bar">
          <button type="button" class="btn soft sheet-back" data-health-close="1" aria-label="Назад">‹ Назад</button>
          <h2 id="health-sheet-title" class="health-sheet-title">${escapeHtml(title)}</h2>
          <span class="sheet-spacer"></span>
        </div>
        <div class="health-sheet-body">
          <p class="panel-sub">${escapeHtml(dateLabelRu(d.date || state.date))} · данные хаба</p>
          ${body}
        </div>
      </div>
    </div>`;
}

export function fmtNum(v, suffix = "") {
  if (v == null || v === "") return null;
  const n = Number(v);
  if (Number.isNaN(n)) return null;
  const text = Number.isInteger(n) ? String(n) : String(Math.round(n * 10) / 10);
  return suffix ? `${text}${suffix}` : text;
}

export function renderBodyMetrics(bc) {
  if (!bc) return "";
  const rows = [
    ["ИМТ", fmtNum(bc.bmi)],
    ["Жир", fmtNum(bc.body_fat_pct, "%")],
    ["Мышцы", fmtNum(bc.muscle_kg, " кг")],
    ["Вода", fmtNum(bc.water_pct, "%")],
    ["Кость", fmtNum(bc.bone_kg, " кг")],
    ["Висц. жир", fmtNum(bc.visceral_fat)],
    ["Возраст тела", fmtNum(bc.body_age, " лет")],
    ["БMR", fmtNum(bc.bmr_kcal, " ккал")],
    ["Оценка", fmtNum(bc.body_score, "/100")],
    ["Пульс", fmtNum(bc.heart_rate, " уд/мин")],
    ["Скел. мышцы", fmtNum(bc.skeletal_muscle_kg, " кг")],
    ["Белок", fmtNum(bc.protein_kg, " кг")],
  ].filter(([, val]) => val != null);
  if (!rows.length) return "";
  return `<div class="metrics">${rows.map(([label, val]) => `
      <div class="metric">
        <div class="metric-label">${label}</div>
        <div class="metric-value">${val}</div>
      </div>`).join("")}</div>`;
}

export function connectionBadge(ok, label) {
  return `<span class="badge ${ok ? "ok" : "off"}">${label}: ${ok ? "подключён" : "нет"}</span>`;
}

export function sourceLabel(key, status) {
  const names = {
    mi_fitness: "Mi Fitness",
    xiaomi_home: "Весы",
    fatsecret: "FatSecret",
    medm: "MedM",
  };
  const name = names[key] || key;
  if (!status) return `${name}: —`;
  if (status.ok === false) {
    if (status.error === "not_connected") return `${name}: не подключён`;
    return `${name}: ошибка`;
  }
  if (status.count != null) return `${name}: ${status.count}`;
  return `${name}: ок`;
}

export function sparkBars(values, maxHint, { relative = false } = {}) {
  const nums = values.map((v) => (v == null || Number.isNaN(Number(v)) ? null : Number(v)));
  const present = nums.filter((v) => v != null);
  let min = 0;
  let max = Math.max(maxHint || 0, ...(present.length ? present : [1]));
  if (relative && present.length) {
    min = Math.min(...present);
    max = Math.max(...present);
    if (max <= min) max = min + 1;
  }
  const span = Math.max(max - min, 1);
  return `<div class="spark">${nums
    .map((v) => {
      if (v == null) return `<span class="bar empty" title="нет данных"></span>`;
      const h = Math.max(8, Math.round(((v - min) / span) * 56));
      return `<span class="bar" style="height:${h}px" title="${Math.round(v * 10) / 10}"></span>`;
    })
    .join("")}</div>`;
}

export function emptyState(title, hint, action, ctaLabel) {
  const btn = action
    ? `<button class="btn primary" type="button" data-action="${escapeAttr(action)}">${ctaLabel || "Обновить"}</button>`
    : "";
  return `<div class="empty-state">
    <p class="empty-title">${escapeHtml(title)}</p>
    <p class="empty-hint">${escapeHtml(hint)}</p>
    ${btn}
  </div>`;
}

export function sourceStatusCards(d) {
  const conn = state.collectorStatus?.connections || {};
  const ss = d.sources_status || {};
  const rows = [
    {
      label: "Mi Fitness",
      connected: !!conn.xiaomi?.connected,
      st: ss.mi_fitness || ss.xiaomi_home,
      detail: d.steps != null ? `шаги ${d.steps}` : (d.sleep_min != null ? "сон есть" : "нет данных"),
    },
    {
      label: "FatSecret",
      connected: !!conn.fatsecret?.connected,
      st: ss.fatsecret,
      detail: d.meals?.length ? `${d.meals.length} записей` : "пусто",
    },
    {
      label: "MedM",
      connected: !!conn.medm?.connected,
      st: ss.medm,
      detail: d.bp?.length ? `АД ${d.bp.length}` : "пусто",
    },
  ];
  return `<div class="source-grid">${rows.map((r) => {
    const tone = syncTone({
      connected: r.connected,
      status: r.st,
      lastSyncedAt: d.last_synced_at,
      refreshing: state.refreshing,
    });
    return `<div class="source-card ${tone.tone}">
      <div class="source-label">${r.label}</div>
      <div class="source-status">${tone.label}</div>
      <div class="source-detail">${r.detail}</div>
    </div>`;
  }).join("")}</div>`;
}

export function weekGoalStrip(series) {
  const stats = weekGoalStats(series, state.profile.coaching_calorie_target || {});
  const sleepTxt = stats.avgSleep != null
    ? `${Math.floor(stats.avgSleep / 60)}ч ${stats.avgSleep % 60}м`
    : "—";
  return `<div class="goal-strip">
    <div class="goal-item"><span class="goal-k">В цели</span><span class="goal-v">${stats.inGoal} / ${stats.withCal || 0}</span></div>
    <div class="goal-item"><span class="goal-k">Сон ср.</span><span class="goal-v">${sleepTxt}</span></div>
    <div class="goal-item"><span class="goal-k">Цель</span><span class="goal-v">${stats.lo || "?"}–${stats.hi || "?"}</span></div>
  </div>`;
}

export function weekHero(series) {
  const stats = weekGoalStats(series, state.profile.coaching_calorie_target || {});
  const total = stats.withCal || 0;
  const pct = total ? Math.round((stats.inGoal / total) * 100) : 0;
  return `<div class="week-hero">
    <p class="week-hero-kicker">Главный итог недели</p>
    <div class="week-hero-value">${stats.inGoal}<span class="week-hero-of">/${total || 0}</span></div>
    <p class="week-hero-sub">дней в калорийной цели${stats.lo ? ` (${stats.lo}–${stats.hi})` : ""}</p>
    <div class="week-hero-bar" aria-hidden="true"><span style="width:${pct}%"></span></div>
  </div>`;
}

function freshnessLine(d) {
  const parts = [];
  if (d.steps != null) parts.push(`шаги${d.locks?.steps ? " · руч." : ""}`);
  if (d.sleep_min != null) parts.push(`сон${d.locks?.sleep ? " · руч." : ""}`);
  if ((d.body_composition?.weight_kg ?? d.weight_kg) != null) parts.push(`вес${d.locks?.weight ? " · руч." : ""}`);
  if (d.meals?.length) parts.push(`еда ${d.meals.length}`);
  if (d.bp?.length) parts.push(`АД ${d.bp.length}`);
  if (!d.last_synced_at && !parts.length) return "";
  const t = d.last_synced_at
    ? new Date(d.last_synced_at).toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit" })
    : null;
  return t ? `Синхронизация ${t}${parts.length ? `: ${parts.join(" · ")}` : ""}` : parts.join(" · ");
}

function latestBp() {
  return latestBpReading(day().bp);
}

export function renderToday() {
  const d = day();
  const bp = latestBp();
  const totals = nutritionTotals(d.meals);
  const bc = d.body_composition;
  const weightVal = bc?.weight_kg ?? d.weight_kg ?? state.profile.weight_kg_latest ?? "—";
  const target = state.profile.coaching_calorie_target || {};
  let kcalVs = "";
  let goalClass = "goal-pill";
  if (totals.calories && (target.kcal_min || target.kcal_max)) {
    const lo = Number(target.kcal_min || 0);
    const hi = Number(target.kcal_max || lo);
    const cal = Math.round(totals.calories);
    if (cal < lo) { kcalVs = `ниже цели на ${lo - cal} — запас до вечера`; goalClass = "goal-pill warn"; }
    else if (cal > hi) { kcalVs = `выше цели на ${cal - hi}`; goalClass = "goal-pill warn"; }
    else kcalVs = `в цели ${lo}–${hi}`;
  }
  const isEmptyDay = !totals.calories && d.steps == null && d.sleep_min == null && !bp && weightVal === "—";
  const sheet = state.healthDetail ? renderHealthDetail(state.healthDetail, d) : "";
  return `
    <section class="panel stack-gap">
      <div class="panel-head">
        <h2 class="panel-title">Сегодня</h2>
        <p class="panel-sub">${freshnessLine(d) || "Нажмите «Обновить», чтобы подтянуть облако."}</p>
      </div>
      ${sourceStatusCards(d)}
      ${hasManualLocks(d) ? `<button class="btn soft" id="unlock-cloud" type="button">Снова из облака</button>` : ""}
      ${isEmptyDay ? emptyState("День пока пустой", "Подключите источники и нажмите «Обновить».", "refresh", "Обновить данные") : ""}
    </section>
    <section class="panel stack-gap health-panel">
      <div class="panel-head health-head">
        <div>
          <h2 class="panel-title">Здоровье</h2>
          <p class="panel-sub">Сон, активность, пульс, давление, вес · нажмите плитку</p>
        </div>
        <button class="btn soft icon-btn" id="health-add" type="button" aria-label="Добавить измерение" title="Добавить">+</button>
      </div>
      ${renderHealthTiles(d)}
      <button class="health-manage" id="health-manage" type="button">
        <span>Источники и функции здоровья</span>
        <span aria-hidden="true">›</span>
      </button>
    </section>
    <section class="panel stack-gap">
      <div class="panel-head">
        <h2 class="panel-title">День</h2>
        <p class="panel-sub">Питание и состав тела</p>
      </div>
      <div class="cards">
        ${bc && renderBodyMetrics(bc) ? `<div class="card wide"><h2>Состав тела</h2>${renderBodyMetrics(bc)}</div>` : ""}
        <div class="card wide">
          <h2>Еда</h2>
          <div class="value">${Math.round(totals.calories)} ккал</div>
          <div class="sub">Б ${Math.round(totals.protein_g)} · Ж ${Math.round(totals.fat_g)} · У ${Math.round(totals.carbs_g)}</div>
          ${kcalVs ? `<div class="${goalClass}">● ${kcalVs}</div>` : ""}
          <ul class="list">${d.meals.length
            ? d.meals.map((m, i) => {
                const label = `${escapeHtml(MEAL_RU[m.meal_type] || m.meal_type)}: ${escapeHtml(m.name)}`;
                return m.source === "fatsecret"
                  ? `<li><span>${label}</span></li>`
                  : `<li><span>${label}</span><button class="btn ghost" data-del-meal="${i}" type="button">×</button></li>`;
              }).join("")
            : `<li class="empty">Пока пусто — FatSecret + «Обновить»</li>`}</ul>
        </div>
      </div>
    </section>
    <div class="coach-cta">
      <p class="coach-cta-kicker">Главное действие</p>
      <button class="btn primary btn-xl" id="ask-coach" type="button">Отправить день коучу</button>
      <div class="actions compact">
        <button class="btn soft" id="copy-report" type="button">Скопировать отчёт</button>
        <button class="btn ghost" id="share-report" type="button">Поделиться</button>
        <button class="btn ghost" id="refresh-data-tab" type="button">Обновить данные</button>
      </div>
    </div>
    ${sheet}`;
}

export function renderWeek() {
  const series = state.weekSeries?.length ? state.weekSeries : [];
  const target = state.profile.coaching_calorie_target || {};
  const report = state.weekReport || "";
  const axis = series.map((s) => `<span>${s.label}</span>`).join("");
  const empty = !series.some((s) => s.calories != null || s.steps != null || s.sleep_min != null);
  return `
    <section class="panel stack-gap">
      <div class="panel-head">
        <h2 class="panel-title">Неделя</h2>
        <p class="panel-sub">Относительно ${state.date}</p>
      </div>
      ${weekHero(series)}
      ${weekGoalStrip(series)}
      ${empty ? emptyState("Неделя ещё пустая", "Соберите 7 дней одной кнопкой.", "backfill", "Заполнить неделю") : ""}
    </section>
    <div class="card wide lift">
      <div class="week-block"><div class="week-label">Калории</div>${sparkBars(series.map((s) => s.calories), Number(target.kcal_max || 2100))}<div class="week-axis">${axis}</div></div>
      <div class="week-block"><div class="week-label">Шаги</div>${sparkBars(series.map((s) => s.steps), 10000)}<div class="week-axis">${axis}</div></div>
      <div class="week-block"><div class="week-label">Сон</div>${sparkBars(series.map((s) => s.sleep_min), 540)}<div class="week-axis">${axis}</div></div>
      <div class="week-block"><div class="week-label">Вес</div>${sparkBars(series.map((s) => s.weight), null, { relative: true })}<div class="week-axis">${axis}</div></div>
      <div class="week-block"><div class="week-label">АД</div>${sparkBars(series.map((s) => s.bp_sys), null, { relative: true })}<div class="week-axis">${axis}</div></div>
    </div>
    <details class="report-fold lift"><summary>Текст недели для коуча</summary>
      <div class="report">${escapeHtml(report || "Загрузка…")}</div>
    </details>
    <div class="actions">
      <button class="btn primary btn-xl" id="backfill-week" type="button">Заполнить неделю</button>
      <button class="btn soft" id="copy-week-report" type="button">Скопировать неделю</button>
      <button class="btn ghost" id="share-week-report" type="button">Поделиться</button>
    </div>`;
}

export function renderAdd() {
  const d = day();
  return `
    <section class="panel stack-gap">
      <div class="panel-head">
        <h2 class="panel-title">Добавить</h2>
        <p class="panel-sub">Ручные правки перекрывают облако до «Снова из облака»</p>
      </div>
    </section>
    <div class="card wide form lift">
      <h2>Давление</h2>
      <div class="row">
        <input id="sys" inputmode="numeric" placeholder="Сис" />
        <input id="dia" inputmode="numeric" placeholder="Диа" />
        <input id="pulse" inputmode="numeric" placeholder="Пульс" />
      </div>
      <button class="btn primary" id="save-bp" type="button">Записать АД</button>
    </div>
    <div class="card wide form lift">
      <h2>Сон / шаги / вес</h2>
      <label>Сон, минут</label>
      <input id="sleep" inputmode="numeric" value="${d.sleep_min ?? ""}" placeholder="419" />
      <label>Шаги</label>
      <input id="steps" inputmode="numeric" value="${d.steps ?? ""}" placeholder="871" />
      <label>Вес, кг</label>
      <input id="weight" inputmode="decimal" value="${d.weight_kg ?? ""}" placeholder="109.0" />
      <button class="btn primary" id="save-vitals" type="button">Сохранить</button>
      ${hasManualLocks(d) ? `<button class="btn soft" id="unlock-cloud" type="button">Снова из облака</button>` : ""}
    </div>
    <div class="card wide form lift">
      <h2>Еда</h2>
      <select id="meal-type">
        <option value="breakfast">Завтрак</option>
        <option value="lunch">Обед</option>
        <option value="dinner">Ужин</option>
        <option value="snack">Перекус</option>
      </select>
      <input id="meal-name" placeholder="Что ели" />
      <div class="row">
        <input id="meal-grams" inputmode="decimal" placeholder="г" />
        <input id="meal-kcal" inputmode="decimal" placeholder="ккал" />
        <input id="meal-p" inputmode="decimal" placeholder="Б" />
      </div>
      <div class="row">
        <input id="meal-f" inputmode="decimal" placeholder="Ж" />
        <input id="meal-c" inputmode="decimal" placeholder="У" />
        <span></span>
      </div>
      <button class="btn primary" id="save-meal" type="button">Добавить еду</button>
    </div>`;
}

export function renderCoach(formatReport, snapshot) {
  const report = formatReport(snapshot());
  const bubbles = state.chat
    .map((m) => `<div class="bubble ${m.role}">${escapeHtml(m.content)}</div>`)
    .join("");
  return `
    <section class="panel coach-hero stack-gap">
      <div class="panel-head">
        <h2 class="panel-title">Коучу</h2>
        <p class="panel-sub">Сначала действие — отчёт по желанию</p>
      </div>
      <button class="btn primary btn-xl" id="copy-report" type="button">Скопировать отчёт</button>
      <div class="actions compact">
        <button class="btn soft" id="share-report" type="button">Поделиться</button>
        <button class="btn ghost" id="toggle-coach-report" type="button">${state.coachReportOpen ? "Скрыть отчёт" : "Показать отчёт"}</button>
        <button class="btn ghost" id="clear-chat" type="button">Очистить чат</button>
      </div>
    </section>
    ${state.coachReportOpen ? `<div class="report lift">${escapeHtml(report)}</div>` : `<p class="hint lift">Отчёт свёрнут — откройте, если нужно сверить цифры.</p>`}
    <div class="chat lift">${bubbles || emptyState("Пока тишина", "Спросите, что урезать сегодня или как дотянуть белок.")}</div>
    <div class="form card wide lift">
      <textarea id="coach-msg" rows="3" placeholder="Вопрос коучу…"></textarea>
      <button class="btn primary btn-xl" id="send-coach" type="button" ${state.sending ? "disabled" : ""}>${state.sending ? "Отправка…" : "Передать коучу"}</button>
    </div>`;
}

function renderSourcesPane() {
  const cs = state.collectorStatus || {};
  const conn = cs.connections || {};
  const lastSources = cs.last_sources || cs.last_result?.sources || {};
  return `
    ${sourceStatusCards(day())}
    <div class="card wide lift">
      <h2>Статус</h2>
      <div class="badges">
        ${connectionBadge(!!conn.xiaomi?.connected, "Xiaomi")}
        ${connectionBadge(!!conn.fatsecret?.connected, "FatSecret")}
        ${connectionBadge(!!conn.medm?.connected, "MedM")}
      </div>
      <div class="sub" style="margin-top:8px">${cs.running ? `Авто-сбор каждые ${cs.interval_min} мин` : "Авто-сбор не запущен"}</div>
      ${cs.last_result?.collected_at ? `<div class="sub">Последний сбор: ${new Date(cs.last_result.collected_at).toLocaleString("ru-RU")}</div>` : ""}
      ${Object.keys(lastSources).length ? `<div class="sub">${Object.entries(lastSources).map(([k, v]) => sourceLabel(k, v)).join(" · ")}</div>` : ""}
      ${cs.last_error ? `<div class="sub high">${escapeHtml(cs.last_error)}</div>` : ""}
      <div class="actions compact" style="margin-top:10px">
        <button class="btn primary" id="collect-now" type="button">Собрать сейчас</button>
        <button class="btn soft" id="backfill-week-more" type="button">Заполнить неделю</button>
      </div>
    </div>
    <div class="card wide form lift">
      <h2>Xiaomi / Mi Fitness</h2>
      ${conn.xiaomi?.connected ? `<button class="btn ghost" id="disconnect-xiaomi" type="button">Отключить Xiaomi</button>` : ""}
      ${state.xiaomi2fa ? `
        <label>Код 2FA</label>
        <input id="xi-code" placeholder="Код" autocomplete="one-time-code" />
        <button class="btn primary" id="xi-verify" type="button">Подтвердить</button>
      ` : `
        <details>
          <summary>Подключить Xiaomi</summary>
          <input id="xi-user" placeholder="Email / телефон" autocomplete="username" />
          <input id="xi-pass" type="password" placeholder="Пароль" autocomplete="current-password" />
          <button class="btn primary" id="xi-login" type="button">Подключить</button>
          <p class="hint">Или токены:</p>
          <input id="xi-uid" placeholder="userId" />
          <input id="xi-pt" placeholder="passToken" />
          <button class="btn primary" id="xi-tokens" type="button">Сохранить токены</button>
        </details>
      `}
    </div>
    <div class="card wide form lift">
      <h2>FatSecret</h2>
      <p class="hint">${conn.fatsecret?.connected ? "Подключён" : "Для дневника питания"}</p>
      <button class="btn primary" id="fatsecret-connect" type="button">Подключить FatSecret</button>
      ${conn.fatsecret?.connected ? `<button class="btn ghost" id="disconnect-fatsecret" type="button">Отключить</button>` : ""}
      ${state.fatsecretSession ? `
        <label>PIN FatSecret</label>
        <input id="fs-pin" placeholder="PIN" />
        <button class="btn primary" id="fs-verify" type="button">Подтвердить</button>
      ` : ""}
      <div id="fatsecret-status" class="sub"></div>
    </div>
    <div class="card wide form lift">
      <h2>MedM BP</h2>
      <input id="medm-email" placeholder="Email MedM" autocomplete="username" />
      <input id="medm-pass" type="password" placeholder="Пароль" autocomplete="current-password" />
      <button class="btn primary" id="medm-login" type="button">Подключить MedM</button>
      ${conn.medm?.connected ? `<button class="btn ghost" id="disconnect-medm" type="button">Отключить</button>` : ""}
    </div>
    <div class="card wide form lift">
      <h2>Импорт CSV давления</h2>
      <input id="csv-file" type="file" accept=".csv,text/csv,text/plain" />
      <button class="btn primary" id="import-csv" type="button">Импортировать</button>
    </div>`;
}

function renderProfilePane() {
  const t = state.profile.coaching_calorie_target || {};
  return `
    <div class="card wide form lift">
      <h2>Профиль для коуча</h2>
      <p class="hint">Сервер · last-write-wins по updated_at${state.profile.updated_at ? ` · ${new Date(state.profile.updated_at).toLocaleString("ru-RU")}` : ""}</p>
      <label>Рост, см</label>
      <input id="height" inputmode="numeric" value="${state.profile.height_cm ?? ""}" placeholder="165" />
      <label>Лекарства (через запятую)</label>
      <input id="meds" value="${escapeAttr((state.profile.medications || []).join(", "))}" />
      <label>Цель ккал мин–макс · белок</label>
      <div class="row">
        <input id="kcal-min" value="${t.kcal_min ?? 1900}" />
        <input id="kcal-max" value="${t.kcal_max ?? 2100}" />
        <input id="protein" value="${t.protein_g ?? 130}" placeholder="Белок" />
      </div>
      <label>Заметка дня</label>
      <textarea id="notes" rows="2">${escapeAttr(day().notes || "")}</textarea>
      <button class="btn primary" id="save-profile" type="button">Сохранить профиль</button>
    </div>
    <p class="hint">Android: Chrome → «Добавить на главный экран»</p>`;
}

export function renderMore() {
  const pane = state.morePane === "profile" ? "profile" : "sources";
  return `
    <section class="panel stack-gap">
      <div class="panel-head">
        <h2 class="panel-title">Ещё</h2>
        <p class="panel-sub">Источники и профиль — отдельно</p>
      </div>
      <div class="segment" role="tablist" aria-label="Разделы">
        <button type="button" class="segment-btn ${pane === "sources" ? "active" : ""}" data-more-pane="sources" role="tab" aria-selected="${pane === "sources"}">Источники</button>
        <button type="button" class="segment-btn ${pane === "profile" ? "active" : ""}" data-more-pane="profile" role="tab" aria-selected="${pane === "profile"}">Профиль</button>
      </div>
    </section>
    ${pane === "profile" ? renderProfilePane() : renderSourcesPane()}`;
}

export function weekSeriesFromLocal(daysCount = 7) {
  const end = new Date(`${state.date}T12:00:00`);
  const series = [];
  for (let i = daysCount - 1; i >= 0; i--) {
    const d = new Date(end);
    d.setDate(end.getDate() - i);
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
    const dayData = state.days[key] || { meals: [], steps: null, sleep_min: null, weight_kg: null, bp: [], body_composition: null };
    const totals = nutritionTotals(dayData.meals || []);
    const bp = latestBpReading(dayData.bp);
    series.push({
      date: key,
      label: `${String(d.getDate()).padStart(2, "0")}.${String(d.getMonth() + 1).padStart(2, "0")}`,
      calories: totals.calories || null,
      steps: dayData.steps,
      weight: dayData.body_composition?.weight_kg ?? dayData.weight_kg,
      bp_sys: bp?.systolic ?? null,
      sleep_min: dayData.sleep_min,
    });
  }
  return series;
}
