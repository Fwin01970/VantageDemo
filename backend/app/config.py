"""
Reads settings from the .env file so nothing is hardcoded in code.
"""
import os
from dotenv import load_dotenv

load_dotenv()

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
