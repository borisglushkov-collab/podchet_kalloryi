/**
 * Pure hub day/profile logic — safe to unit-test in Node.
 */
export const MEAL_RU = {
  breakfast: "Завтрак",
  lunch: "Обед",
  dinner: "Ужин",
  snack: "Перекус",
};

export const defaultProfile = () => ({
  height_cm: null,
  weight_kg_latest: null,
  medications: [],
  coaching_calorie_target: {
    kcal_min: 1900,
    kcal_max: 2100,
    protein_g: 130,
  },
  updated_at: null,
});

export const emptyDay = (date) => ({
  date,
  meals: [],
  bp: [],
  workouts: [],
  sleep_min: null,
  sleep_deep_min: null,
  sleep_light_min: null,
  sleep_rem_min: null,
  sleep_in_bed_min: null,
  steps: null,
  weight_kg: null,
  body_composition: null,
  notes: "",
  sources_status: null,
  last_synced_at: null,
  locks: { steps: false, sleep: false, weight: false },
});

export function countNutritionItems(nutrition) {
  return (nutrition?.meals || []).reduce((n, m) => n + (m.items?.length || 0), 0);
}

export function normalizeNutritionItem(it) {
  if (!it) return null;
  const name = String(it.name || it.food_entry_name || it.food_name || "").trim();
  if (!name) return null;
  return {
    name,
    grams: Number(it.grams ?? it.number_of_units ?? 0),
    calories: Number(it.calories ?? 0),
    protein: Number(it.protein ?? it.protein_g ?? 0),
    fat: Number(it.fat ?? it.fat_g ?? 0),
    carbs: Number(it.carbs ?? it.carbs_g ?? it.carbohydrate ?? 0),
  };
}

export function importNutritionMeals(d, nutrition, force = false) {
  const n = nutrition || {};
  const incomingCount = countNutritionItems(n);
  if (incomingCount === 0) return false;

  const shouldReplace =
    force ||
    n.source === "fatsecret" ||
    incomingCount > (d.meals?.length || 0);
  if (!shouldReplace) return false;

  d.meals = [];
  for (const m of n.meals) {
    const mt = String(m.meal_type || "snack").toLowerCase();
    const items = Array.isArray(m.items) ? m.items : [];
    for (const it of items) {
      const row = normalizeNutritionItem(it);
      if (!row) continue;
      d.meals.push({ meal_type: mt, source: n.source || "auto", ...row });
    }
  }
  return true;
}

export function bodyCompositionFromWeight(w) {
  if (!w || w.kg == null) return null;
  return {
    weight_kg: Number(w.kg),
    bmi: w.bmi ?? null,
    body_fat_pct: w.bodyFat ?? null,
    muscle_kg: w.muscle ?? null,
    water_pct: w.water ?? null,
    bone_kg: w.bone ?? null,
    visceral_fat: w.visceralFat ?? null,
    body_age: w.bodyAge ?? null,
    bmr_kcal: w.bmr ?? null,
    body_score: w.bodyScore ?? null,
    heart_rate: w.heartRate ?? null,
    skeletal_muscle_kg: w.skeletalMuscle ?? null,
    protein_kg: w.protein ?? null,
    source: w.source || "xiaomi_home",
  };
}

export function applySnapshotToDay(d, snap, { force = false, onWeight } = {}) {
  d.locks = d.locks || { steps: false, sleep: false, weight: false };
  let stepCount = snap.steps?.count ?? snap.activity?.steps;
  // Prefer Mi Fitness cloud totals when steps/activity disagree (old max-merge left stale highs).
  if (snap.steps?.source === "mi_fitness" && snap.steps?.count != null) {
    stepCount = snap.steps.count;
  } else if (snap.activity?.source === "mi_fitness" && snap.activity?.steps != null) {
    stepCount = snap.activity.steps;
  }
  if (
    stepCount != null
    && !d.locks.steps
    && (force || d.steps == null || snap.source === "mi_fitness_auto")
  ) {
    d.steps = Number(stepCount);
  }
  const sleepMin = snap.sleep?.total_min ?? snap.sleep?.duration_min;
  const cloudSleep = snap.source === "mi_fitness_auto";
  if (
    !d.locks.sleep
    && (force || d.sleep_min == null || cloudSleep)
  ) {
    if (sleepMin != null) {
      d.sleep_min = Number(sleepMin);
      if (snap.sleep?.deep_min != null) d.sleep_deep_min = Number(snap.sleep.deep_min);
      if (snap.sleep?.light_min != null) d.sleep_light_min = Number(snap.sleep.light_min);
      if (snap.sleep?.rem_min != null) d.sleep_rem_min = Number(snap.sleep.rem_min);
      if (snap.sleep?.in_bed_min != null) d.sleep_in_bed_min = Number(snap.sleep.in_bed_min);
      else d.sleep_in_bed_min = null;
    } else if (force && cloudSleep && Object.prototype.hasOwnProperty.call(snap, "sleep") && snap.sleep == null) {
      d.sleep_min = null;
      d.sleep_deep_min = null;
      d.sleep_light_min = null;
      d.sleep_rem_min = null;
      d.sleep_in_bed_min = null;
    }
  }
  if (
    snap.weight?.kg != null
    && !d.locks.weight
    && (force || d.weight_kg == null || snap.weight.source === "xiaomi_home")
  ) {
    const bc = bodyCompositionFromWeight(snap.weight);
    if (bc) {
      d.weight_kg = bc.weight_kg;
      d.body_composition = bc;
      if (typeof onWeight === "function") onWeight(bc.weight_kg);
    }
  }
  if (snap.heart_rate && (force || !d.heart_rate || snap.source === "mi_fitness_auto")) {
    d.heart_rate = snap.heart_rate;
  }
  if (force) {
    d.workouts = Array.isArray(snap.workouts) ? snap.workouts : [];
  } else if (Array.isArray(snap.workouts) && snap.workouts.length) {
    d.workouts = snap.workouts;
  }

  if (snap.sources_status) d.sources_status = snap.sources_status;
  if (snap.generated_at) d.last_synced_at = snap.generated_at;

  const incoming = [];
  const readings = snap.blood_pressure?.readings_today;
  if (Array.isArray(readings) && readings.length) {
    for (const r of readings) {
      if (!r?.systolic || !r?.diastolic) continue;
      incoming.push({
        systolic: r.systolic,
        diastolic: r.diastolic,
        pulse: r.pulse,
        measured_at: r.measured_at,
        source: r.source || "auto",
      });
    }
  }
  const latest = snap.blood_pressure?.latest;
  if (latest?.systolic && latest?.diastolic) {
    const measuredAt = latest.measured_at || null;
    // Do not invent "now" for undated latest — that sorts above real timed readings.
    if (measuredAt || !incoming.length) {
      incoming.push({
        systolic: latest.systolic,
        diastolic: latest.diastolic,
        pulse: latest.pulse,
        measured_at: measuredAt || `${d.date || ""}`,
        source: latest.source || "auto",
      });
    }
  }
  if (force) {
    // Collect-now is authoritative for cloud BP; keep only local manuals not present server-side.
    const manuals = (d.bp || []).filter((b) => b.source === "manual" || b.source === "csv");
    d.bp = [];
    for (const r of [...incoming, ...manuals]) {
      if (!d.bp.some((b) => b.systolic === r.systolic && b.diastolic === r.diastolic && b.measured_at === r.measured_at)) {
        d.bp.push(r);
      }
    }
  } else {
    for (const r of incoming) {
      if (!d.bp.some((b) => b.systolic === r.systolic && b.diastolic === r.diastolic && b.measured_at === r.measured_at)) {
        d.bp.push(r);
      }
    }
  }
  d.bp = sortBpNewestFirst(d.bp);

  importNutritionMeals(d, snap.nutrition, force);
  return d;
}

/** Sort key for BP measured_at; date-only counts as start-of-day (older than timed same day). */
export function bpSortKey(measuredAt) {
  const s = String(measuredAt || "");
  if (!s) return 0;
  const t = Date.parse(s.includes("T") ? s : `${s}T00:00:00`);
  return Number.isFinite(t) ? t : 0;
}

export function sortBpNewestFirst(list) {
  return [...(list || [])].sort((a, b) => bpSortKey(b.measured_at) - bpSortKey(a.measured_at));
}

export function latestBpReading(list) {
  return sortBpNewestFirst(list)[0] || null;
}

export function clearManualLocks(d) {
  d.locks = { steps: false, sleep: false, weight: false };
  return d;
}

export function hasManualLocks(d) {
  const locks = d?.locks || {};
  return Boolean(locks.steps || locks.sleep || locks.weight);
}

export function nutritionTotals(meals) {
  return (meals || []).reduce(
    (acc, m) => ({
      calories: acc.calories + Number(m.calories || 0),
      protein_g: acc.protein_g + Number(m.protein ?? m.protein_g ?? 0),
      fat_g: acc.fat_g + Number(m.fat ?? m.fat_g ?? 0),
      carbs_g: acc.carbs_g + Number(m.carbs ?? m.carbs_g ?? 0),
    }),
    { calories: 0, protein_g: 0, fat_g: 0, carbs_g: 0 },
  );
}

export function weekGoalStats(series, target = {}) {
  const lo = Number(target.kcal_min || 0);
  const hi = Number(target.kcal_max || lo);
  const withCal = (series || []).filter((s) => s.calories != null);
  let inGoal = 0;
  if (lo || hi) {
    for (const s of withCal) {
      const cal = Number(s.calories);
      if ((!lo || cal >= lo) && (!hi || cal <= hi)) inGoal += 1;
    }
  }
  const sleepVals = (series || []).map((s) => s.sleep_min).filter((v) => v != null);
  const avgSleep = sleepVals.length
    ? Math.round(sleepVals.reduce((a, b) => a + b, 0) / sleepVals.length)
    : null;
  return {
    inGoal,
    withCal: withCal.length,
    lo: lo || null,
    hi: hi || null,
    avgSleep,
  };
}

export function syncTone({ connected, status, lastSyncedAt, refreshing, now = Date.now() }) {
  if (refreshing) return { tone: "busy", label: "обновляю…" };
  if (!connected) return { tone: "off", label: "не подключён" };
  if (status?.ok === false && status.error !== "not_connected") {
    return { tone: "err", label: "ошибка" };
  }
  if (lastSyncedAt) {
    const ageH = (now - new Date(lastSyncedAt).getTime()) / 3600000;
    if (Number.isFinite(ageH) && ageH > 6) {
      const t = new Date(lastSyncedAt).toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit" });
      return { tone: "stale", label: `устарело · ${t}` };
    }
    const t = new Date(lastSyncedAt).toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit" });
    return { tone: "ok", label: `ок · ${t}` };
  }
  return { tone: "ok", label: "подключён" };
}

/** Last-write-wins: prefer newer updated_at; ties keep server. */
export function mergeProfilesLww(local, server) {
  const l = { ...defaultProfile(), ...(local || {}) };
  const s = { ...defaultProfile(), ...(server || {}) };
  const lt = l.updated_at ? Date.parse(l.updated_at) : 0;
  const st = s.updated_at ? Date.parse(s.updated_at) : 0;
  if (lt > st) return { profile: l, winner: "local", shouldPush: true };
  return { profile: s, winner: "server", shouldPush: false };
}

export function todayIso(date = new Date()) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Moscow",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}
