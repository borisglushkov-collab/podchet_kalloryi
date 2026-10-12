"""FatSecret quantity is number_of_units, not always grams.

Coaches kept reading `grams: 4.0` as four Mealty trays. In the diary that is
usually servings of a food whose metric size is often 100 g (FatSecret custom
foods / RU brands). Values ≥20 are treated as grams. When the entry description
says «N servings» and no metric size is known, we assume 100 g per serving —
matching the FatSecret app (1.3 → 130 г, 1.23 → 123 г).
"""

from __future__ import annotations

import re
from typing import Any

_GRAMS_IN_DESC = re.compile(
    r"(\d+(?:[.,]\d+)?)\s*(?:г|гр|g|gram|grams)\b",
    re.IGNORECASE,
)
_SERVINGS_IN_DESC = re.compile(
    r"\b(?:servings?|порц(?:ия|ии|ий|ию)?)\b",
    re.IGNORECASE,
)

SERVING_UNITS_MAX = 20.0
DEFAULT_CUSTOM_SERVING_GRAMS = 100.0


def _as_float(val: Any) -> float:
    try:
        return float(val or 0)
    except (TypeError, ValueError):
        return 0.0


def _round_qty(val: float) -> float:
    """Keep serving fractions like 1.23; strip float noise."""
    return round(float(val), 3)


def quantity_fields(entry: dict[str, Any]) -> dict[str, Any]:
    """Return units / qty_label / qty_is_servings for a food diary row."""
    units = _as_float(
        entry.get("number_of_units")
        if entry.get("number_of_units") not in (None, "", 0, 0.0)
        else entry.get("units")
        if entry.get("units") not in (None, "", 0, 0.0)
        else entry.get("grams")
    )
    units = _round_qty(units)
    desc = str(entry.get("food_entry_description") or entry.get("serving_description") or "").strip()
    metric = _as_float(
        entry.get("metric_serving_grams")
        if entry.get("metric_serving_grams") not in (None, "", 0, 0.0)
        else entry.get("serving_grams")
    )

    grams_estimated = None
    # API metric size for the chosen serving (generic foods).
    if metric > 0 and 0 < units < SERVING_UNITS_MAX:
        grams_estimated = round(units * metric, 1)
    else:
        match = _GRAMS_IN_DESC.search(desc)
        # Only multiply description grams when units look like servings (<20).
        # Weighed items often have units=192 and desc="192 g" — already grams.
        if match and 0 < units < SERVING_UNITS_MAX:
            per = float(match.group(1).replace(",", "."))
            grams_estimated = round(units * per, 1) if units else round(per, 1)
        elif _SERVINGS_IN_DESC.search(desc) and 0 < units < SERVING_UNITS_MAX:
            # Custom/brand foods: FatSecret app shows N×100 г as grams.
            grams_estimated = round(units * DEFAULT_CUSTOM_SERVING_GRAMS, 1)
        elif units >= SERVING_UNITS_MAX:
            grams_estimated = round(units, 1)

    qty_is_servings = 0 < units < SERVING_UNITS_MAX and grams_estimated is None

    # Prefer plain grams like the FatSecret mobile diary.
    if grams_estimated is not None:
        qty_label = f"{grams_estimated:g} г"
    elif qty_is_servings:
        qty_label = f"×{units:g} ед. FatSecret"
    else:
        qty_label = ""

    out: dict[str, Any] = {
        "units": units,
        "qty_label": qty_label,
        "qty_is_servings": qty_is_servings,
        "grams_estimated": grams_estimated,
    }
    if desc:
        out["serving_description"] = desc
    return out
