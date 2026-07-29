"""Fusiona config de Cosmos con defaults de entorno — función pura, sin I/O."""

from __future__ import annotations

from typing import Any, Optional


def resolve_config(
    doc: Optional[dict[str, Any]],
    env_threshold: int,
    env_risky: set[str],
) -> tuple[int, set[str]]:
    """doc=None (aún no existe) -> defaults de entorno, sin romper despliegues previos.
    Una lista de categorías vacía en el doc se respeta (no cae a defaults)."""
    if not doc:
        return env_threshold, env_risky
    threshold = int(doc.get("threshold", env_threshold))
    categories = doc.get("riskyCategories")
    if categories is None:
        risky = env_risky
    else:
        risky = {str(c).strip() for c in categories if str(c).strip()}
    return threshold, risky
