# Explicador de casos — Centinela (Semana 3)

Genera una explicación **determinista** (plantillas) a partir de `triggeredRules`
persistidos por el motor de scoring. **No usa LLM.**

## Uso en código

```python
from explainer import explain_case

text = explain_case(score=82, threshold=60, triggered_rules=[...])
```

## Integración

El `case-service` invoca el explicador **después** de abrir el caso (best-effort):
si falla, el caso queda OPEN sin explicación y se puede regenerar después.

## Tests

```powershell
cd backend\explanation-service
python -m pytest tests -q
```

## Backfill (SQLite)

```powershell
$env:PYTHONPATH = "$PWD;$PWD\..\case-service"
python backfill.py --transaction-id <uuid> --sqlite-path ..\case-service\data\cases.db
```
