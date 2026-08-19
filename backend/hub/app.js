const STORAGE_DAYS = "hub.days.v1";
const STORAGE_PROFILE = "hub.profile.v1";
const STORAGE_CHAT = "hub.chat.v1";

const MEAL_RU = {
  breakfast: "Завтрак",
  lunch: "Обед",
  dinner: "Ужин",
  snack: "Перекус",
};

const defaultProfile = () => ({
  height_cm: 165,
  weight_kg_latest: 109,
  medications: ["Edarbi 80"],
  coaching_calorie_target: {
    kcal_min: 1900,
    kcal_max: 2100,
    protein_g: 130,
  },
});

const emptyDay = (date) => ({
  date,
  meals: [],
  bp: [],
  sleep_min: null,
  steps: null,
  weight_kg: null,
  notes: "",
});

function loadJson(key, fallback) {
  try {
    const raw = localStorage.getItem(key);
    return raw ? JSON.parse(raw) : fallback;
  } catch {
    return fallback;
  }
}

function saveJson(key, value) {
  localStorage.setItem(key, JSON.stringify(value));
}

function todayIso() {
  const d = new Date();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${d.getFullYear()}-${m}-${day}`;
}

const state = {
  date: todayIso(),
  tab: "today",
  days: loadJson(STORAGE_DAYS, {}),
  profile: { ...defaultProfile(), ...loadJson(STORAGE_PROFILE, {}) },
  chat: loadJson(STORAGE_CHAT, []),
  sending: false,
  collectorStatus: {},
  xiaomi2fa: null,
};

function day() {
  if (!state.days[state.date]) state.days[state.date] = emptyDay(state.date);
  return state.days[state.date];
}

function persist() {
  saveJson(STORAGE_DAYS, state.days);
  saveJson(STORAGE_PROFILE, state.profile);
  saveJson(STORAGE_CHAT, state.chat);
  syncServer();
}

function nutritionTotals(meals) {
  return meals.reduce(
    (acc, m) => ({
      calories: acc.calories + Number(m.calories || 0),
      protein_g: acc.protein_g + Number(m.protein || 0),
      fat_g: acc.fat_g + Number(m.fat || 0),
      carbs_g: acc.carbs_g + Number(m.carbs || 0),
    }),
    { calories: 0, protein_g: 0, fat_g: 0, carbs_g: 0 }
  );
}

function latestBp() {
  const list = [...day().bp].sort((a, b) => String(b.measured_at).localeCompare(String(a.measured_at)));
  return list[0] || null;
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
    nutrition: {
      ...totals,
      meals: Object.values(mealsByType),
    },
    blood_pressure: {
      readings_today: d.bp,
      latest: bp,
      avg_7d: avgBp(7),
    },
    activity: d.steps == null ? {} : { steps: Number(d.steps), source: "manual" },
    sleep: d.sleep_min == null ? {} : { duration_min: Number(d.sleep_min), source: "manual" },
    body_composition: d.weight_kg == null ? {} : { weight_kg: Number(d.weight_kg) },
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
  if (snap.sleep?.duration_min) {
    const h = Math.floor(snap.sleep.duration_min / 60);
    const m = snap.sleep.duration_min % 60;
    lines.push(`Сон: ${h}h${String(m).padStart(2, "0")}`);
  }
  if (snap.activity?.steps != null) lines.push(`Шаги: ${snap.activity.steps}`);
  const weight = snap.body_composition?.weight_kg ?? snap.profile?.weight_kg_latest;
  if (weight != null) lines.push(`Вес: ${weight}`);
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

async function syncServer() {
  try {
    await fetch("/api/health/sync", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ snapshot: snapshot() }),
    });
  } catch {
    /* offline is fine — local copy still works */
  }
}

function toast(text) {
  const el = document.createElement("div");
  el.className = "toast";
  el.textContent = text;
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 2200);
}

function val(id) {
  return document.getElementById(id)?.value?.trim() || "";
}

function renderToday() {
  const d = day();
  const bp = latestBp();
  const avg = avgBp(7);
  const totals = nutritionTotals(d.meals);
  const high = bp && (bp.systolic >= 140 || bp.diastolic >= 90);
  const sleepH = d.sleep_min ? `${Math.floor(d.sleep_min / 60)}ч ${d.sleep_min % 60}м` : "—";
  return `
    <div class="cards">
      <div class="card">
        <h2>Давление</h2>
        <div class="value ${high ? "high" : ""}">${bp ? `${bp.systolic}/${bp.diastolic}` : "—"}</div>
        <div class="sub">${avg ? `среднее 7д ${avg.systolic}/${avg.diastolic}` : "нет среднего"}</div>
      </div>
      <div class="card">
        <h2>Сон</h2>
        <div class="value">${sleepH}</div>
        <div class="sub">цель около 7–8 часов</div>
      </div>
      <div class="card">
        <h2>Шаги</h2>
        <div class="value">${d.steps ?? "—"}</div>
        <div class="sub">${state.collectorStatus?.running ? "авто из Mi Fitness" : "ручной ввод"}</div>
      </div>
      <div class="card">
        <h2>Вес</h2>
        <div class="value">${d.weight_kg ?? state.profile.weight_kg_latest ?? "—"}</div>
        <div class="sub">кг</div>
      </div>
      <div class="card wide">
        <h2>Еда</h2>
        <div class="value">${Math.round(totals.calories)} ккал</div>
        <div class="sub">Б ${Math.round(totals.protein_g)} · Ж ${Math.round(totals.fat_g)} · У ${Math.round(totals.carbs_g)}</div>
        <ul class="list">${
          d.meals.length
            ? d.meals.map((m, i) => `<li><span>${MEAL_RU[m.meal_type] || m.meal_type}: ${m.name}</span><button class="btn ghost" data-del-meal="${i}">×</button></li>`).join("")
            : `<li class="empty">Пока пусто — добавьте приём</li>`
        }</ul>
      </div>
    </div>
    <div class="actions">
      <button class="btn primary" id="copy-report">Скопировать отчёт коучу</button>
      <button class="btn ghost" id="ask-coach">Спросить коуча по этому дню</button>
    </div>
    <p class="hint">Это не вкладка в «Подсчёте калорий». Сюда вы складываете день, кнопка копирует текст или отправляет коучу.</p>
  `;
}

function renderAdd() {
  const d = day();
  return `
    <div class="card wide form">
      <h2>Давление</h2>
      <div class="row">
        <input id="sys" inputmode="numeric" placeholder="Сис" />
        <input id="dia" inputmode="numeric" placeholder="Диа" />
        <input id="pulse" inputmode="numeric" placeholder="Пульс" />
      </div>
      <button class="btn primary" id="save-bp">Записать АД</button>
    </div>
    <div class="card wide form" style="margin-top:10px">
      <h2>Сон / шаги / вес</h2>
      <label>Сон, минут (например 419 = 6ч59)</label>
      <input id="sleep" inputmode="numeric" value="${d.sleep_min ?? ""}" placeholder="419" />
      <label>Шаги</label>
      <input id="steps" inputmode="numeric" value="${d.steps ?? ""}" placeholder="871" />
      <label>Вес, кг</label>
      <input id="weight" inputmode="decimal" value="${d.weight_kg ?? ""}" placeholder="109.0" />
      <button class="btn primary" id="save-vitals">Сохранить</button>
    </div>
    <div class="card wide form" style="margin-top:10px">
      <h2>Еда</h2>
      <select id="meal-type">
        <option value="breakfast">Завтрак</option>
        <option value="lunch">Обед</option>
        <option value="dinner">Ужин</option>
        <option value="snack">Перекус</option>
      </select>
      <input id="meal-name" placeholder="Что ели, например омлет" />
      <div class="row">
        <input id="meal-grams" inputmode="decimal" placeholder="г" />
        <input id="meal-kcal" inputmode="decimal" placeholder="ккал" />
        <input id="meal-p" inputmode="decimal" placeholder="Б" />
      </div>
      <button class="btn primary" id="save-meal">Добавить еду</button>
    </div>
  `;
}

function renderCoach() {
  const report = formatReport(snapshot());
  const bubbles = state.chat
    .map((m) => `<div class="bubble ${m.role}">${escapeHtml(m.content)}</div>`)
    .join("");
  return `
    <div class="report">${escapeHtml(report)}</div>
    <div class="actions">
      <button class="btn ghost" id="copy-report">Скопировать этот текст</button>
    </div>
    <div class="chat" style="margin-top:12px">${bubbles}</div>
    <div class="form" style="margin-top:12px">
      <textarea id="coach-msg" rows="3" placeholder="Вопрос коучу, например: что урезать сегодня?"></textarea>
      <button class="btn primary" id="send-coach" ${state.sending ? "disabled" : ""}>${state.sending ? "Отправка…" : "Передать коучу"}</button>
    </div>
    <p class="hint">Коуч видит весь снимок дня: АД, сон, шаги, вес, еду и рабочие цели 1900–2100 ккал. Не нужно слать скрины.</p>
  `;
}

function renderMore() {
  const t = state.profile.coaching_calorie_target || {};
  const cs = state.collectorStatus || {};
  return `
    <div class="card wide form">
      <h2>Авто-сбор Mi Fitness</h2>
      <div class="sub" id="collector-info">${cs.running ? "✓ Сбор активен, каждые " + cs.interval_min + " мин" : "Сбор не запущен"}</div>
      ${cs.last_error ? `<div class="sub high">${escapeHtml(cs.last_error)}</div>` : ""}
      ${cs.last_result?.collected_at ? `<div class="sub">Последний: ${cs.last_result.collected_at}, данные: ${(cs.last_result.keys || []).join(", ")}</div>` : ""}
      <button class="btn primary" id="collect-now">Собрать данные сейчас</button>
      ${state.xiaomi2fa ? `
        <div style="margin-top:8px">
          <label>Код из email/SMS</label>
          <input id="xi-code" placeholder="Введите код 2FA" />
          <button class="btn primary" id="xi-verify">Подтвердить код</button>
        </div>
      ` : `
        <details style="margin-top:8px">
          <summary>Подключить аккаунт Xiaomi</summary>
          <input id="xi-user" placeholder="Email / телефон Xiaomi" />
          <input id="xi-pass" type="password" placeholder="Пароль Xiaomi" />
          <button class="btn primary" id="xi-login">Подключить</button>
          <p class="hint">Или введите токены вручную (из Cookie account.xiaomi.com):</p>
          <input id="xi-uid" placeholder="userId" />
          <input id="xi-pt" placeholder="passToken" />
          <button class="btn primary" id="xi-tokens">Сохранить токены</button>
        </details>
      `}
    </div>
    <div class="card wide form" style="margin-top:10px">
      <h2>Импорт CSV давления</h2>
      <p class="hint">Экспорт из Citizen / «Давление»: колонки Дата,Время,Сис,Диа,Пульс</p>
      <input id="csv-file" type="file" accept=".csv,text/csv,text/plain" />
      <button class="btn primary" id="import-csv">Импортировать CSV</button>
    </div>
    <div class="card wide form" style="margin-top:10px">
      <h2>Профиль для коуча</h2>
      <label>Лекарства (через запятую)</label>
      <input id="meds" value="${escapeAttr((state.profile.medications || []).join(", "))}" />
      <label>Рабочая цель ккал мин–макс</label>
      <div class="row">
        <input id="kcal-min" value="${t.kcal_min ?? 1900}" />
        <input id="kcal-max" value="${t.kcal_max ?? 2100}" />
        <input id="protein" value="${t.protein_g ?? 130}" placeholder="Белок" />
      </div>
      <label>Заметка дня</label>
      <textarea id="notes" rows="2">${escapeAttr(day().notes || "")}</textarea>
      <button class="btn primary" id="save-profile">Сохранить профиль</button>
    </div>
    <p class="hint">На Android: меню Chrome → «Добавить на главный экран» — будет как отдельное приложение.</p>
  `;
}

function escapeHtml(text) {
  return String(text)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function escapeAttr(text) {
  return escapeHtml(text).replaceAll('"', "&quot;");
}

function render() {
  const view = document.getElementById("view");
  if (state.tab === "add") view.innerHTML = renderAdd();
  else if (state.tab === "coach") view.innerHTML = renderCoach();
  else if (state.tab === "more") view.innerHTML = renderMore();
  else view.innerHTML = renderToday();
  bind();
}

async function copyReport() {
  const text = formatReport(snapshot());
  try {
    await navigator.clipboard.writeText(text);
    toast("Отчёт скопирован — вставьте коучу");
  } catch {
    prompt("Скопируйте отчёт", text);
  }
}

async function sendCoach() {
  const message = val("coach-msg") || "Что улучшить по этому дню?";
  state.chat.push({ role: "user", content: message });
  state.sending = true;
  persist();
  render();
  try {
    const history = state.chat.slice(0, -1).map((m) => ({ role: m.role, content: m.content }));
    const res = await fetch("/api/coach-health-chat", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ message, snapshot: snapshot(), history }),
    });
    const data = await res.json();
    state.chat.push({ role: "assistant", content: data.reply || "Нет ответа" });
  } catch (err) {
    state.chat.push({ role: "assistant", content: `Сеть недоступна. Отчёт всё равно можно скопировать.\n${err}` });
  }
  state.sending = false;
  persist();
  render();
}

function bind() {
  document.getElementById("copy-report")?.addEventListener("click", copyReport);
  document.getElementById("ask-coach")?.addEventListener("click", () => {
    state.tab = "coach";
    document.querySelectorAll(".tabs button").forEach((b) => b.classList.toggle("active", b.dataset.tab === "coach"));
    render();
  });
  document.getElementById("save-bp")?.addEventListener("click", () => {
    const systolic = Number(val("sys"));
    const diastolic = Number(val("dia"));
    const pulse = val("pulse") ? Number(val("pulse")) : null;
    if (!systolic || !diastolic) return toast("Нужны систол и диастол");
    const now = new Date();
    const iso = new Date(now.getTime() - now.getTimezoneOffset() * 60000).toISOString().slice(0, 19);
    day().bp.push({ measured_at: iso, systolic, diastolic, pulse, source: "manual" });
    persist();
    toast("АД записано");
    render();
  });
  document.getElementById("save-vitals")?.addEventListener("click", () => {
    const d = day();
    d.sleep_min = val("sleep") ? Number(val("sleep")) : null;
    d.steps = val("steps") ? Number(val("steps")) : null;
    d.weight_kg = val("weight") ? Number(val("weight").replace(",", ".")) : null;
    if (d.weight_kg) state.profile.weight_kg_latest = d.weight_kg;
    persist();
    toast("Сохранено");
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
      fat: 0,
      carbs: 0,
    });
    persist();
    toast("Еда добавлена");
    render();
  });
  document.querySelectorAll("[data-del-meal]").forEach((btn) => {
    btn.addEventListener("click", () => {
      day().meals.splice(Number(btn.dataset.delMeal), 1);
      persist();
      render();
    });
  });
  document.getElementById("send-coach")?.addEventListener("click", sendCoach);
  document.getElementById("save-profile")?.addEventListener("click", () => {
    state.profile.medications = val("meds")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
    state.profile.coaching_calorie_target = {
      kcal_min: Number(val("kcal-min") || 1900),
      kcal_max: Number(val("kcal-max") || 2100),
      protein_g: Number(val("protein") || 130),
    };
    day().notes = val("notes");
    persist();
    toast("Профиль сохранён");
  });
  document.getElementById("import-csv")?.addEventListener("click", importCsv);
  document.getElementById("collect-now")?.addEventListener("click", collectNow);
  document.getElementById("xi-login")?.addEventListener("click", xiaomiLogin);
  document.getElementById("xi-verify")?.addEventListener("click", xiaomiVerify);
  document.getElementById("xi-tokens")?.addEventListener("click", xiaomiSetTokens);
}

async function importCsv() {
  const file = document.getElementById("csv-file")?.files?.[0];
  if (!file) return toast("Выберите CSV файл");
  const text = await file.text();
  try {
    await fetch("/api/health/blood-pressure/import-csv", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ csv: text }),
    });
  } catch {
    /* still parse locally */
  }
  const rows = parseCitizenCsv(text);
  for (const row of rows) dayFor(row.date).bp.push(row);
  persist();
  toast(`Импортировано ${rows.length} измерений`);
  render();
}

function dayFor(date) {
  if (!state.days[date]) state.days[date] = emptyDay(date);
  return state.days[date];
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

document.getElementById("date").value = state.date;
document.getElementById("date").addEventListener("change", (e) => {
  state.date = e.target.value || todayIso();
  render();
});
document.querySelectorAll(".tabs button").forEach((btn) => {
  btn.addEventListener("click", () => {
    state.tab = btn.dataset.tab;
    document.querySelectorAll(".tabs button").forEach((b) => b.classList.toggle("active", b === btn));
    render();
  });
});

async function fetchCollectorStatus() {
  try {
    const r = await fetch("/api/health/collector-status");
    state.collectorStatus = await r.json();
  } catch { /* offline */ }
}

async function collectNow() {
  toast("Собираю данные из Mi Fitness…");
  try {
    const r = await fetch("/api/health/collect-now", { method: "POST" });
    if (!r.ok) {
      const e = await r.json();
      toast(e.detail || "Ошибка сбора");
      return;
    }
    const snap = await r.json();
    const d = dayFor(snap.date || todayIso());
    if (snap.steps?.count != null) d.steps = snap.steps.count;
    if (snap.sleep?.total_min != null) d.sleep_min = snap.sleep.total_min;
    if (snap.weight?.kg != null) { d.weight_kg = snap.weight.kg; state.profile.weight_kg_latest = snap.weight.kg; }
    persist();
    await fetchCollectorStatus();
    toast("Данные обновлены из Mi Fitness");
    render();
  } catch (err) {
    toast("Ошибка: " + err.message);
  }
}

async function xiaomiLogin() {
  const username = val("xi-user");
  const password = val("xi-pass");
  if (!username || !password) return toast("Введите логин и пароль Xiaomi");
  toast("Подключаюсь к Xiaomi…");
  try {
    const r = await fetch("/api/health/xiaomi-login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username, password }),
    });
    const data = await r.json();
    if (!r.ok) { toast(data.detail || "Ошибка входа"); return; }
    if (data.status === "2fa_required") {
      state.xiaomi2fa = data.session_id;
      toast("Код отправлен на email/телефон — введите ниже");
      render();
      return;
    }
    toast("Xiaomi подключён! userId: " + data.user_id);
    state.xiaomi2fa = null;
    await fetchCollectorStatus();
    render();
  } catch (err) {
    toast("Ошибка: " + err.message);
  }
}

async function xiaomiVerify() {
  const code = val("xi-code");
  if (!code || !state.xiaomi2fa) return toast("Введите код из email/SMS");
  toast("Проверяю код…");
  try {
    const r = await fetch("/api/health/xiaomi-verify", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ session_id: state.xiaomi2fa, code }),
    });
    const data = await r.json();
    if (!r.ok) { toast(data.detail || "Ошибка"); return; }
    toast("Xiaomi подключён! userId: " + data.user_id);
    state.xiaomi2fa = null;
    await fetchCollectorStatus();
    render();
  } catch (err) {
    toast("Ошибка: " + err.message);
  }
}

async function xiaomiSetTokens() {
  const uid = val("xi-uid");
  const pt = val("xi-pt");
  if (!uid || !pt) return toast("Введите userId и passToken");
  toast("Сохраняю токены…");
  try {
    const r = await fetch("/api/health/xiaomi-tokens", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ user_id: uid, pass_token: pt }),
    });
    const data = await r.json();
    if (!r.ok) { toast(data.detail || "Ошибка"); return; }
    toast("Токены сохранены! userId: " + data.user_id);
    await fetchCollectorStatus();
    render();
  } catch (err) {
    toast("Ошибка: " + err.message);
  }
}

fetchCollectorStatus();

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("sw.js").catch(() => {});
}

render();
