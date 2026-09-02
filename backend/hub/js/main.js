import {
  MEAL_RU,
  applySnapshotToDay,
  clearManualLocks,
  defaultProfile,
  latestBpReading,
  mergeProfilesLww,
  nutritionTotals,
  todayIso,
} from "./logic.js";
import { ApiError, healthApi } from "./api.js";
import { state, day, dayFor, persistLocal, saveJson, STORAGE_DAYS, STORAGE_PROFILE, STORAGE_CHAT } from "./state.js";
import {
  toast,
  val,
  captureFocus,
  restoreFocus,
  setOfflineBanner,
  setSkeleton,
  setCompactStage,
  updateTabA11y,
  showPinGate,
  setRefreshStatus,
  escapeHtml,
} from "./ui.js";
import {
  renderToday,
  renderWeek,
  renderAdd,
  renderCoach,
  renderMore,
  weekSeriesFromLocal,
} from "./render.js";

function bodyCompositionReportLines(bc) {
  if (!bc) return [];
  const lines = [];
  if (bc.weight_kg != null) lines.push(`Вес: ${bc.weight_kg} кг`);
  const parts = [];
  if (bc.bmi != null) parts.push(`ИМТ ${bc.bmi}`);
  if (bc.body_fat_pct != null) parts.push(`жир ${bc.body_fat_pct}%`);
  if (bc.muscle_kg != null) parts.push(`мышцы ${bc.muscle_kg} кг`);
  if (bc.water_pct != null) parts.push(`вода ${bc.water_pct}%`);
  if (bc.bone_kg != null) parts.push(`кость ${bc.bone_kg} кг`);
  if (bc.visceral_fat != null) parts.push(`висц. жир ${bc.visceral_fat}`);
  if (bc.body_age != null) parts.push(`возраст тела ${bc.body_age}`);
  if (bc.bmr_kcal != null) parts.push(`BMR ${bc.bmr_kcal} ккал`);
  if (bc.body_score != null) parts.push(`оценка ${bc.body_score}`);
  if (bc.heart_rate != null) parts.push(`пульс ${bc.heart_rate}`);
  if (bc.skeletal_muscle_kg != null) parts.push(`скел. мышцы ${bc.skeletal_muscle_kg} кг`);
  if (bc.protein_kg != null) parts.push(`белок ${bc.protein_kg} кг`);
  if (parts.length) lines.push(`Состав тела: ${parts.join(", ")}`);
  return lines;
}

function latestBp() {
  return latestBpReading(day().bp);
}

function avgBp(daysCount = 7) {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - daysCount);
  const all = Object.values(state.days).flatMap((d) => d.bp || []);
  const window = all.filter((r) => new Date(r.measured_at) >= cutoff);
  if (!window.length) return null;
  const sys = window.reduce((s, r) => s + Number(r.systolic), 0) / window.length;
  const dia = window.reduce((s, r) => s + Number(r.diastolic), 0) / window.length;
  return { systolic: Math.round(sys), diastolic: Math.round(dia) };
}

function snapshot() {
  const d = day();
  const totals = nutritionTotals(d.meals);
  const mealsByType = {};
  for (const meal of d.meals) {
    const key = meal.meal_type || "snack";
    mealsByType[key] ??= { meal_type: key, items: [] };
    mealsByType[key].items.push({
      name: meal.name,
      grams: Number(meal.grams || 0),
      calories: Number(meal.calories || 0),
      protein_g: Number(meal.protein || 0),
      fat_g: Number(meal.fat || 0),
      carbs_g: Number(meal.carbs || 0),
    });
  }
  const bp = latestBp();
  return {
    date: d.date,
    generated_at: new Date().toISOString(),
    profile: {
      height_cm: Number(state.profile.height_cm),
      weight_kg_latest: d.weight_kg ?? state.profile.weight_kg_latest,
      medications: state.profile.medications || [],
      coaching_calorie_target: state.profile.coaching_calorie_target,
    },
    nutrition: { ...totals, meals: Object.values(mealsByType) },
    blood_pressure: { readings_today: d.bp, latest: bp, avg_7d: avgBp(7) },
    activity: d.steps == null ? undefined : { steps: Number(d.steps), source: "manual" },
    sleep: d.sleep_min == null ? undefined : {
      duration_min: Number(d.sleep_min),
      total_min: Number(d.sleep_min),
      deep_min: d.sleep_deep_min,
      light_min: d.sleep_light_min,
      rem_min: d.sleep_rem_min,
      source: "manual",
    },
    body_composition: d.body_composition || (d.weight_kg == null ? undefined : { weight_kg: Number(d.weight_kg) }),
    weight: d.body_composition ? {
      kg: d.body_composition.weight_kg,
      bmi: d.body_composition.bmi,
      bodyFat: d.body_composition.body_fat_pct,
      muscle: d.body_composition.muscle_kg,
      water: d.body_composition.water_pct,
      bone: d.body_composition.bone_kg,
      visceralFat: d.body_composition.visceral_fat,
      bodyAge: d.body_composition.body_age,
      bmr: d.body_composition.bmr_kcal,
      bodyScore: d.body_composition.body_score,
      heartRate: d.body_composition.heart_rate,
      skeletalMuscle: d.body_composition.skeletal_muscle_kg,
      protein: d.body_composition.protein_kg,
      source: d.body_composition.source,
    } : (d.weight_kg == null ? undefined : { kg: Number(d.weight_kg) }),
    workouts: d.workouts || [],
    notes: d.notes || "",
  };
}

function formatReport(snap) {
  const lines = [`Дата: ${snap.date}`];
  const latest = snap.blood_pressure?.latest;
  if (latest) {
    let line = `АД: ${latest.systolic}/${latest.diastolic}`;
    if (latest.pulse) line += `, пульс ${latest.pulse}`;
    const avg = snap.blood_pressure.avg_7d;
    if (avg) line += `, avg 7d: ${avg.systolic}/${avg.diastolic}`;
    lines.push(line);
  }
  if (snap.sleep?.duration_min || snap.sleep?.total_min) {
    const mins = snap.sleep.duration_min || snap.sleep.total_min;
    const h = Math.floor(mins / 60);
    const m = mins % 60;
    let line = `Сон: ${h}h${String(m).padStart(2, "0")}`;
    const stages = [];
    if (snap.sleep.deep_min != null) stages.push(`глубокий ${snap.sleep.deep_min}м`);
    if (snap.sleep.light_min != null) stages.push(`лёгкий ${snap.sleep.light_min}м`);
    if (snap.sleep.rem_min != null) stages.push(`REM ${snap.sleep.rem_min}м`);
    if (stages.length) line += ` (${stages.join(", ")})`;
    lines.push(line);
  }
  if (snap.activity?.steps != null) lines.push(`Шаги: ${snap.activity.steps}`);
  const workouts = snap.workouts || [];
  if (workouts.length) {
    const bits = workouts.map((w) => {
      const mins = w.duration_min ? `${w.duration_min} мин` : "";
      const cal = w.calories ? `${w.calories} ккал` : "";
      const hr = w.avg_hr ? `пульс ${w.avg_hr}` : "";
      return [w.name || "Тренировка", mins, cal, hr].filter(Boolean).join(", ");
    });
    lines.push(`Тренировки: ${bits.join("; ")}`);
  }
  const bc = snap.body_composition || null;
  for (const line of bodyCompositionReportLines(bc)) lines.push(line);
  if (!bc) {
    const weight = snap.profile?.weight_kg_latest;
    if (weight != null) lines.push(`Вес: ${weight}`);
  }
  const n = snap.nutrition || {};
  const mealBits = (n.meals || [])
    .map((meal) => {
      const names = (meal.items || []).map((i) => i.name).filter(Boolean);
      return names.length ? `${MEAL_RU[meal.meal_type] || meal.meal_type}: ${names.join(", ")}` : "";
    })
    .filter(Boolean);
  if (n.calories || mealBits.length) {
    lines.push(`Еда: ${Math.round(n.calories || 0)} kcal${mealBits.length ? ` (${mealBits.join("; ")})` : ""}`);
    if (n.protein_g || n.fat_g || n.carbs_g) {
      lines.push(`КБЖУ: Б ${Math.round(n.protein_g || 0)} · Ж ${Math.round(n.fat_g || 0)} · У ${Math.round(n.carbs_g || 0)}`);
    }
    const t0 = snap.profile?.coaching_calorie_target || {};
    if (n.calories && (t0.kcal_min || t0.kcal_max)) {
      const lo = Number(t0.kcal_min || 0);
      const hi = Number(t0.kcal_max || lo);
      const cal = Math.round(n.calories);
      if (cal < lo) lines.push(`Vs цель: ниже на ${lo - cal} ккал (цель ${lo}–${hi})`);
      else if (cal > hi) lines.push(`Vs цель: выше на ${cal - hi} ккал (цель ${lo}–${hi})`);
      else lines.push(`Vs цель: в диапазоне ${lo}–${hi} ккал`);
    }
  }
  const meds = snap.profile?.medications || [];
  if (meds.length) lines.push(`Лекарства: ${meds.join(", ")}`);
  const t = snap.profile?.coaching_calorie_target || {};
  if (t.kcal_min || t.kcal_max) {
    lines.push(`Рабочая цель: ${t.kcal_min}–${t.kcal_max} ккал${t.protein_g ? `, Б ${t.protein_g}` : ""}`);
  }
  if (snap.notes) lines.push(`Заметки: ${snap.notes}`);
  return lines.join("\n");
}

function handleApiError(err, fallback = "Ошибка") {
  if (err instanceof ApiError) {
    state.lastError = err.message;
    if (err.offline) {
      state.online = false;
      setOfflineBanner(false);
    }
    if (err.status === 401 && state.pinRequired) {
      state.unlocked = false;
      showPinGate(true);
      toast("Нужен PIN");
      return;
    }
    toast(err.message || fallback);
    setRefreshStatus(err.message || fallback, true);
    return;
  }
  toast(String(err?.message || fallback));
}

async function syncServer() {
  try {
    await healthApi.sync(snapshot());
    state.online = true;
    setOfflineBanner(true);
  } catch (err) {
    if (err instanceof ApiError && err.offline) {
      state.online = false;
      setOfflineBanner(false);
    }
  }
}

function persist() {
  persistLocal();
  syncServer();
}

function render() {
  const focus = captureFocus();
  setCompactStage(state.tab !== "today");
  updateTabA11y(state.tab);
  const view = document.getElementById("view");
  if (!view) return;
  if (state.tab === "add") view.innerHTML = renderAdd();
  else if (state.tab === "week") view.innerHTML = renderWeek();
  else if (state.tab === "coach") view.innerHTML = renderCoach(formatReport, snapshot);
  else if (state.tab === "more") view.innerHTML = renderMore();
  else view.innerHTML = renderToday();
  bind();
  restoreFocus(focus);
}

function setRefreshBusy(busy) {
  state.refreshing = busy;
  setSkeleton(busy);
  const buttons = [
    ...["refresh-data", "refresh-data-tab", "collect-now", "backfill-week", "backfill-week-more"]
      .map((id) => document.getElementById(id))
      .filter(Boolean),
    ...document.querySelectorAll("[data-action='refresh'], [data-action='backfill']"),
  ];
  for (const btn of buttons) {
    btn.disabled = busy;
    const id = btn.id;
    const action = btn.dataset.action;
    if (id === "refresh-data") btn.textContent = busy ? "…" : "Обновить";
    else if (id === "refresh-data-tab" || action === "refresh") btn.textContent = busy ? "Обновляю…" : "Обновить данные";
    else if (id === "collect-now") btn.textContent = busy ? "Обновляю…" : "Собрать сейчас";
    else if (id === "backfill-week" || id === "backfill-week-more" || action === "backfill") {
      btn.textContent = busy ? "Собираю…" : "Заполнить неделю";
    }
  }
}

function summarizeCollectedSnapshot(snap) {
  const parts = [];
  const steps = snap.steps?.count ?? snap.activity?.steps;
  if (steps != null) parts.push(`шаги ${steps}`);
  const mealCount = (snap.nutrition?.meals || []).reduce((n, m) => n + (m.items?.length || 0), 0);
  const mealKcal = snap.nutrition?.calories;
  if (mealCount) parts.push(mealKcal ? `еда ${mealCount} (${Math.round(mealKcal)} ккал)` : `еда ${mealCount}`);
  const bpCount = snap.blood_pressure?.readings_today?.length || 0;
  if (bpCount) parts.push(`АД ${bpCount}`);
  const workoutCount = snap.workouts?.length || 0;
  if (workoutCount) parts.push(`тренировки ${workoutCount}`);
  if (snap.weight?.kg != null) parts.push(`вес ${snap.weight.kg} кг`);
  const sources = snap.sources_status || {};
  const failed = Object.entries(sources)
    .filter(([, s]) => s && s.ok === false && s.error !== "not_connected")
    .map(([k]) => k);
  if (failed.length) parts.push(`ошибки: ${failed.join(", ")}`);
  return parts.length ? parts.join(", ") : "нет записей за день";
}

async function fetchCollectorStatus() {
  try {
    state.collectorStatus = await healthApi.collectorStatus();
    state.online = true;
    setOfflineBanner(true);
  } catch (err) {
    if (err instanceof ApiError && err.offline) {
      state.online = false;
      setOfflineBanner(false);
    }
  }
}

async function loadWeek(returnOnly = false) {
  try {
    const data = await healthApi.week(state.date, 7);
    if (data.profile) {
      const merged = mergeProfilesLww(state.profile, data.profile);
      state.profile = merged.profile;
      saveJson(STORAGE_PROFILE, state.profile);
      if (merged.shouldPush) await saveServerProfile(false);
    }
    state.weekReport = data.report || "";
    state.weekSeries = (data.days || []).map((snap) => {
      const d = new Date(`${snap.date}T12:00:00`);
      const nutrition = snap.nutrition || {};
      const bp = snap.blood_pressure?.latest || {};
      const sleep = snap.sleep || {};
      return {
        date: snap.date,
        label: `${String(d.getDate()).padStart(2, "0")}.${String(d.getMonth() + 1).padStart(2, "0")}`,
        calories: nutrition.calories ?? null,
        steps: snap.steps?.count ?? snap.activity?.steps ?? null,
        weight: snap.weight?.kg ?? snap.body_composition?.weight_kg ?? null,
        bp_sys: bp.systolic ?? null,
        sleep_min: sleep.total_min ?? sleep.duration_min ?? null,
      };
    });
    state.online = true;
    setOfflineBanner(true);
    if (!returnOnly && state.tab === "week") render();
    return state.weekReport;
  } catch (err) {
    state.weekSeries = weekSeriesFromLocal(7);
    state.weekReport = "Офлайн — локальные данные";
    if (err instanceof ApiError && err.offline) setOfflineBanner(false);
    return state.weekReport;
  }
}

async function loadServerDay(options = false) {
  const opts = typeof options === "boolean" ? { autoCollect: options } : options;
  const { autoCollect = false, force = false } = opts;
  try {
    const data = await healthApi.day(state.date);
    const snap = data.snapshot || {};
    if (autoCollect && !snap.generated_at && state.date <= todayIso()) {
      toast("Загружаю данные за этот день…");
      try {
        await healthApi.collectNow(state.date);
        return loadServerDay({ force: true });
      } catch { /* offline */ }
    }
    const d = day();
    const serverAt = snap.generated_at ? Date.parse(snap.generated_at) : NaN;
    const localAt = d.last_synced_at ? Date.parse(d.last_synced_at) : NaN;
    const serverNewer = Number.isFinite(serverAt)
      && (!Number.isFinite(localAt) || serverAt > localAt);
    applySnapshotToDay(d, snap, {
      force: force || serverNewer,
      onWeight: (kg) => { state.profile.weight_kg_latest = kg; },
    });
    saveJson(STORAGE_DAYS, state.days);
    state.online = true;
    setOfflineBanner(true);
    render();
    return true;
  } catch (err) {
    if (err instanceof ApiError && err.status === 401) handleApiError(err);
    return false;
  }
}

async function refreshData() {
  if (state.refreshing) return;
  setRefreshBusy(true);
  setRefreshStatus(`Сбор данных за ${state.date}…`);
  toast(`Обновляю ${state.date}…`);
  try {
    const snap = await healthApi.collectNow(state.date);
    applySnapshotToDay(day(), snap, {
      force: true,
      onWeight: (kg) => { state.profile.weight_kg_latest = kg; },
    });
    // Backend also re-collects yesterday when refreshing today; reload week/history.
    if (state.date === todayIso()) {
      const y = new Date(`${state.date}T12:00:00`);
      y.setDate(y.getDate() - 1);
      const yKey = `${y.getFullYear()}-${String(y.getMonth() + 1).padStart(2, "0")}-${String(y.getDate()).padStart(2, "0")}`;
      try {
        const yData = await healthApi.day(yKey);
        applySnapshotToDay(dayFor(yKey), yData.snapshot || {}, {
          force: true,
          onWeight: (kg) => { state.profile.weight_kg_latest = kg; },
        });
      } catch { /* offline */ }
    }
    saveJson(STORAGE_DAYS, state.days);
    await fetchCollectorStatus();
    if (state.tab === "week") await loadWeek();
    const t = new Date().toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit" });
    const summary = summarizeCollectedSnapshot(snap);
    setRefreshStatus(`Обновлено в ${t}: ${summary}`);
    toast(`Данные обновлены: ${summary}`);
    state.online = true;
    setOfflineBanner(true);
    render();
  } catch (err) {
    handleApiError(err, "Ошибка сбора");
  } finally {
    setRefreshBusy(false);
  }
}

async function backfillWeek() {
  if (state.refreshing) return;
  setRefreshBusy(true);
  setRefreshStatus("Собираю 7 дней…");
  toast("Заполняю неделю…");
  try {
    const data = await healthApi.backfill(7);
    const ok = (data.results || []).filter((x) => x.ok).length;
    await loadServerDay({ force: true });
    await loadWeek();
    await fetchCollectorStatus();
    setRefreshStatus(`Неделя: собрано ${ok} из ${(data.results || []).length} дней`);
    toast(`Неделя обновлена (${ok} дн.)`);
    render();
  } catch (err) {
    handleApiError(err, "Ошибка backfill");
  } finally {
    setRefreshBusy(false);
  }
}

async function saveServerProfile(showToast = true) {
  try {
    state.profile.updated_at = new Date().toISOString();
    const data = await healthApi.putProfile({
      height_cm: state.profile.height_cm,
      weight_kg_latest: state.profile.weight_kg_latest,
      medications: state.profile.medications,
      coaching_calorie_target: state.profile.coaching_calorie_target,
      updated_at: state.profile.updated_at,
    });
    if (data.profile) state.profile = { ...defaultProfile(), ...data.profile };
    saveJson(STORAGE_PROFILE, state.profile);
    if (showToast) toast("Профиль сохранён на сервере");
    return true;
  } catch (err) {
    if (showToast) toast("Сохранено локально (сервер недоступен)");
    return false;
  }
}

async function loadServerProfile() {
  try {
    const data = await healthApi.profile();
    if (!data.profile) return;
    const merged = mergeProfilesLww(state.profile, data.profile);
    state.profile = merged.profile;
    saveJson(STORAGE_PROFILE, state.profile);
    if (merged.shouldPush) await saveServerProfile(false);
  } catch (err) {
    if (err instanceof ApiError && err.status === 401) handleApiError(err);
  }
}

async function checkPinGate() {
  try {
    const data = await healthApi.gate();
    state.pinRequired = !!data.pin_required;
    if (!state.pinRequired) {
      state.unlocked = true;
      showPinGate(false);
      return;
    }
    // Cookie session is source of truth; probe a protected endpoint.
    try {
      await healthApi.profile();
      state.unlocked = true;
      showPinGate(false);
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        state.unlocked = false;
        showPinGate(true);
      } else {
        state.unlocked = true;
        showPinGate(false);
      }
    }
  } catch {
    state.unlocked = true;
    showPinGate(false);
  }
}

async function submitPin() {
  const pin = val("hub-pin");
  if (!pin) return toast("Введите PIN");
  try {
    await healthApi.unlock(pin);
    state.unlocked = true;
    showPinGate(false);
    toast("Доступ открыт");
    await loadServerProfile();
    await fetchCollectorStatus();
    await loadServerDay();
    render();
  } catch (err) {
    handleApiError(err, "Неверный PIN");
  }
}

async function shareText(text, title = "Отчёт коучу") {
  if (navigator.share) {
    try {
      await navigator.share({ title, text });
      return true;
    } catch { /* cancel */ }
  }
  try {
    await navigator.clipboard.writeText(text);
    toast("Скопировано — вставьте коучу");
    return true;
  } catch {
    prompt("Скопируйте отчёт", text);
    return false;
  }
}

async function copyReport() {
  try {
    await navigator.clipboard.writeText(formatReport(snapshot()));
    toast("Отчёт скопирован");
  } catch {
    prompt("Скопируйте отчёт", formatReport(snapshot()));
  }
}

async function shareReport() {
  await shareText(formatReport(snapshot()));
}

async function copyWeekReport() {
  const text = state.weekReport || (await loadWeek(true)) || "";
  if (!text) return toast("Нет данных за неделю");
  try {
    await navigator.clipboard.writeText(text);
    toast("Недельный отчёт скопирован");
  } catch {
    prompt("Скопируйте отчёт", text);
  }
}

async function shareWeekReport() {
  const text = state.weekReport || (await loadWeek(true)) || "";
  if (!text) return toast("Нет данных за неделю");
  await shareText(text, "Неделя для коуча");
}

async function sendCoach() {
  const message = val("coach-msg") || "Что улучшить по этому дню?";
  state.chat.push({ role: "user", content: message });
  state.sending = true;
  persist();
  render();
  try {
    if (!state.weekReport) await loadWeek(true);
    const history = state.chat.slice(0, -1).map((m) => ({ role: m.role, content: m.content }));
    const data = await healthApi.coachChat({
      message,
      snapshot: snapshot(),
      history,
      week_report: state.weekReport || "",
    });
    state.chat.push({ role: "assistant", content: data.reply || "Нет ответа" });
    state.online = true;
  } catch (err) {
    state.chat.push({
      role: "assistant",
      content: `Сеть недоступна. Отчёт всё равно можно скопировать.\n${err.message || err}`,
    });
  }
  state.sending = false;
  persist();
  render();
}

function parseCitizenCsv(text) {
  const lines = text.replace(/^\uFEFF/, "").trim().split(/\r?\n/);
  if (!lines.length) return [];
  const delim = (lines[0].match(/;/g) || []).length > (lines[0].match(/,/g) || []).length ? ";" : ",";
  const header = lines[0].split(delim).map((h) => h.trim().toLowerCase());
  const idx = (names) => header.findIndex((h) => names.some((n) => h === n || h.startsWith(n)));
  const dateI = idx(["дата", "date"]);
  const timeI = idx(["время", "time"]);
  const sysI = idx(["сис", "systolic", "sys"]);
  const diaI = idx(["диа", "diastolic", "dia"]);
  const pulseI = idx(["пульс", "pulse"]);
  const out = [];
  for (let i = 1; i < lines.length; i++) {
    const cols = lines[i].split(delim);
    const date = (cols[dateI] || "").trim();
    const time = (cols[timeI] || "00:00").trim();
    const systolic = Number(String(cols[sysI] || "").replace(/\D/g, ""));
    const diastolic = Number(String(cols[diaI] || "").replace(/\D/g, ""));
    if (!date || !systolic || !diastolic) continue;
    let isoDate = date;
    const dmy = date.match(/^(\d{2})\.(\d{2})\.(\d{4})$/);
    if (dmy) isoDate = `${dmy[3]}-${dmy[2]}-${dmy[1]}`;
    out.push({
      date: isoDate,
      measured_at: `${isoDate}T${time.length === 5 ? time + ":00" : time}`,
      systolic,
      diastolic,
      pulse: pulseI >= 0 && cols[pulseI] ? Number(String(cols[pulseI]).replace(/\D/g, "")) : null,
      source: "csv",
    });
  }
  return out;
}

async function importCsv() {
  const file = document.getElementById("csv-file")?.files?.[0];
  if (!file) return toast("Выберите CSV файл");
  const text = await file.text();
  try { await healthApi.importCsv(text); } catch { /* local still */ }
  const rows = parseCitizenCsv(text);
  for (const row of rows) dayFor(row.date).bp.push(row);
  persist();
  toast(`Импортировано ${rows.length} измерений`);
  render();
}

async function disconnectSource(source) {
  if (!confirm(`Отключить ${source}?`)) return;
  try {
    await healthApi.disconnect(source);
    toast(`${source} отключён`);
    await fetchCollectorStatus();
    render();
  } catch (err) {
    handleApiError(err);
  }
}

async function xiaomiLogin() {
  const username = val("xi-user");
  const password = val("xi-pass");
  if (!username || !password) return toast("Введите логин и пароль Xiaomi");
  toast("Подключаюсь к Xiaomi…");
  try {
    const data = await healthApi.xiaomiLogin({ username, password });
    if (data.status === "2fa_required") {
      state.xiaomi2fa = data.session_id;
      toast("Код отправлен — введите ниже");
      render();
      return;
    }
    state.xiaomi2fa = null;
    toast("Xiaomi подключён");
    await fetchCollectorStatus();
    await refreshData();
  } catch (err) {
    handleApiError(err);
  }
}

async function xiaomiVerify() {
  const code = val("xi-code");
  if (!code || !state.xiaomi2fa) return toast("Введите код");
  try {
    await healthApi.xiaomiVerify({ session_id: state.xiaomi2fa, code });
    state.xiaomi2fa = null;
    toast("Xiaomi подтверждён");
    await fetchCollectorStatus();
    await refreshData();
  } catch (err) {
    handleApiError(err);
  }
}

async function xiaomiSetTokens() {
  const userId = val("xi-uid");
  const passToken = val("xi-pt");
  if (!userId || !passToken) return toast("Нужны userId и passToken");
  try {
    await healthApi.xiaomiTokens({ user_id: userId, pass_token: passToken });
    toast("Токены сохранены");
    await fetchCollectorStatus();
    await refreshData();
  } catch (err) {
    handleApiError(err);
  }
}

async function fatsecretConnect() {
  try {
    const data = await healthApi.fatsecretConnect();
    state.fatsecretSession = data.session_id;
    if (data.authorize_url) window.open(data.authorize_url, "_blank");
    toast("Откройте FatSecret и введите PIN");
    render();
  } catch (err) {
    handleApiError(err);
  }
}

async function fatsecretVerify() {
  const pin = val("fs-pin");
  if (!pin || !state.fatsecretSession) return toast("Нужен PIN");
  try {
    await healthApi.fatsecretVerify({ session_id: state.fatsecretSession, pin });
    state.fatsecretSession = null;
    toast("FatSecret подключён");
    await fetchCollectorStatus();
    await refreshData();
  } catch (err) {
    handleApiError(err);
  }
}

async function medmLogin() {
  const email = val("medm-email");
  const password = val("medm-pass");
  if (!email || !password) return toast("Введите email и пароль MedM");
  try {
    await healthApi.medmLogin({ email, password });
    const passEl = document.getElementById("medm-pass");
    if (passEl) passEl.value = "";
    toast("MedM подключён");
    await fetchCollectorStatus();
    await refreshData();
  } catch (err) {
    handleApiError(err);
  }
}

function bind() {
  document.getElementById("copy-report")?.addEventListener("click", copyReport);
  document.getElementById("share-report")?.addEventListener("click", shareReport);
  document.getElementById("copy-week-report")?.addEventListener("click", copyWeekReport);
  document.getElementById("share-week-report")?.addEventListener("click", shareWeekReport);
  document.getElementById("clear-chat")?.addEventListener("click", () => {
    state.chat = [];
    persist();
    toast("Чат очищен");
    render();
  });
  document.getElementById("toggle-coach-report")?.addEventListener("click", () => {
    state.coachReportOpen = !state.coachReportOpen;
    render();
  });
  document.getElementById("ask-coach")?.addEventListener("click", () => {
    state.tab = "coach";
    render();
  });
  document.querySelectorAll("[data-more-pane]").forEach((btn) => {
    btn.addEventListener("click", () => {
      state.morePane = btn.dataset.morePane;
      render();
    });
  });
  document.getElementById("save-bp")?.addEventListener("click", async () => {
    const systolic = Number(val("sys"));
    const diastolic = Number(val("dia"));
    const pulse = val("pulse") ? Number(val("pulse")) : null;
    if (!systolic || !diastolic) return toast("Нужны систол и диастол");
    const now = new Date();
    const iso = new Date(now.getTime() - now.getTimezoneOffset() * 60000).toISOString().slice(0, 19);
    const reading = { measured_at: iso, systolic, diastolic, pulse, source: "manual" };
    day().bp.push(reading);
    persist();
    try { await healthApi.bloodPressure(reading); } catch { /* offline */ }
    toast("АД записано");
    render();
  });
  document.getElementById("save-vitals")?.addEventListener("click", () => {
    const d = day();
    d.locks = d.locks || { steps: false, sleep: false, weight: false };
    if (val("sleep")) { d.sleep_min = Number(val("sleep")); d.locks.sleep = true; }
    if (val("steps")) { d.steps = Number(val("steps")); d.locks.steps = true; }
    if (val("weight")) {
      d.weight_kg = Number(val("weight").replace(",", "."));
      state.profile.weight_kg_latest = d.weight_kg;
      d.locks.weight = true;
    }
    persist();
    toast("Сохранено (ручные правки защищены)");
    render();
  });
  document.getElementById("save-meal")?.addEventListener("click", () => {
    const name = val("meal-name");
    if (!name) return toast("Напишите, что ели");
    day().meals.push({
      meal_type: document.getElementById("meal-type").value,
      name,
      grams: Number(val("meal-grams") || 0),
      calories: Number(val("meal-kcal") || 0),
      protein: Number(val("meal-p") || 0),
      fat: Number(val("meal-f") || 0),
      carbs: Number(val("meal-c") || 0),
      source: "manual",
    });
    persist();
    toast("Еда добавлена");
    render();
  });
  document.querySelectorAll("[data-del-meal]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const idx = Number(btn.dataset.delMeal);
      const meal = day().meals[idx];
      if (meal?.source === "fatsecret") {
        toast("Это блюдо из FatSecret — измените дневник там");
        return;
      }
      day().meals.splice(idx, 1);
      persist();
      render();
    });
  });
  document.getElementById("send-coach")?.addEventListener("click", sendCoach);
  document.getElementById("save-profile")?.addEventListener("click", async () => {
    const height = val("height");
    state.profile.height_cm = height ? Number(height) : null;
    state.profile.medications = val("meds").split(",").map((s) => s.trim()).filter(Boolean);
    state.profile.coaching_calorie_target = {
      kcal_min: Number(val("kcal-min") || 1900),
      kcal_max: Number(val("kcal-max") || 2100),
      protein_g: Number(val("protein") || 130),
    };
    day().notes = val("notes");
    persistLocal();
    await saveServerProfile(true);
  });
  document.getElementById("unlock-cloud")?.addEventListener("click", async () => {
    clearManualLocks(day());
    persist();
    toast("Ручные правки сняты — тяну облако…");
    await refreshData();
  });
  document.getElementById("import-csv")?.addEventListener("click", importCsv);
  document.getElementById("collect-now")?.addEventListener("click", refreshData);
  document.getElementById("backfill-week")?.addEventListener("click", backfillWeek);
  document.getElementById("backfill-week-more")?.addEventListener("click", backfillWeek);
  document.getElementById("xi-login")?.addEventListener("click", xiaomiLogin);
  document.getElementById("xi-verify")?.addEventListener("click", xiaomiVerify);
  document.getElementById("xi-tokens")?.addEventListener("click", xiaomiSetTokens);
  document.getElementById("medm-login")?.addEventListener("click", medmLogin);
  document.getElementById("fatsecret-connect")?.addEventListener("click", fatsecretConnect);
  document.getElementById("fs-verify")?.addEventListener("click", fatsecretVerify);
  document.getElementById("disconnect-xiaomi")?.addEventListener("click", () => disconnectSource("xiaomi"));
  document.getElementById("disconnect-fatsecret")?.addEventListener("click", () => disconnectSource("fatsecret"));
  document.getElementById("disconnect-medm")?.addEventListener("click", () => disconnectSource("medm"));
}

function wireShell() {
  document.getElementById("hub-pin-go")?.addEventListener("click", submitPin);
  document.getElementById("hub-pin")?.addEventListener("keydown", (e) => {
    if (e.key === "Enter") submitPin();
  });
  const dateEl = document.getElementById("date");
  if (dateEl) {
    dateEl.value = state.date;
    dateEl.addEventListener("change", async (e) => {
      state.date = e.target.value || todayIso();
      await loadServerDay(true);
      if (state.tab === "week") await loadWeek();
      render();
    });
  }
  document.body.addEventListener("click", (e) => {
    const t = e.target?.closest?.("button, [data-action]");
    if (!t) return;
    const id = t.id;
    const action = t.dataset?.action;
    if (id === "refresh-data" || id === "refresh-data-tab" || action === "refresh") {
      e.preventDefault();
      refreshData();
    } else if (action === "backfill") {
      e.preventDefault();
      backfillWeek();
    }
  });
  document.querySelectorAll(".tabs button").forEach((btn) => {
    btn.addEventListener("click", async () => {
      state.tab = btn.dataset.tab;
      if (state.tab === "week") await loadWeek();
      render();
    });
  });
  window.addEventListener("online", () => {
    state.online = true;
    setOfflineBanner(true);
    toast("Снова онлайн");
  });
  window.addEventListener("offline", () => {
    state.online = false;
    setOfflineBanner(false);
  });

  // Pull-to-refresh lite: overscroll gesture on touch
  let touchStartY = 0;
  document.addEventListener("touchstart", (e) => {
    touchStartY = e.touches[0]?.clientY || 0;
  }, { passive: true });
  document.addEventListener("touchend", (e) => {
    const y = e.changedTouches[0]?.clientY || 0;
    if (window.scrollY <= 0 && y - touchStartY > 90 && !state.refreshing) {
      refreshData();
    }
  }, { passive: true });
}

async function boot() {
  wireShell();
  if (!state.online) setOfflineBanner(false);
  await checkPinGate();
  if (state.pinRequired && !state.unlocked) {
    render();
    return;
  }
  await loadServerProfile();
  await fetchCollectorStatus();
  await loadServerDay();
  render();
}

const swUrl = `sw.js?v=${encodeURIComponent(state.assetVersion)}`;
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register(swUrl).then((reg) => {
    reg.update().catch(() => {});
    navigator.serviceWorker.addEventListener("controllerchange", () => {
      toast("Обновление установлено — перезагрузка…");
      window.location.reload();
    });
  }).catch(() => {});
}

boot();
