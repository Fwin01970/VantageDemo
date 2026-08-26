"""
Reads settings from the .env file so nothing is hardcoded in code.
"""
import os
from pathlib import Path
from dotenv import load_dotenv

# Explicit path instead of relying on python-dotenv's automatic search —
# that search depends on the current working directory the process was
# launched from, which silently breaks (finds nothing, or the WRONG
# .env if one exists elsewhere in the tree) depending on whether you ran
# uvicorn from backend/ vs backend/app/. This always loads the .env file
# that sits right next to this config.py, no matter where you run from.
load_dotenv(dotenv_path=Path(__file__).resolve().parent / ".env")

DATABASE_URL = os.getenv("DATABASE_URL")
FAKE_AUTH_SECRET = os.getenv("FAKE_AUTH_SECRET", "local-dev-only-not-a-real-secret")

# ── Databricks (Phase 2) ────────────────────────────────────────────────
# Only the SECRET lives here now. Everything else (host, warehouse ID,
# Genie space ID) is resolved per-tenant from the data_source_connections
# table — see app/services/data_source_resolver.py. This variable name
# must match whatever a tenant's `secret_ref` column points at.
DATABRICKS_PAT = os.getenv("DATABRICKS_PAT")

# ── LLM providers (fallback chain) ──────────────────────────────────────
# Tried in this order: Ollama (free/local) -> Anthropic -> OpenAI.
# Leave any of these blank/unset and that provider is simply skipped.
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.1")
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")
ANTHROPIC_MODEL = os.getenv("ANTHROPIC_MODEL", "claude-3-5-haiku-20241022")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
# Google deprecates model versions frequently — if this default (or your
# own GEMINI_MODEL in .env) ever starts returning 404 "no longer
# available", check https://generativelanguage.googleapis.com/v1beta/models?key=YOUR_KEY
# for the current name and update here/your .env.
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-3.6-flash")

# ── Per-user credentials / secret store ─────────────────────────────────
# See CREDENTIAL_MANAGEMENT_DESIGN.md. "local" (default) needs only
# SECRET_STORE_MASTER_KEY — generate one with:
#   python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
# "azure_key_vault" needs AZURE_KEY_VAULT_URL and a real Azure identity
# (Managed Identity in Azure, or `az login` locally) — see secret_store.py
# for the honesty note on how thoroughly that path has actually been
# tested versus just reasoned through.
SECRET_STORE_BACKEND = os.getenv("SECRET_STORE_BACKEND", "local")
SECRET_STORE_MASTER_KEY = os.getenv("SECRET_STORE_MASTER_KEY")
AZURE_KEY_VAULT_URL = os.getenv("AZURE_KEY_VAULT_URL")

if not DATABASE_URL:
    raise RuntimeError(
        "DATABASE_URL is not set. Copy backend/.env.example to backend/.env "
        "and fill in your Postgres password."
    )

# ── Real authentication (password + OAuth) ──────────────────────────────
# FRONTEND_BASE_URL/BACKEND_BASE_URL matter for OAuth redirect URIs — the
# URI registered with each provider's app console must match exactly.
FRONTEND_BASE_URL = os.getenv("FRONTEND_BASE_URL", "http://localhost:5173")
BACKEND_BASE_URL = os.getenv("BACKEND_BASE_URL", "http://localhost:8000")

# Account lockout after repeated failed password attempts.
ACCOUNT_LOCK_THRESHOLD = int(os.getenv("ACCOUNT_LOCK_THRESHOLD", "5"))
ACCOUNT_LOCK_MINUTES = int(os.getenv("ACCOUNT_LOCK_MINUTES", "15"))

# ── OAuth providers — fully wired, inactive until real credentials exist ──
# Each provider's entire flow (authorize -> callback -> token exchange ->
# find-or-create user) is implemented in auth/oauth_providers.py and
# routers/auth.py right now. GET /auth/providers reports which of these
# are configured, and the frontend only shows a button for a provider
# that's actually usable. Filling in real values here — no code changes —
# is the entire migration once Entra ID (or Google/GitHub/Facebook) app
# registrations exist.
MICROSOFT_CLIENT_ID = os.getenv("MICROSOFT_CLIENT_ID")
MICROSOFT_CLIENT_SECRET = os.getenv("MICROSOFT_CLIENT_SECRET")
# "common" accepts both personal and work/school Microsoft accounts;
# use "organizations" for work/school only, or a specific tenant GUID to
# restrict sign-in to just your own Entra ID directory.
MICROSOFT_TENANT = os.getenv("MICROSOFT_TENANT", "common")

GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID")
GOOGLE_CLIENT_SECRET = os.getenv("GOOGLE_CLIENT_SECRET")

GITHUB_CLIENT_ID = os.getenv("GITHUB_CLIENT_ID")
GITHUB_CLIENT_SECRET = os.getenv("GITHUB_CLIENT_SECRET")

FACEBOOK_CLIENT_ID = os.getenv("FACEBOOK_CLIENT_ID")
FACEBOOK_CLIENT_SECRET = os.getenv("FACEBOOK_CLIENT_SECRET")

# Signs the short-lived OAuth "state" parameter (CSRF protection for the
# redirect round-trip) — reuses FAKE_AUTH_SECRET rather than introducing
# a second secret to manage, since both are local-only signing keys with
# the same trust boundary.
OAUTH_STATE_SECRET = FAKE_AUTH_SECRET
