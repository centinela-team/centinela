"""Regenera explicación para un caso existente (p. ej. tras caída del explicador)."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from uuid import UUID

_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_ROOT / "explanation-service"))
sys.path.insert(0, str(_ROOT / "case-service"))

from explainer import explain_case  # noqa: E402
from sqlite_repository import SqliteCaseRepository  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description="Backfill de explicación de caso")
    parser.add_argument("--transaction-id", required=True)
    parser.add_argument(
        "--sqlite-path",
        default=os.environ.get("SQLITE_PATH", "./data/cases.db"),
    )
    args = parser.parse_args()

    repo = SqliteCaseRepository(args.sqlite_path)
    case = repo.get_case_by_transaction(args.transaction_id)
    if not case:
        raise SystemExit(f"Caso no encontrado para tx={args.transaction_id}")

    text = explain_case(
        score=int(case["score"]),
        threshold=int(case["threshold"]),
        triggered_rules=list(case.get("triggeredRules") or []),
    )
    repo.save_explanation(UUID(str(case["caseId"])), text)
    print(text)


if __name__ == "__main__":
    main()
