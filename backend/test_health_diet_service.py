"""Tests for health-diet.ru food mapping."""

from health_diet_service import _map_item, _relevance_score


def test_map_item_grechka():
    item = _map_item(
        {
            "i": 79,
            "ns": {"ru": {"name": "Гречневая крупа ядрица"}},
            "c": 308,
            "p": 12.6,
            "t": 3.3,
            "h": 57.1,
        }
    )
    assert item is not None
    assert item["name"] == "Гречневая крупа ядрица"
    assert item["kcal_per_100g"] == 308
    assert item["protein_per_100g"] == 12.6
    assert item["fat_per_100g"] == 3.3
    assert item["carbs_per_100g"] == 57.1
    assert item["source"] == "health_diet"
    assert item["url"].endswith("/79.php")


def test_relevance_prefers_prefix():
    assert _relevance_score("Гречка варёная", "гречка") > _relevance_score(
        "Йогурт греческий", "гречка"
    )


def test_relevance_matches_word_forms():
    assert _relevance_score("Гречневая крупа ядрица", "гречка") >= 45
    assert _relevance_score("Гречневая крупа ядрица", "гречка") > _relevance_score(
        "Йогурт греческий 2%", "гречка"
    )
