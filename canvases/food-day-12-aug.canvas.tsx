import {
  BarChart,
  Callout,
  CollapsibleSection,
  Grid,
  H1,
  H2,
  H3,
  Row,
  Stack,
  Stat,
  Table,
  Text,
  UsageBar,
  useHostTheme,
} from "cursor/canvas";

const DATE = "12 августа 2026";
const SOURCE = "Дневник питания · скрины до 15:48";

const TARGETS = {
  calories: 2000,
  protein: 130,
  fat: 62,
  carbs: 165,
};

const CONSUMED = {
  calories: 782,
  protein: 49,
  fat: 38,
  carbs: 65,
};

const MEALS = [
  {
    name: "Завтрак",
    time: "08:06",
    kcal: 308,
    protein: 18.4,
    fat: 13.7,
    carbs: 29.1,
    items: "3 яйца, кофе с молоком 240 мл, банан",
    verdict: "success" as const,
    note: "Умеренно, белок есть",
  },
  {
    name: "Обед",
    time: "14:25",
    kcal: 474,
    protein: 30.7,
    fat: 24,
    carbs: 36.4,
    items: "Mealty: лосось + пюре + спаржа + шпинат (380 г); помидоры 210 г",
    verdict: "warning" as const,
    note: "Белок сильный, жир выше нормы",
  },
  {
    name: "Ужин",
    time: "—",
    kcal: 0,
    protein: 0,
    fat: 0,
    carbs: 0,
    items: "Не занесено",
    verdict: "neutral" as const,
    note: "Главный рычаг дня",
  },
];

function remaining(target: number, consumed: number): number {
  return Math.max(0, target - consumed);
}

function pct(consumed: number, target: number): string {
  return `${Math.round((consumed / target) * 100)}%`;
}

function MacroBar({
  label,
  consumed,
  target,
  unit,
  color,
}: {
  label: string;
  consumed: number;
  target: number;
  unit: string;
  color: "blue" | "green" | "yellow" | "purple";
}) {
  return (
    <UsageBar
      total={target}
      topLeftLabel={label}
      topRightLabel={`${consumed} / ${target} ${unit}`}
      segments={[{ id: "consumed", value: consumed, color }]}
    />
  );
}

export default function FoodDay12Aug() {
  const theme = useHostTheme();

  const leftKcal = remaining(TARGETS.calories, CONSUMED.calories);
  const leftProtein = remaining(TARGETS.protein, CONSUMED.protein);
  const leftFat = remaining(TARGETS.fat, CONSUMED.fat);
  const leftCarbs = remaining(TARGETS.carbs, CONSUMED.carbs);

  const dinnerPlan = [
    {
      title: "Дома",
      kcal: "520–560",
      protein: "65–70 г",
      detail: "Творог 5% 200 г + 2 яйца + овощи + кефир или прот. чипсы",
    },
    {
      title: "VkusVill",
      kcal: "450–500",
      protein: "45–50 г",
      detail: "Куриное филе с овощами + салат витаминный; при недоборе — творог 100–150 г",
    },
    {
      title: "Mealty",
      kcal: "500–600",
      protein: "50–65 г",
      detail: "Курица с птитимом и фасолью; при необходимости творог дома",
    },
  ];

  return (
    <Stack gap={20} style={{ padding: 16, maxWidth: 920 }}>
      <Stack gap={4}>
        <H1>Питание · {DATE}</H1>
        <Text tone="tertiary" size="small">
          {SOURCE}
        </Text>
      </Stack>

      <Grid columns={4} gap={12}>
        <Stat
          value={`${CONSUMED.calories}`}
          label={`ккал · ${pct(CONSUMED.calories, TARGETS.calories)} от ~${TARGETS.calories}`}
        />
        <Stat value={`${CONSUMED.protein} г`} label={`белок · осталось ${leftProtein} г`} />
        <Stat
          value={`${CONSUMED.fat} г`}
          label={`жир · осталось ${leftFat} г`}
          tone="warning"
        />
        <Stat value={`${CONSUMED.carbs} г`} label={`углеводы · осталось ${leftCarbs} г`} />
      </Grid>

      <Callout tone="info" title="Остаток на день">
        <Text>
          После завтрака и обеда: ~{leftKcal} ккал, белок {leftProtein}–{remaining(140, CONSUMED.protein)} г,
          жир {leftFat}–{remaining(70, CONSUMED.fat)} г, углеводы {leftCarbs}–{remaining(180, CONSUMED.carbs)} г.
          Целевой ужин: 550–650 ккал, белок от 70 г, без лишнего жира и соли.
        </Text>
      </Callout>

      <Stack gap={10}>
        <H2>Прогресс по макросам</H2>
        <Text tone="tertiary" size="small">
          Съедено vs целевые нормы (ккал ~2000, белок 120–140 г, жир 55–70 г, углеводы 150–180 г)
        </Text>
        <Stack gap={12}>
          <MacroBar
            label="Калории"
            consumed={CONSUMED.calories}
            target={TARGETS.calories}
            unit="ккал"
            color="blue"
          />
          <MacroBar
            label="Белок"
            consumed={CONSUMED.protein}
            target={TARGETS.protein}
            unit="г"
            color="green"
          />
          <MacroBar
            label="Жир"
            consumed={CONSUMED.fat}
            target={TARGETS.fat}
            unit="г"
            color="yellow"
          />
          <MacroBar
            label="Углеводы"
            consumed={CONSUMED.carbs}
            target={TARGETS.carbs}
            unit="г"
            color="purple"
          />
        </Stack>
      </Stack>

      <Grid columns={2} gap={16}>
        <Stack gap={8}>
          <H2>Калории по приёмам (ккал)</H2>
          <Text tone="tertiary" size="small">
            Завтрак, обед, ужин · 12 августа
          </Text>
          <BarChart
            categories={["Завтрак", "Обед", "Ужин"]}
            series={[{ name: "Ккал", data: [308, 474, 0], tone: "info" }]}
            valueSuffix=" ккал"
            showValues
            referenceLines={[{ value: 600, label: "ориентир ужина", tone: "warning" }]}
            height={220}
          />
        </Stack>

        <Stack gap={8}>
          <H2>Съедено vs цель за день</H2>
          <Text tone="tertiary" size="small">
            Сравнение факта с целевыми значениями
          </Text>
          <BarChart
            categories={["Ккал", "Белок", "Жир", "Углеводы"]}
            series={[
              { name: "Съедено", data: [782, 49, 38, 65], tone: "info" },
              { name: "Цель", data: [2000, 130, 62, 165], tone: "neutral" },
            ]}
            horizontal
            height={220}
          />
        </Stack>
      </Grid>

      <Stack gap={8}>
        <H2>Приёмы пищи</H2>
        <Table
          headers={["Приём", "Время", "Ккал", "Б", "Ж", "У", "Состав", "Оценка"]}
          rows={MEALS.map((m) => [
            m.name,
            m.time,
            String(m.kcal),
            m.protein ? `${m.protein}` : "—",
            m.fat ? `${m.fat}` : "—",
            m.carbs ? `${m.carbs}` : "—",
            m.items,
            m.note,
          ])}
          rowTone={MEALS.map((m) => m.verdict)}
          columnAlign={["left", "center", "right", "right", "right", "right", "left", "left"]}
          striped
        />
      </Stack>

      <Stack gap={8}>
        <H2>Ужин — закрыть день</H2>
        <Callout tone="warning" title="После лосося на обед">
          <Text>
            Не добавлять ещё рыбу, жирные соусы или солёные готовые блюда. Фокус: белок без разгона жира
            (важно при гипертонии).
          </Text>
        </Callout>

        <Grid columns={3} gap={12}>
          {dinnerPlan.map((plan) => (
            <Stack
              key={plan.title}
              gap={6}
              style={{
                padding: 12,
                borderRadius: 8,
                border: `1px solid ${theme.stroke.tertiary}`,
              }}
            >
              <H3>{plan.title}</H3>
              <Row gap={12}>
                <Text size="small" weight="semibold">
                  {plan.kcal} ккал
                </Text>
                <Text size="small" tone="secondary">
                  Б {plan.protein}
                </Text>
              </Row>
              <Text size="small" tone="secondary">
                {plan.detail}
              </Text>
            </Stack>
          ))}
        </Grid>

        <CollapsibleSection
          title="Прогноз дня после ужина «Дома»"
          defaultOpen
          trailing={<Text size="small" tone="tertiary">~1300–1350 ккал</Text>}
        >
          <Stack gap={8} style={{ paddingLeft: 8 }}>
            <Text size="small">
              Ужин дома (~540 ккал, Б ~68) даст итог: ~1320 ккал, белок ~117 г, жир ~58 г, углеводы ~95 г.
            </Text>
            <Text size="small" tone="secondary">
              При лёгком голоде — перекус +150–200 ккал: яблоко, кефир, 20 г орехов.
            </Text>
          </Stack>
        </CollapsibleSection>
      </Stack>
    </Stack>
  );
}
