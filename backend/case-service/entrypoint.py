"""Entrypoint Container Apps: ROLE=worker|api."""

from __future__ import annotations

import os
import sys


def main() -> None:
    role = os.environ.get("ROLE", "api").strip().lower()
    if role == "worker":
        from worker import main as worker_main

        worker_main()
        return
    import uvicorn

    port = int(os.environ.get("PORT", "8010"))
    uvicorn.run("api:app", host="0.0.0.0", port=port, log_level="info")


if __name__ == "__main__":
    main()
