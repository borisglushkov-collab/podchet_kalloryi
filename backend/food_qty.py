"""FatSecret quantity is number_of_units, not always grams.

Coaches kept reading `grams: 4.0` as four Mealty trays. In the diary that is
usually 4 × 100 g servings = one 400 g pack. Values ≥20 are treated as grams.
"""

from __future__ import annotations

import re
from typing import Any

_GRAMS_IN_DESC = re.compile(
    r"(\d+(?:[.,]\d+)?)\s*(?:г|гр|g|gram|grams)\b",
    re.IGNORECASE,
)

SERVING_UNITS_MAX = 20.0


def _as_float(val: Any) -> float:
    try:
        return float(val or 0)
    except (TypeError, ValueError):
        return 0.0


def quantity_fields(entry: dict[str, Any]) -> dict[str, Any]:
    """Return units / qty_label / qty_is_servings for a food diary row."""
    units = _as_float(
        entry.get("number_of_units")
        if entry.get("number_of_units") not in (None, "", 0, 0.0)
        else entry.get("units")
        if entry.get("units") not in (None, "", 0, 0.0)
        else entry.get("grams")
    )
    desc = str(entry.get("food_entry_description") or entry.get("serving_description") or "").strip()
    grams_from_desc = None
    match = _GRAMS_IN_DESC.search(desc)
    if match:
        per = float(match.group(1).replace(",", "."))
        grams_from_desc = round(units * per, 1) if units else round(per, 1)

    qty_is_servings = 0 < units < SERVING_UNITS_MAX and grams_from_desc is None
    grams_estimated = grams_from_desc
    if grams_estimated is None and units >= SERVING_UNITS_MAX:
        grams_estimated = round(units, 1)

    if grams_from_desc is not None and units:
        per = grams_from_desc / units if units else grams_from_desc
        qty_label = f"{units:g} × {per:g} г ≈ {grams_from_desc:g} г"
    elif qty_is_servings:
        qty_label = f"×{units:g} ед. FatSecret"
    elif grams_estimated is not None:
        qty_label = f"{grams_estimated:g} г"
    else:
        qty_label = ""

    out: dict[str, Any] = {
        "units": round(units, 1),
        "qty_label": qty_label,
        "qty_is_servings": qty_is_servings,
        "grams_estimated": grams_estimated,
    }
    if desc:
        out["serving_description"] = desc
    return out
