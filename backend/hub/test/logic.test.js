import assert from "node:assert/strict";
import test from "node:test";
import {
  applySnapshotToDay,
  clearManualLocks,
  emptyDay,
  hasManualLocks,
  importNutritionMeals,
  latestBpReading,
  mergeProfilesLww,
  syncTone,
  weekGoalStats,
} from "../js/logic.js";

test("empty FatSecret collect does not wipe meals", () => {
  const d = emptyDay("2026-08-20");
  d.meals = [{ meal_type: "breakfast", name: "омлет", calories: 200, source: "fatsecret" }];
  const changed = importNutritionMeals(d, { source: "fatsecret", meals: [] }, true);
  assert.equal(changed, false);
  assert.equal(d.meals.length, 1);
});

test("FatSecret meals replace when incoming has items", () => {
  const d = emptyDay("2026-08-20");
  d.meals = [{ meal_type: "snack", name: "old", calories: 50, source: "manual" }];
  importNutritionMeals(
    d,
    {
      source: "fatsecret",
      meals: [{ meal_type: "lunch", items: [{ name: "суп", calories: 120, protein: 8, fat: 3, carbs: 10 }] }],
    },
    false,
  );
  assert.equal(d.meals.length, 1);
  assert.equal(d.meals[0].name, "суп");
  assert.equal(d.meals[0].source, "fatsecret");
});

test("force refresh clears sleep when cloud reports null", () => {
  const d = emptyDay("2026-09-02");
  d.sleep_min = 420;
  d.sleep_deep_min = 50;
  applySnapshotToDay(
    d,
    { sleep: null, source: "mi_fitness_auto" },
    { force: true },
  );
  assert.equal(d.sleep_min, null);
  assert.equal(d.sleep_deep_min, null);
});

test("manual locks block cloud overwrite", () => {
  const d = emptyDay("2026-08-20");
  d.steps = 100;
  d.locks.steps = true;
  applySnapshotToDay(d, { steps: { count: 5000 }, source: "mi_fitness_auto" }, { force: true });
  assert.equal(d.steps, 100);
  clearManualLocks(d);
  applySnapshotToDay(d, { steps: { count: 5000 }, source: "mi_fitness_auto" }, { force: true });
  assert.equal(d.steps, 5000);
  assert.equal(hasManualLocks(d), false);
});

test("week goal stats count days in range", () => {
  const stats = weekGoalStats(
    [
      { calories: 2000 },
      { calories: 2200 },
      { calories: 1950 },
      { calories: null },
    ],
    { kcal_min: 1900, kcal_max: 2100 },
  );
  assert.equal(stats.inGoal, 2);
  assert.equal(stats.withCal, 3);
});

test("syncTone covers busy stale off ok", () => {
  assert.equal(syncTone({ connected: true, refreshing: true }).tone, "busy");
  assert.equal(syncTone({ connected: false }).tone, "off");
  const staleAt = new Date(Date.now() - 7 * 3600000).toISOString();
  assert.equal(syncTone({ connected: true, lastSyncedAt: staleAt }).tone, "stale");
  const freshAt = new Date(Date.now() - 10 * 60000).toISOString();
  assert.equal(syncTone({ connected: true, lastSyncedAt: freshAt }).tone, "ok");
});

test("force refresh replaces cloud BP and keeps manuals", () => {
  const d = emptyDay("2026-08-27");
  d.bp = [
    { systolic: 147, diastolic: 91, measured_at: "2026-08-27", source: "medm_bp" },
    { systolic: 120, diastolic: 80, measured_at: "2026-08-27T08:00:00", source: "manual" },
  ];
  applySnapshotToDay(
    d,
    {
      blood_pressure: {
        readings_today: [
          { systolic: 133, diastolic: 88, pulse: 72, measured_at: "2026-08-27T09:05:00", source: "medm_bp" },
          { systolic: 140, diastolic: 90, pulse: 68, measured_at: "2026-08-27T14:13:00", source: "medm_bp" },
        ],
        latest: { systolic: 140, diastolic: 90, pulse: 68, measured_at: "2026-08-27T14:13:00", source: "medm_bp" },
      },
    },
    { force: true },
  );
  assert.equal(d.bp.length, 3);
  assert.equal(latestBpReading(d.bp).systolic, 140);
  assert.equal(latestBpReading(d.bp).measured_at, "2026-08-27T14:13:00");
  assert.ok(d.bp.some((b) => b.source === "manual" && b.systolic === 120));
  assert.equal(d.bp.some((b) => b.measured_at === "2026-08-27"), false);
});

test("profile merge last-write-wins", () => {
  const local = { height_cm: 165, updated_at: "2026-08-20T12:00:00Z", medications: ["A"] };
  const server = { height_cm: 170, updated_at: "2026-08-20T10:00:00Z", medications: ["B"] };
  const a = mergeProfilesLww(local, server);
  assert.equal(a.winner, "local");
  assert.equal(a.shouldPush, true);
  assert.equal(a.profile.height_cm, 165);

  const b = mergeProfilesLww(
    { height_cm: 165, updated_at: "2026-08-20T09:00:00Z" },
    { height_cm: 170, updated_at: "2026-08-20T11:00:00Z" },
  );
  assert.equal(b.winner, "server");
  assert.equal(b.profile.height_cm, 170);
});
