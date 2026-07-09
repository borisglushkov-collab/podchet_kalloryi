import {
  Button,
  Card,
  CardBody,
  Divider,
  Grid,
  H1,
  H2,
  H3,
  Pill,
  Row,
  Stack,
  Swatch,
  Text,
  useHostTheme,
} from "cursor/canvas";

const TARGETS = { kcal: 2000, protein: 120, fat: 65, carbs: 180 };
const CONSUMED = { kcal: 760, protein: 85, fat: 42, carbs: 98 };

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

function CalorieRing({
  remaining,
  target,
  size = 140,
}: {
  remaining: number;
  target: number;
  size?: number;
}) {
  const theme = useHostTheme();
  const consumed = target - remaining;
  const progress = target > 0 ? consumed / target : 0;
  const stroke = 12;
  const radius = (size - stroke) / 2;
  const circumference = 2 * Math.PI * radius;
  const dash = circumference * Math.min(progress, 1);

  return (
    <div style={{ position: "relative", width: size, height: size }}>
      <svg width={size} height={size} style={{ transform: "rotate(-90deg)" }}>
        <circle cx={size / 2} cy={size / 2} r={radius} fill="none" stroke={theme.fill.tertiary} strokeWidth={stroke} />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke={theme.palette.blue}
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={`${dash} ${circumference - dash}`}
        />
      </svg>
      <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center" }}>
        <Text weight="bold" style={{ fontSize: 32, lineHeight: 1 }}>{remaining}</Text>
        <Text size="small" tone="secondary">осталось</Text>
      </div>
    </div>
  );
}

function MealRow({
  label,
  color,
  kcal,
  target,
  items,
}: {
  label: string;
  color: "yellow" | "orange" | "purple" | "green";
  kcal: number;
  target: number;
  items: string[];
}) {
  const theme = useHostTheme();
  return (
    <Stack gap={0}>
      <Row align="center" style={{ padding: "10px 0" }}>
        <Swatch color={color} />
        <Stack gap={2} style={{ flex: 1, marginLeft: 10 }}>
          <Row justify="space-between" align="center">
            <Text weight="semibold">{label}</Text>
            <Text size="small" tone="secondary">{kcal} / {target} ккал</Text>
          </Row>
        </Stack>
        <div
          style={{
            width: 28,
            height: 28,
            borderRadius: 14,
            border: `1px solid ${theme.stroke.secondary}`,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <Text size="small" tone="secondary">+</Text>
        </div>
      </Row>
      {items.map((item) => (
        <Row key={item} style={{ paddingLeft: 22, paddingBottom: 6 }}>
          <Text size="small" tone="secondary">{item}</Text>
        </Row>
      ))}
      <Divider />
    </Stack>
  );
}

function PhoneScreen() {
  const theme = useHostTheme();
  const remaining = TARGETS.kcal - CONSUMED.kcal;

  return (
    <PhoneFrame>
      <div style={{ flex: 1, overflow: "auto" }}>
        <Row align="center" justify="space-between" style={{ padding: "8px 12px" }}>
          <Text size="small" tone="tertiary">{"<"}</Text>
          <Text weight="semibold">Среда, 8 июля</Text>
          <Text size="small" tone="tertiary">{">"}</Text>
        </Row>

        <Stack gap={16} style={{ padding: "0 16px 16px", alignItems: "center" }}>
          <CalorieRing remaining={remaining} target={TARGETS.kcal} />

          <Row gap={16} justify="center" style={{ width: "100%" }}>
            <Stack gap={2} style={{ alignItems: "center" }}>
              <Text size="small" tone="tertiary">Белки</Text>
              <Text weight="semibold" style={{ color: theme.palette.blue }}>
                {CONSUMED.protein}г
              </Text>
            </Stack>
            <Stack gap={2} style={{ alignItems: "center" }}>
              <Text size="small" tone="tertiary">Жиры</Text>
              <Text weight="semibold" style={{ color: theme.palette.orange }}>
                {CONSUMED.fat}г
              </Text>
            </Stack>
            <Stack gap={2} style={{ alignItems: "center" }}>
              <Text size="small" tone="tertiary">Углев.</Text>
              <Text weight="semibold" style={{ color: theme.palette.purple }}>
                {CONSUMED.carbs}г
              </Text>
            </Stack>
          </Row>

          <Row gap={4} style={{ width: "100%" }}>
            {[
              { color: theme.palette.blue, pct: CONSUMED.protein / TARGETS.protein },
              { color: theme.palette.orange, pct: CONSUMED.fat / TARGETS.fat },
              { color: theme.palette.purple, pct: CONSUMED.carbs / TARGETS.carbs },
            ].map((bar, i) => (
              <div key={i} style={{ flex: 1, height: 4, borderRadius: 2, background: theme.fill.tertiary, overflow: "hidden" }}>
                <div style={{ width: `${Math.min(bar.pct * 100, 100)}%`, height: "100%", background: bar.color, borderRadius: 2 }} />
              </div>
            ))}
          </Row>

          <Card variant="filled" style={{ width: "100%" }}>
            <CardBody>
              <Row justify="space-between" align="center">
                <Stack gap={2}>
                  <Text size="small" tone="secondary">ИИ-подсказка</Text>
                  <Text size="small">До цели: 340 ккал на ужин</Text>
                </Stack>
                <Button variant="secondary">Открыть</Button>
              </Row>
            </CardBody>
          </Card>

          <div style={{ width: "100%" }}>
            <Row justify="space-between" align="center" style={{ marginBottom: 8 }}>
              <Text weight="semibold">Приёмы пищи</Text>
              <Text size="small" tone="tertiary">760 / 2000 ккал</Text>
            </Row>
            <MealRow label="Завтрак" color="yellow" kcal={320} target={400} items={["Омлет 2 яйца · 180 ккал", "Кофе с молоком · 140 ккал"]} />
            <MealRow label="Обед" color="orange" kcal={580} target={600} items={["Куриный суп · 280 ккал", "Салат · 300 ккал"]} />
            <MealRow label="Ужин" color="purple" kcal={0} target={500} items={["Нет записей"]} />
            <MealRow label="Перекус" color="green" kcal={0} target={200} items={[]} />
          </div>
        </Stack>
      </div>

      <div style={{ borderTop: `1px solid ${theme.stroke.tertiary}`, padding: "8px 8px 16px", background: theme.bg.chrome }}>
        <Row justify="space-around">
          {[
            { label: "Дневник", active: true },
            { label: "Поиск", active: false },
            { label: "+", fab: true },
            { label: "Отчёт", active: false },
            { label: "Профиль", active: false },
          ].map((tab) => (
            <Stack key={tab.label} gap={2} style={{ alignItems: "center", minWidth: 48 }}>
              {tab.fab ? (
                <div style={{ width: 44, height: 44, borderRadius: 22, background: theme.palette.blue, display: "flex", alignItems: "center", justifyContent: "center" }}>
                  <Text weight="bold" style={{ color: theme.text.onAccent, fontSize: 20 }}>+</Text>
                </div>
              ) : (
                <>
                  <Text size="small" weight={tab.active ? "semibold" : "normal"} style={tab.active ? { color: theme.palette.blue } : undefined}>
                    {tab.label}
                  </Text>
                </>
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

export default function VariantMfpClassic() {
  const theme = useHostTheme();

  return (
    <Stack gap={24} style={{ padding: 24, maxWidth: 960 }}>
      <Stack gap={8}>
        <H1>Вариант A: MyFitnessPal / FatSecret</H1>
        <Text tone="secondary">
          Классический дневник — данные важнее декора. Привычный UX для 200M+ пользователей MFP.
        </Text>
        <Row gap={8}>
          <Pill tone="info" size="sm">Референс: MyFitnessPal</Pill>
          <Pill tone="neutral" size="sm">FatSecret</Pill>
        </Row>
      </Stack>

      <Row gap={32} align="start" wrap>
        <PhoneScreen />

        <Stack gap={20} style={{ flex: 1, minWidth: 280 }}>
          <H2>Ключевые решения</H2>

          <Annotation title="1. Кольцо калорий — единственный герой">
            Крупное кольцо по центру, цифра «осталось» — главный фокус. Никаких дублирующих progress bar.
          </Annotation>

          <Annotation title="2. Компактная строка макросов">
            Б / Ж / У одной строкой с цветными цифрами и тонкими полосками — как в MFP Nutrition tab.
          </Annotation>

          <Annotation title="3. Плоский список приёмов">
            Без Card-обёрток: разделители, цветные Swatch-метки, кнопка «+» справа. Максимум плотности данных.
          </Annotation>

          <Annotation title="4. ИИ — вторичная подсказка">
            Компактный баннер, не hero. Пользователь MFP пришёл логировать еду, не читать советы.
          </Annotation>

          <Annotation title="5. Навигация 5 вкладок">
            Дневник · Поиск · FAB + · Отчёт · Профиль — стандарт MFP/Lose It.
          </Annotation>

          <Divider />

          <H3>Палитра (Flutter)</H3>
          <Grid columns={2} gap={8}>
            <Row gap={8} align="center">
              <div style={{ width: 20, height: 20, borderRadius: 4, background: "#0072CE" }} />
              <Text size="small">Accent blue #0072CE</Text>
            </Row>
            <Row gap={8} align="center">
              <div style={{ width: 20, height: 20, borderRadius: 4, background: "#FFFFFF", border: `1px solid ${theme.stroke.tertiary}` }} />
              <Text size="small">Background white</Text>
            </Row>
            <Row gap={8} align="center">
              <div style={{ width: 20, height: 20, borderRadius: 4, background: "#F5F5F5", border: `1px solid ${theme.stroke.tertiary}` }} />
              <Text size="small">Surface gray #F5F5F5</Text>
            </Row>
            <Row gap={8} align="center">
              <div style={{ width: 20, height: 20, borderRadius: 4, background: "#333333" }} />
              <Text size="small">Text primary #333</Text>
            </Row>
          </Grid>

          <H3>Когда выбирать</H3>
          <Text size="small" tone="secondary">
            Максимальная конверсия для аудитории, привыкшей к MFP/FatSecret. Быстрый ввод, минимум обучения.
            AI и rollover — фоновые фичи, не на первом плане.
          </Text>
        </Stack>
      </Row>
    </Stack>
  );
}
