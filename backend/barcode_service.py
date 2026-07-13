"""Barcode lookup via Open Food Facts."""

import logging
from typing import Any

import httpx

logger = logging.getLogger(__name__)

OFF_PRODUCT_URL = "https://world.openfoodfacts.org/api/v2/product/{barcode}.json"


def _num(value: Any) -> float:
    if value is None:
        return 0.0
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value).replace(",", "."))
    except ValueError:
        return 0.0


def _map_product(barcode: str, product: dict[str, Any]) -> dict[str, Any]:
    nutriments = product.get("nutriments") or {}
    name = (
        product.get("product_name_ru")
        or product.get("product_name")
        or product.get("generic_name_ru")
        or product.get("generic_name")
        or f"Продукт {barcode}"
    )
    brand = product.get("brands") or None
    if brand and "," in brand:
        brand = brand.split(",")[0].strip()

    kcal = _num(
        nutriments.get("energy-kcal_100g")
        or nutriments.get("energy_100g")
        or nutriments.get("energy-kcal")
    )
    if kcal <= 0 and nutriments.get("energy-kj_100g"):
        kcal = _num(nutriments.get("energy-kj_100g")) / 4.184

    return {
        "name": str(name).strip(),
        "brand": brand,
        "barcode": barcode,
        "kcal_per_100g": round(kcal, 1),
        "protein_per_100g": round(
            _num(nutriments.get("proteins_100g") or nutriments.get("proteins")), 1
        ),
        "fat_per_100g": round(
            _num(nutriments.get("fat_100g") or nutriments.get("fat")), 1
        ),
        "carbs_per_100g": round(
            _num(nutriments.get("carbohydrates_100g") or nutriments.get("carbohydrates")),
            1,
        ),
        "suggested_grams": 100.0,
        "source": "openfoodfacts",
        "image_url": product.get("image_front_url") or product.get("image_url"),
    }


async def lookup_barcode(barcode: str) -> dict[str, Any] | None:
    code = "".join(ch for ch in barcode if ch.isdigit())
    if len(code) < 8:
        return None

    headers = {"User-Agent": "PodchetKalloriy/1.4 (contact@example.com)"}
    async with httpx.AsyncClient(timeout=20.0, headers=headers) as client:
        response = await client.get(OFF_PRODUCT_URL.format(barcode=code))
        if response.status_code == 404:
            return None
        response.raise_for_status()
        data = response.json()

    if data.get("status") != 1:
        return None
    product = data.get("product")
    if not isinstance(product, dict):
        return None
    return _map_product(code, product)
