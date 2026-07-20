"""Tests for barcode mapping and Open Food Facts text search helpers."""

from barcode_service import _map_product


def test_map_product_russian_name():
    item = _map_product(
        "4607025392134",
        {
            "product_name_ru": "Творог 5%",
            "brands": "Простоквашино",
            "nutriments": {
                "energy-kcal_100g": 121,
                "proteins_100g": 16,
                "fat_100g": 5,
                "carbohydrates_100g": 3,
            },
        },
    )
    assert item is not None
    assert item["name"] == "Творог 5% (Простоквашино)"
    assert item["brand"] == "Простоквашино"
    assert item["kcal_per_100g"] == 121
    assert item["protein_per_100g"] == 16
    assert item["source"] == "openfoodfacts"


def test_map_product_skips_without_kcal():
    item = _map_product(
        None,
        {
            "product_name": "Empty",
            "brands": "X",
            "nutriments": {},
        },
    )
    assert item is None


def test_map_product_includes_brand_in_name_for_search():
    item = _map_product(
        None,
        {
            "product_name_ru": "Куриные тефтельки",
            "brands": "Милти",
            "nutriments": {
                "energy-kcal_100g": 152,
                "proteins_100g": 10,
                "fat_100g": 8,
                "carbohydrates_100g": 9,
            },
        },
    )
    assert item is not None
    assert "Милти" in item["name"]
    assert item["brand"] == "Милти"
