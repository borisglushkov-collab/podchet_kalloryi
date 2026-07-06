"""Perekrestok product search and link enrichment."""

import asyncio
import logging
from urllib.parse import quote

logger = logging.getLogger(__name__)


def search_url(product_name: str) -> str:
    return f"https://www.perekrestok.ru/cat/search?search={quote(product_name)}"


async def enrich_product(product: dict, city: str = "Москва") -> dict:
    name = product.get("name", "")
    enriched = {
        "name": name,
        "store": "Перекрёсток",
        "reason": product.get("reason", ""),
        "price_rub": None,
        "url": search_url(name),
        "image_url": None,
    }

    try:
        from perekrestok_api import PerekrestokAPI

        async with PerekrestokAPI() as api:
            if city:
                try:
                    geo = await api.Geolocation.search(city)
                    items = geo.json().get("content", {}).get("items", [])
                    if items:
                        city_id = items[0]["id"]
                        shops = await api.Geolocation.Shop.on_map(city_id=city_id, limit=1)
                        shop_items = shops.json().get("content", {}).get("items", [])
                        if shop_items:
                            await api.Geolocation.Selection.shop(shop_items[0]["id"])
                except Exception as e:
                    logger.warning("Perekrestok geolocation failed: %s", e)

            results = await api.Catalog.search(query=name, entity_types=["product"])
            data = results.json()
            content = data.get("content", {})
            items = content.get("items", []) if isinstance(content, dict) else []
            if not items and isinstance(content, list):
                items = content
            if not items:
                return enriched

            item = items[0]
            product_data = item.get("product") or item
            product_id = product_data.get("id") or item.get("id")
            title = (
                product_data.get("title")
                or product_data.get("name")
                or item.get("title")
                or name
            )
            price_info = product_data.get("price") or item.get("price") or {}
            price = (
                price_info.get("current")
                or price_info.get("value")
                or price_info.get("amount")
            )
            image = product_data.get("image") or item.get("image")

            enriched["name"] = title
            if price is not None:
                enriched["price_rub"] = int(price) if isinstance(price, (int, float)) else None
            if product_id:
                enriched["url"] = f"https://www.perekrestok.ru/cat/p/{product_id}"
            if image:
                if isinstance(image, dict):
                    enriched["image_url"] = image.get("cropUrl") or image.get("url")
                elif isinstance(image, str):
                    enriched["image_url"] = image
    except Exception as e:
        logger.warning("Perekrestok search failed for '%s': %s", name, e)

    return enriched


async def enrich_products(products: list[dict], city: str = "Москва") -> list[dict]:
    tasks = [enrich_product(p, city) for p in products]
    return await asyncio.gather(*tasks)
