import {
  Button,
  Card,
  CardBody,
  CardHeader,
  CollapsibleSection,
  Divider,
  Grid,
  H1,
  H2,
  H3,
  Pill,
  Row,
  Spacer,
  Stack,
  Stat,
  Swatch,
  Text,
  UsageBar,
  mergeStyle,
  useHostTheme,
} from "cursor/canvas";

const TARGETS = { kcal: 2000, protein: 120, fat: 65, carbs: 180 };
const CONSUMED = { kcal: 760, protein: 85, fat: 42, carbs: 98 };

function CalorieRing({
  remaining,
  target,
  size = 120,
}: {
  remaining: number;
  target: number;
  size?: number;
}) {
  const theme = useHostTheme();
  const consumed = target - remaining;
  const progress = target > 0 ? consumed / target : 0;
  const stroke = 10;
  const radius = (size - stroke) / 2;
  const circumference = 2 * Math.PI * radius;
  const dash = circumference * Math.min(progress, 1);

  return (
    <div style={{ position: "relative", width: size, height: size }}>
      <svg width={size} height={size} style={{ transform: "rotate(-90deg)" }}>
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke={theme.fill.tertiary}
          strokeWidth={stroke}
        />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke={theme.accent.primary}
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={`${dash} ${circumference - dash}`}
        />
      </svg>
      <div
        style={{
          position: "absolute",
          inset: 0,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <Text
          weight="bold"
          style={{ fontSize: 28, lineHeight: 1, color: theme.text.primary }}
        >
          {remaining}
        </Text>
        <Text size="small" tone="secondary">
          ккал осталось
        </Text>
      </div>
    </div>
  );
}

function MacroDots({
  label,
  current,
  target,
  color,
}: {
  label: string;
  current: number;
  target: number;
  color: "blue" | "orange" | "purple";
}) {
  const theme = useHostTheme();
  const filled = Math.round((current / target) * 5);

  return (
    <Stack gap={4} style={{ alignItems: "center" }}>
      <Text size="small" tone="tertiary">
        {label}
      </Text>
      <Row gap={3}>
        {Array.from({ length: 5 }).map((_, i) => (
          <div
            key={i}
            style={{
              width: 8,
              height: 8,
              borderRadius: 4,
              background:
                i < filled
                  ? theme.palette[color]
                  : theme.fill.tertiary,
            }}
          />
        ))}
      </Row>
      <Text size="small" weight="semibold">
        {current}/{target}
      </Text>
    </Stack>
  );
}

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
      <div
        style={{
          height: 28,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <div
          style={{
            width: 80,
            height: 6,
            borderRadius: 3,
            background: theme.fill.tertiary,
          }}
        />
      </div>
      {children}
    </div>
  );
}

function PhoneScreen() {
  const theme = useHostTheme();
  const remaining = TARGETS.kcal - CONSUMED.kcal;
  const dayProgress = Math.round((CONSUMED.kcal / TARGETS.kcal) * 100);

  return (
    <PhoneFrame>
      <div style={{ flex: 1, overflow: "auto", padding: "0 16px 8px" }}>
        <Stack gap={12}>
          <Row align="center" justify="space-between">
            <Stack gap={2}>
              <Text weight="semibold">Доброе утро, Алексей</Text>
              <Text size="small" tone="secondary">
                Среда, 8 июля
              </Text>
            </Stack>
            <Row gap={4}>
              <div
                style={{
                  width: 32,
                  height: 32,
                  borderRadius: 16,
                  background: theme.fill.secondary,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                <Text size="small" tone="tertiary">
                  ...
                </Text>
              </div>
            </Row>
          </Row>

          <Card variant="filled">
            <CardBody>
              <Row gap={16} align="center">
                <CalorieRing remaining={remaining} target={TARGETS.kcal} />
                <Stack gap={8} style={{ flex: 1 }}>
                  <Text size="small" tone="secondary">
                    Прогресс дня
                  </Text>
                  <UsageBar
                    total={100}
                    segments={[
                      { id: "done", value: dayProgress, color: "green" },
                    ]}
                    topLeftLabel={`${dayProgress}%`}
                    topRightLabel={`${CONSUMED.kcal} / ${TARGETS.kcal} ккал`}
                  />
                  <Row justify="space-between">
                    <MacroDots
                      label="Белки"
                      current={CONSUMED.protein}
                      target={TARGETS.protein}
                      color="blue"
                    />
                    <MacroDots
                      label="Жиры"
                      current={CONSUMED.fat}
                      target={TARGETS.fat}
                      color="orange"
                    />
                    <MacroDots
                      label="Углев."
                      current={CONSUMED.carbs}
                      target={TARGETS.carbs}
                      color="purple"
                    />
                  </Row>
                </Stack>
              </Row>
            </CardBody>
          </Card>

          <Grid columns={4} gap={6}>
            <Stat
              label="ккал"
              value={String(remaining)}
              tone="info"
              style={{ textAlign: "center" }}
            />
            <Stat
              label="Б"
              value={`${CONSUMED.protein}/${TARGETS.protein}`}
              style={{ textAlign: "center" }}
            />
            <Stat
              label="Ж"
              value={`${CONSUMED.fat}/${TARGETS.fat}`}
              style={{ textAlign: "center" }}
            />
            <Stat
              label="У"
              value={`${CONSUMED.carbs}/${TARGETS.carbs}`}
              style={{ textAlign: "center" }}
            />
          </Grid>

          <Card>
            <CardHeader trailing={<Pill tone="info" size="sm">ИИ</Pill>}>
              Что съесть на обед?
            </CardHeader>
            <CardBody>
              <Stack gap={6}>
                <Text weight="semibold">Куриная грудка с гречкой</Text>
                <Text size="small" tone="secondary">
                  420 ккал · Б 38 · Ж 8 · У 45 · ~25 мин
                </Text>
                <Row gap={8}>
                  <Button variant="primary">Добавить</Button>
                  <Button variant="ghost">Другие варианты</Button>
                </Row>
              </Stack>
            </CardBody>
          </Card>

          <Stack gap={0}>
            <CollapsibleSection
              title="Завтрак"
              leading={<Swatch color="yellow" />}
              trailing={
                <Text size="small" tone="tertiary">
                  320 / 400
                </Text>
              }
            >
              <Stack gap={4} style={{ paddingLeft: 24 }}>
                <Text size="small">Омлет 2 яйца · 180 ккал</Text>
                <Text size="small">Кофе с молоком · 140 ккал</Text>
              </Stack>
            </CollapsibleSection>
            <Divider />
            <CollapsibleSection
              title="Обед"
              leading={<Swatch color="orange" />}
              trailing={
                <Pill tone="success" size="sm">
                  выполнен
                </Pill>
              }
            >
              <Stack gap={4} style={{ paddingLeft: 24 }}>
                <Text size="small">Куриный суп · 280 ккал</Text>
                <Text size="small">Салат · 300 ккал</Text>
              </Stack>
            </CollapsibleSection>
            <Divider />
            <CollapsibleSection
              title="Ужин"
              leading={<Swatch color="purple" />}
              trailing={
                <Text size="small" tone="tertiary">
                  0 / 500
                </Text>
              }
            >
              <Stack gap={4} style={{ paddingLeft: 24 }}>
                <Text size="small" tone="secondary" italic>
                  Перенос: +340 ккал · Б 35 · Ж 23 · У 82
                </Text>
                <Text size="small" tone="tertiary">
                  Нет записей
                </Text>
              </Stack>
            </CollapsibleSection>
            <Divider />
            <CollapsibleSection
              title="Перекус"
              leading={<Swatch color="green" />}
              trailing={
                <Text size="small" tone="tertiary">
                  0 / 200
                </Text>
              }
            >
              <Text size="small" tone="tertiary" style={{ paddingLeft: 24 }}>
                Нет записей
              </Text>
            </CollapsibleSection>
          </Stack>

          <Card variant="filled">
            <CardHeader>ИИ-ассистент</CardHeader>
            <CardBody>
              <Stack gap={8}>
                <Text size="small" tone="secondary">
                  Дефицит: 340 ккал, 35 г белка до цели дня
                </Text>
                <Row gap={8}>
                  <Button variant="primary">Рецепты</Button>
                  <Button variant="secondary">Перекрёсток</Button>
                </Row>
              </Stack>
            </CardBody>
          </Card>
        </Stack>
      </div>

      <div
        style={{
          borderTop: `1px solid ${theme.stroke.tertiary}`,
          padding: "8px 12px 16px",
          background: theme.bg.chrome,
        }}
      >
        <Row justify="space-around" align="center">
          {[
            { label: "Дневник", active: true },
            { label: "Поиск", active: false },
            { label: "+", active: false, accent: true },
            { label: "ИИ", active: false },
            { label: "Профиль", active: false },
          ].map((tab) => (
            <Stack key={tab.label} gap={2} style={{ alignItems: "center" }}>
              <div
                style={{
                  width: tab.accent ? 40 : 24,
                  height: tab.accent ? 40 : 24,
                  borderRadius: tab.accent ? 20 : 0,
                  background: tab.accent
                    ? theme.accent.primary
                    : "transparent",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                <Text
                  size="small"
                  weight={tab.active || tab.accent ? "semibold" : "normal"}
                  style={
                    tab.accent
                      ? { color: theme.text.onAccent }
                      : tab.active
                        ? { color: theme.accent.primary }
                        : undefined
                  }
                >
                  {tab.label}
                </Text>
              </div>
              {!tab.accent && (
                <Text
                  size="small"
                  tone={tab.active ? "primary" : "tertiary"}
                  style={
                    tab.active ? { color: theme.accent.primary } : undefined
                  }
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

function Annotation({
  title,
  children,
}: {
  title: string;
  children: import("react").ReactNode;
}) {
  return (
    <Stack gap={4}>
      <Text weight="semibold">{title}</Text>
      <Text size="small" tone="secondary">
        {children}
      </Text>
    </Stack>
  );
}

export default function HybridDesignMockup() {
  const theme = useHostTheme();

  return (
    <Stack gap={24} style={{ padding: 24, maxWidth: 960 }}>
      <Stack gap={8}>
        <H1>Гибрид 2+3: Lifesum + Cronometer</H1>
        <Text tone="secondary">
          Макет главного экрана «Дневник питания» — wellness-эстетика с
          pro-dashboard и встроенным ИИ-ассистентом.
        </Text>
      </Stack>

      <Row gap={32} align="start" wrap>
        <PhoneScreen />

        <Stack gap={20} style={{ flex: 1, minWidth: 280 }}>
          <H2>Зоны экрана</H2>

          <Annotation title="1. Приветствие (Вариант 2)">
            Персональное «Доброе утро» + дата вместо сухого AppBar. Создаёт
            ощущение wellness-приложения, а не таблицы.
          </Annotation>

          <Annotation title="2. Hero-карточка (Вариант 2)">
            Кольцо оставшихся калорий — главный фокус. Точки вместо 4 progress
            bar: меньше шума, тот же смысл. Прогресс дня одной полосой.
          </Annotation>

          <Annotation title="3. Dashboard grid (Вариант 3)">
            4 метрики на одном взгляде для продвинутых пользователей. Дублирует
            hero, но в компактном виде — можно свайпнуть/скрыть.
          </Annotation>

          <Annotation title="4. ИИ-карточка (Вариант 2)">
            Рекомендация встроена в дневник, не спрятана за кнопкой. Превью
            блюда + быстрое добавление.
          </Annotation>

          <Annotation title="5. Accordion приёмы (Вариант 3)">
            Сворачиваемые секции с rollover-дефицитом в заголовке. Видно
            «Перенос: +340 ккал» без лишнего текста.
          </Annotation>

          <Annotation title="6. ИИ-панель (Вариант 3)">
            Постоянный контекст дефицита + табы «Рецепты» / «Перекрёсток».
            Уникальная фича всегда на виду.
          </Annotation>

          <Divider />

          <H3>Палитра (Flutter)</H3>
          <Grid columns={2} gap={8}>
            <Row gap={8} align="center">
              <div
                style={{
                  width: 20,
                  height: 20,
                  borderRadius: 4,
                  background: "#2ECC9A",
                }}
              />
              <Text size="small">Primary mint #2ECC9A</Text>
            </Row>
            <Row gap={8} align="center">
              <div
                style={{
                  width: 20,
                  height: 20,
                  borderRadius: 4,
                  background: "#FAF8F5",
                  border: `1px solid ${theme.stroke.tertiary}`,
                }}
              />
              <Text size="small">Background cream #FAF8F5</Text>
            </Row>
            <Row gap={8} align="center">
              <div
                style={{
                  width: 20,
                  height: 20,
                  borderRadius: 4,
                  background: "#4A90D9",
                }}
              />
              <Text size="small">Protein blue</Text>
            </Row>
            <Row gap={8} align="center">
              <div
                style={{
                  width: 20,
                  height: 20,
                  borderRadius: 4,
                  background: "#1A1A2E",
                }}
              />
              <Text size="small">Dark surface #1A1A2E</Text>
            </Row>
          </Grid>
        </Stack>
      </Row>
    </Stack>
  );
}
