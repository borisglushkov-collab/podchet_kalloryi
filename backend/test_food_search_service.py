"""Tests for food search merge / brand relevance."""

from food_search_service import _merge_results, _relevance_score


def test_relevance_matches_brand_in_name():
    score = _relevance_score(
        "Куриные тефтельки (Милти)",
        "Милти",
        brand="Милти",
    )
    assert score >= 60


def test_merge_prefers_openfoodfacts_brand_hits():
    items = _merge_results(
        [
            [],
            [
                {
                    "name": "Куриные тефтельки (Милти)",
                    "brand": "Милти",
                    "kcal_per_100g": 152,
                    "protein_per_100g": 10,
                    "fat_per_100g": 8,
                    "carbs_per_100g": 9,
                    "source": "openfoodfacts",
                }
            ],
        ],
        "Милти",
        10,
    )
    assert len(items) == 1
    assert items[0]["source"] == "openfoodfacts"
    assert "Милти" in items[0]["name"]
