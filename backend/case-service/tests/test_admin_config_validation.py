"""Tests de validación de AdminConfigRequest — puros, sin HTTP ni Cosmos."""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from api import AdminConfigRequest


def test_threshold_too_high_rejected():
    with pytest.raises(ValidationError):
        AdminConfigRequest(threshold=103, riskyCategories=[])


def test_threshold_zero_rejected():
    with pytest.raises(ValidationError):
        AdminConfigRequest(threshold=0, riskyCategories=[])


def test_threshold_at_bounds_accepted():
    assert AdminConfigRequest(threshold=1, riskyCategories=[]).threshold == 1
    assert AdminConfigRequest(threshold=102, riskyCategories=[]).threshold == 102


def test_valid_category_codes_accepted():
    r = AdminConfigRequest(threshold=60, riskyCategories=["7995", "51"])
    assert r.riskyCategories == ["7995", "51"]


def test_non_numeric_category_rejected():
    with pytest.raises(ValidationError):
        AdminConfigRequest(threshold=60, riskyCategories=["abc"])


def test_too_short_category_rejected():
    with pytest.raises(ValidationError):
        AdminConfigRequest(threshold=60, riskyCategories=["1"])


def test_empty_categories_list_accepted():
    r = AdminConfigRequest(threshold=60, riskyCategories=[])
    assert r.riskyCategories == []
