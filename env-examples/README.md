# Environment file templates

This repo intentionally does **not** commit real `.env*` files because they contain secrets.

Use the templates in this folder as starting points:

- `aurora.env.example` → copy to repo root as `.env.aurora` then `source .env.aurora`
- `k6.env.example` → copy to repo root as `.env` (for k6 compose scripts) then export/source

Notes:
- `.env.aurora` is created/updated automatically by:
  - `scripts/setup-aurora-connection.sh`
  - `terraform/scripts/rotate-aurora-password.sh`
  - `terraform/scripts/rollback-aurora-password.sh`
- `.env` is used by some local/docker testing scripts (k6 stack).


