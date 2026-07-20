"""Barcode and text search via Open Food Facts."""

import logging
from typing import Any

import httpx

logger = logging.getLogger(__name__)

OFF_PRODUCT_URL = "https://world.openfoodfacts.org/api/v2/product/{barcode}.json"
OFF_SEARCH_URLS = (
    "https://ru.openfoodfacts.org/cgi/search.pl",
    "https://world.openfoodfacts.org/cgi/search.pl",
)
USER_AGENT = "PodchetKalloriy/1.4 (https://github.com/borisglushkov-collab/podchet_kalloryi)"
TIMEOUT = 15.0


def _num(value: Any) -> float:
    if value is None:
        return 0.0
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value).replace(",", "."))
    except ValueError:
        return 0.0


def _map_product(barcode: str | None, product: dict[str, Any]) -> dict[str, Any] | None:
    nutriments = product.get("nutriments") or {}
    name = (
        product.get("product_name_ru")
        or product.get("product_name")
        or product.get("generic_name_ru")
        or product.get("generic_name")
        or ""
    )
    name = str(name).strip()
    if not name:
        code = barcode or product.get("code") or ""
        name = f"Продукт {code}".strip() if code else ""
    if not name:
        return None

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
    if kcal <= 0:
        return None

    code = barcode or str(product.get("code") or "").strip() or None
    # Include brand in display name so search ranking and UI show it.
    display = f"{name} ({brand})" if brand and brand.lower() not in name.lower() else name
    item: dict[str, Any] = {
        "name": display,
        "brand": brand,
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
    if code:
        item["barcode"] = code
    return item


async def lookup_barcode(barcode: str) -> dict[str, Any] | None:
    code = "".join(ch for ch in barcode if ch.isdigit())
    if len(code) < 8:
        return None

    headers = {"User-Agent": USER_AGENT}
    async with httpx.AsyncClient(timeout=TIMEOUT, headers=headers) as client:
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


async def search_openfoodfacts(query: str, page_size: int = 20) -> list[dict]:
    """Text search for brands and packaged foods (e.g. Милти)."""
    q = query.strip()
    if len(q) < 2:
        return []

    params = {
        "search_terms": q,
        "search_simple": 1,
        "action": "process",
        "json": 1,
        "page_size": min(max(page_size, 1), 30),
    }
    headers = {"User-Agent": USER_AGENT}
    data: dict[str, Any] | None = None
    last_error: Exception | None = None
    for url in OFF_SEARCH_URLS:
        try:
            async with httpx.AsyncClient(timeout=TIMEOUT, headers=headers) as client:
                response = await client.get(url, params=params)
                response.raise_for_status()
                payload = response.json()
            if isinstance(payload, dict):
                data = payload
                break
        except Exception as exc:
            last_error = exc
            logger.warning("Open Food Facts search failed (%s): %s", url, exc)
            continue

    if data is None:
        if last_error:
            logger.warning("Open Food Facts search unavailable: %s", last_error)
        return []

    products = data.get("products") or []
    if not isinstance(products, list):
        return []

    results: list[dict] = []
    seen: set[str] = set()
    for product in products:
        if not isinstance(product, dict):
            continue
        item = _map_product(None, product)
        if not item:
            continue
        key = item["name"].lower()
        if key in seen:
            continue
        seen.add(key)
        results.append(item)
        if len(results) >= page_size:
            break
    return results
