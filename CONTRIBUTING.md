# Contributing

## Principles

- Keep changes aligned with the project specification.
- Do not commit secrets, credentials, connection strings, or local environment files.
- Document architectural decisions that affect cost, scalability, security, or operations.
- Prefer small, focused pull requests.

## Branches

Use short descriptive branch names:

- `feature/<scope>`
- `fix/<scope>`
- `docs/<scope>`
- `infra/<scope>`

## Pull Requests

Each pull request should include:

- Purpose of the change.
- Affected modules.
- Validation performed.
- Risks or follow-up work.

## Documentation

Architecture decisions should be recorded in `docs/decisions/`.
Event and API contracts should be documented in `contracts/` and mirrored in `docs/` when useful for readers.
