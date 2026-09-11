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
    assert "400" in q["qty_label"]
    assert q["qty_is_servings"] is False


def test_cheese_fractional_serving():
    q = quantity_fields({"grams": 0.3})
    assert q["qty_is_servings"] is True
    assert q["qty_label"].startswith("×0.3")
