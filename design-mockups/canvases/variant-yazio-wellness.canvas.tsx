import {
  Button,
  Card,
  CardBody,
  CardHeader,
  Divider,
  Grid,
  H1,
  H2,
  H3,
  Pill,
  Row,
  Stack,
  Stat,
  Swatch,
  Text,
  UsageBar,
  useHostTheme,
} from "cursor/canvas";

const TARGETS = { kcal: 2000, protein: 120, fat: 65, carbs: 180 };
const CONSUMED = { kcal: 760, protein: 85, fat: 42, carbs: 98 };
const WEEK = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"];

function PhoneFrame({ children }: { children: import("react").ReactNode }) {
  const theme = useHostTheme();
  return (
    <div
      style={{
        width: 320,
        minHeight: 680,
        borderRadius: 28,
        border: `2px solid ${theme.stroke.secondary}`,
        background: theme.bg.editor,
        overflow: "hidden",
        display: "flex",
        flexDirection: "column",
      }}
    >
      <div style={{ height: 28, display: "flex", alignItems: "center", justifyContent: "center" }}>
        <div style={{ width: 80, height: 6, borderRadius: 3, background: theme.fill.tertiary }} />
      </div>
      {children}
    </div>
  );
}

function WeekStrip() {
  const theme = useHostTheme();
  return (
    <Row justify="space-between" style={{ width: "100%" }}>
      {WEEK.map((day, i) => {
        const isToday = day === "Ср";
        const done = i < 2;
        return (
          <Stack key={day} gap={4} style={{ alignItems: "center" }}>
            <Text size="small" tone={isToday ? "primary" : "tertiary"} weight={isToday ? "semibold" : "normal"}>
              {day}
            </Text>
            <div
              style={{
                width: 32,
                height: 32,
                borderRadius: 16,
                background: isToday ? theme.palette.green : done ? theme.fill.secondary : theme.fill.tertiary,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                border: isToday ? `2px solid ${theme.palette.green}` : "none",
              }}
            >
              <Text
                size="small"
                weight="semibold"
                style={{ color: isToday || done ? theme.text.onAccent : theme.text.tertiary }}
              >
                {8 + i}
              </Text>
            </div>
          </Stack>
        );
      })}
    </Row>
  );
}

function MealTile({
  label,
  color,
  kcal,
  target,
  status,
}: {
  label: string;
  color: "yellow" | "orange" | "purple" | "green";
  kcal: number;
  target: number;
  status: "done" | "current" | "empty";
}) {
  const theme = useHostTheme();
  const progress = target > 0 ? kcal / target : 0;

  return (
    <Card variant={status === "current" ? "filled" : "default"} style={{ flex: 1, minWidth: 0 }}>
      <CardBody>
        <Stack gap={8}>
          <Row align="center" gap={6}>
            <Swatch color={color} />
            <Text size="small" weight="semibold" truncate>{label}</Text>
          </Row>
          <Text weight="bold" style={{ fontSize: 18 }}>{kcal}</Text>
          <Text size="small" tone="tertiary">/ {target} ккал</Text>
          <div style={{ height: 4, borderRadius: 2, background: theme.fill.tertiary, overflow: "hidden" }}>
            <div
              style={{
                width: `${Math.min(progress * 100, 100)}%`,
                height: "100%",
                background: status === "done" ? theme.palette.green : theme.palette[color],
                borderRadius: 2,
              }}
            />
          </div>
          {status === "done" && <Pill tone="success" size="sm">Готово</Pill>}
          {status === "current" && <Pill tone="info" size="sm">Сейчас</Pill>}
        </Stack>
      </CardBody>
    </Card>
  );
}

function PhoneScreen() {
  const theme = useHostTheme();
  const remaining = TARGETS.kcal - CONSUMED.kcal;
  const dayProgress = Math.round((CONSUMED.kcal / TARGETS.kcal) * 100);
  const score = 72;

  return (
    <PhoneFrame>
      <div style={{ flex: 1, overflow: "auto", padding: "0 16px 8px" }}>
        <Stack gap={14}>
          <Row justify="space-between" align="center">
            <Stack gap={2}>
              <Text weight="semibold">Привет, Алексей</Text>
              <Text size="small" tone="secondary">Твой план на сегодня</Text>
            </Stack>
            <Card variant="filled" style={{ padding: "6px 12px" }}>
              <Row gap={6} align="center">
                <Text size="small" weight="semibold" style={{ color: theme.palette.orange }}>12</Text>
                <Text size="small" tone="secondary">дней</Text>
              </Row>
            </Card>
          </Row>

          <WeekStrip />

          <Card variant="filled">
            <CardBody>
              <Stack gap={10}>
                <Row justify="space-between" align="center">
                  <Text size="small" tone="secondary">Осталось сегодня</Text>
                  <Pill tone="success" size="sm">Оценка {score}/100</Pill>
                </Row>
                <Text weight="bold" style={{ fontSize: 36, lineHeight: 1, color: theme.palette.green }}>
                  {remaining}
                </Text>
                <Text size="small" tone="secondary">ккал до цели</Text>
                <UsageBar
                  total={100}
                  segments={[{ id: "day", value: dayProgress, color: "green" }]}
                  topLeftLabel={`${dayProgress}% дня`}
                  topRightLabel={`${CONSUMED.kcal} из ${TARGETS.kcal}`}
                />
              </Stack>
            </CardBody>
          </Card>

          <Grid columns={3} gap={6}>
            <Stat label="Белки" value={`${CONSUMED.protein}г`} tone="info" style={{ textAlign: "center" }} />
            <Stat label="Жиры" value={`${CONSUMED.fat}г`} tone="warning" style={{ textAlign: "center" }} />
            <Stat label="Углев." value={`${CONSUMED.carbs}г`} style={{ textAlign: "center" }} />
          </Grid>

          <Card>
            <CardHeader trailing={<Pill tone="info" size="sm">Коуч</Pill>}>
              Совет дня
            </CardHeader>
            <CardBody>
              <Stack gap={8}>
                <Text size="small">
                  До обеда осталось 35 г белка. Попробуй куриную грудку с гречкой — 420 ккал, готово за 25 мин.
                </Text>
                <Row gap={8}>
                  <Button variant="primary">Добавить в обед</Button>
                  <Button variant="ghost">Ещё идеи</Button>
                </Row>
              </Stack>
            </CardBody>
          </Card>

          <Stack gap={6}>
            <Text weight="semibold">Приёмы пищи</Text>
            <Row gap={8}>
              <MealTile label="Завтрак" color="yellow" kcal={320} target={400} status="done" />
              <MealTile label="Обед" color="orange" kcal={580} target={600} status="done" />
            </Row>
            <Row gap={8}>
              <MealTile label="Ужин" color="purple" kcal={0} target={500} status="current" />
              <MealTile label="Перекус" color="green" kcal={0} target={200} status="empty" />
            </Row>
          </Stack>

          <Card variant="filled">
            <CardBody>
              <Row justify="space-between" align="center">
                <Stack gap={2}>
                  <Text size="small" tone="secondary">Вода</Text>
                  <Text weight="semibold">1.2 / 2.0 л</Text>
                </Stack>
                <Row gap={4}>
                  {[1, 2, 3, 4, 5].map((n) => (
                    <div
                      key={n}
                      style={{
                        width: 12,
                        height: 20,
                        borderRadius: 4,
                        background: n <= 3 ? theme.palette.blue : theme.fill.tertiary,
                      }}
                    />
                  ))}
                </Row>
              </Row>
            </CardBody>
          </Card>
        </Stack>
      </div>

      <div style={{ borderTop: `1px solid ${theme.stroke.tertiary}`, padding: "8px 12px 16px", background: theme.bg.chrome }}>
        <Row justify="space-around">
          {[
            { label: "Сегодня", active: true },
            { label: "Аналитика", active: false },
            { label: "+", fab: true },
            { label: "Коуч", active: false },
            { label: "Профиль", active: false },
          ].map((tab) => (
            <Stack key={tab.label} gap={2} style={{ alignItems: "center", minWidth: 48 }}>
              {tab.fab ? (
                <div style={{ width: 44, height: 44, borderRadius: 22, background: theme.palette.green, display: "flex", alignItems: "center", justifyContent: "center" }}>
                  <Text weight="bold" style={{ color: theme.text.onAccent, fontSize: 20 }}>+</Text>
                </div>
              ) : (
                <Text
                  size="small"
                  weight={tab.active ? "semibold" : "normal"}
                  style={tab.active ? { color: theme.palette.green } : undefined}
                >
                  {tab.label}
                </Text>
              )}
            </Stack>
          ))}
        </Row>
      </div>
    </PhoneFrame>
  );
}

function Annotation({ title, children }: { title: string; children: import("react").ReactNode }) {
  return (
    <Stack gap={4}>
      <Text weight="semibold">{title}</Text>
      <Text size="small" tone="secondary">{children}</Text>
    </Stack>
  );
}

export default function VariantYazioWellness() {
  const theme = useHostTheme();

  return (
    <Stack gap={24} style={{ padding: 24, maxWidth: 960 }}>
      <Stack gap={8}>
        <H1>Вариант B: Yazio / Noom / Lose It!</H1>
        <Text tone="secondary">
          Wellness + геймификация. Здоровье как lifestyle, мотивация через streak и коучинг.
        </Text>
        <Row gap={8}>
          <Pill tone="success" size="sm">Референс: Yazio</Pill>
          <Pill tone="neutral" size="sm">Noom</Pill>
          <Pill tone="neutral" size="sm">Lose It!</Pill>
        </Row>
      </Stack>

      <Row gap={32} align="start" wrap>
        <PhoneScreen />

        <Stack gap={20} style={{ flex: 1, minWidth: 280 }}>
          <H2>Ключевые решения</H2>

          <Annotation title="1. Streak и недельный календарь">
            Счётчик «12 дней» и полоска дней недели — как в Yazio/Lose It. Retention через привычку.
          </Annotation>

          <Annotation title="2. Крупная цифра «осталось»">
            Большое число ккал вместо кольца — эмоциональный якорь. Оценка дня 72/100 — геймификация Noom.
          </Annotation>

          <Annotation title="3. Плитки приёмов 2×2">
            Каждый приём — мини-карточка с прогрессом и статусом (Готово / Сейчас). Визуально легче accordion.
          </Annotation>

          <Annotation title="4. Коуч-карточка вместо ИИ-кнопки">
            Дружелюбный текст от «коуча» с конкретным советом. AI как персональный тренер, не технология.
          </Annotation>

          <Annotation title="5. Вода и микро-привычки">
            Трекер воды — стандарт Yazio. Расширяет приложение за рамки калорий.
          </Annotation>

          <Annotation title="6. Навигация: Сегодня / Аналитика / Коуч">
            Вкладка «Коуч» выделяет AI-рекомендации как отдельный раздел.
          </Annotation>

          <Divider />

          <H3>Палитра (Flutter)</H3>
          <Grid columns={2} gap={8}>
            <Row gap={8} align="center">
              <div style={{ width: 20, height: 20, borderRadius: 4, background: "#6BCB77" }} />
              <Text size="small">Primary green #6BCB77</Text>
            </Row>
            <Row gap={8} align="center">
              <div style={{ width: 20, height: 20, borderRadius: 4, background: "#FFF9F0", border: `1px solid ${theme.stroke.tertiary}` }} />
              <Text size="small">Warm bg #FFF9F0</Text>
            </Row>
            <Row gap={8} align="center">
              <div style={{ width: 20, height: 20, borderRadius: 4, background: "#FF6B35" }} />
              <Text size="small">Streak orange #FF6B35</Text>
            </Row>
            <Row gap={8} align="center">
              <div style={{ width: 20, height: 20, borderRadius: 4, background: "#4ECDC4" }} />
              <Text size="small">Water teal #4ECDC4</Text>
            </Row>
          </Grid>

          <H3>Когда выбирать</H3>
          <Text size="small" tone="secondary">
            Аудитория 25–40, фокус на мотивации и retention. AI как «коуч», не как фича.
            Меньше плотности данных, больше эмоции. Хорошо для маркетинга в сторе.
          </Text>
        </Stack>
      </Row>
    </Stack>
  );
}
