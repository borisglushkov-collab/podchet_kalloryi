from food_qty import quantity_fields


def test_mealty_four_units_are_servings_not_four_trays():
    q = quantity_fields({"grams": 4.0, "calories": 660})
    assert q["qty_is_servings"] is True
    assert q["units"] == 4.0
    assert "ед. FatSecret" in q["qty_label"]
    assert q["grams_estimated"] is None


def test_cucumber_grams_stay_grams():
    q = quantity_fields({"grams": 150})
    assert q["qty_is_servings"] is False
    assert q["qty_label"] == "150 г"
    assert q["grams_estimated"] == 150


def test_description_100g_serving_estimates_pack():
    q = quantity_fields({"number_of_units": 4, "food_entry_description": "100 g"})
    assert q["grams_estimated"] == 400.0
    assert q["qty_label"] == "400 г"
    assert q["qty_is_servings"] is False


def test_cheese_fractional_serving():
    q = quantity_fields({"grams": 0.3})
    assert q["qty_is_servings"] is True
    assert q["qty_label"].startswith("×0.3")


def test_weighed_item_with_same_grams_in_description():
    """Cucumber: units=192 and desc '192 g' must stay 192 г, not 192×192."""
    q = quantity_fields({"grams": 192, "food_entry_description": "192 g"})
    assert q["qty_is_servings"] is False
    assert q["qty_label"] == "192 г"
    assert q["grams_estimated"] == 192


def test_servings_description_uses_100g_like_fatsecret_app():
    tomatoes = quantity_fields(
        {
            "number_of_units": 1.3,
            "food_entry_description": "1.3 servings Пятерочка Помидоры",
        }
    )
    assert tomatoes["qty_label"] == "130 г"
    assert tomatoes["grams_estimated"] == 130.0
    assert tomatoes["qty_is_servings"] is False

    kebab = quantity_fields(
        {
            "number_of_units": 1.23,
            "food_entry_description": "1.23 servings Мираторг Шашлык из Свиной Шейки",
        }
    )
    assert kebab["units"] == 1.23
    assert kebab["qty_label"] == "123 г"
    assert kebab["grams_estimated"] == 123.0


def test_metric_serving_grams_from_api():
    q = quantity_fields(
        {
            "number_of_units": 1,
            "food_entry_description": "1 medium Банан",
            "metric_serving_grams": 118,
        }
    )
    assert q["qty_label"] == "118 г"
    assert q["grams_estimated"] == 118.0
