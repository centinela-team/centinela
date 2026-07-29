from config_merge import resolve_config


def test_no_doc_falls_back_to_env():
    t, r = resolve_config(None, 60, {"7995"})
    assert (t, r) == (60, {"7995"})


def test_doc_overrides_both_fields():
    t, r = resolve_config({"threshold": 70, "riskyCategories": ["1111", "2222"]}, 60, {"7995"})
    assert (t, r) == (70, {"1111", "2222"})


def test_doc_partial_threshold_only_keeps_env_categories():
    t, r = resolve_config({"threshold": 70}, 60, {"7995"})
    assert (t, r) == (70, {"7995"})


def test_empty_categories_list_is_respected_not_treated_as_missing():
    t, r = resolve_config({"threshold": 60, "riskyCategories": []}, 60, {"7995"})
    assert r == set()
