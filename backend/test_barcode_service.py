"""Tests for barcode mapping."""

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
    assert item["name"] == "Творог 5%"
    assert item["brand"] == "Простоквашино"
    assert item["kcal_per_100g"] == 121
    assert item["protein_per_100g"] == 16
