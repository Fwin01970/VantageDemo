"""
Secret Store
=============
One interface, so the rest of the app (credentials router, data source
resolver) never knows or cares whether a secret physically lives in a
local encrypted column or in Azure Key Vault. See
CREDENTIAL_MANAGEMENT_DESIGN.md §4 for the full reasoning.

Which implementation is active is controlled by SECRET_STORE_BACKEND in
config (defaults to "local"). Only "local" is verified working in this
environment — see the honesty note on AzureKeyVaultSecretStore below.
"""
from abc import ABC, abstractmethod
import base64
import uuid

from cryptography.fernet import Fernet, InvalidToken
from sqlalchemy import text
from sqlalchemy.orm import Session


class SecretStoreError(Exception):
    """Raised on any failure to store/retrieve/delete a secret. Callers
    must never include the plaintext secret in this exception's message —
    only the secret_ref (itself just an opaque id, safe to log)."""
    pass


class SecretStore(ABC):
    @abstractmethod
    def store(self, ref_prefix: str, plaintext: str) -> str:
        """Encrypts and stores `plaintext`, returns an opaque secret_ref
        to save in user_credentials. ref_prefix is just a hint for
        naming/organization (e.g. 'databricks-pat'), not the secret."""
        ...

    @abstractmethod
    def retrieve(self, secret_ref: str) -> str:
        """Returns the decrypted plaintext for a previously-stored ref."""
        ...

    @abstractmethod
    def delete(self, secret_ref: str) -> None:
        """Deletes a secret. Safe to call on an already-deleted ref."""
        ...

    def rotate(self, ref_prefix: str, old_secret_ref: str | None, new_plaintext: str) -> str:
        """
        Default rotation strategy, shared by every backend: store the NEW
        secret first, and only delete the OLD one after that succeeds.
        This is what makes rotation safe against a crash or error
        mid-operation — the user is never left with zero working
        credential, worst case they're left with the OLD one still valid
        a little longer than intended, never with NEITHER.
        """
        new_ref = self.store(ref_prefix, new_plaintext)
        if old_secret_ref:
            try:
                self.delete(old_secret_ref)
            except SecretStoreError:
                # Old secret failed to delete — not ideal, but the NEW
                # secret is already safely stored and will be what's used
                # going forward (user_credentials.*_secret_ref gets
                # updated to new_ref by the caller regardless). Orphaned
                # old secrets are a cleanup task, not a correctness bug.
                pass
        return new_ref


class LocalEncryptedSecretStore(SecretStore):
    """
    Default implementation — works today, no external service required.
    Encrypts with Fernet (AES-128-CBC + HMAC) using a master key from the
    SECRET_STORE_MASTER_KEY env var, stores ciphertext in the local_secrets
    table (see database/add_user_credentials.sql) — a table with NO
    row-level security and NO tenant/user columns at all, so it can only
    ever be queried by secret_ref, never listed or browsed.

    VERIFIED: encrypt -> store -> retrieve -> decrypt round-trip tested
    directly in this environment (see conversation) before this was
    handed over.
    """

    def __init__(self, db: Session, master_key: str):
        try:
            self._fernet = Fernet(master_key.encode() if isinstance(master_key, str) else master_key)
        except (ValueError, TypeError) as e:
            raise SecretStoreError(
                "SECRET_STORE_MASTER_KEY is not a valid Fernet key. Generate one with: "
                "python -c \"from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())\""
            ) from e
        self.db = db

    def store(self, ref_prefix: str, plaintext: str) -> str:
        secret_ref = f"local:{ref_prefix}:{uuid.uuid4()}"
        ciphertext = self._fernet.encrypt(plaintext.encode()).decode()
        self.db.execute(
            text("INSERT INTO local_secrets (secret_ref, ciphertext) VALUES (:ref, :ct)"),
            {"ref": secret_ref, "ct": ciphertext},
        )
        self.db.commit()
        return secret_ref

    def retrieve(self, secret_ref: str) -> str:
        row = self.db.execute(
            text("SELECT ciphertext FROM local_secrets WHERE secret_ref = :ref"),
            {"ref": secret_ref},
        ).mappings().first()
        if row is None:
            raise SecretStoreError(f"No secret found for ref (ref itself, not the secret, is safe to log): {secret_ref}")
        try:
            return self._fernet.decrypt(row["ciphertext"].encode()).decode()
        except InvalidToken as e:
            raise SecretStoreError(
                "Stored secret could not be decrypted — SECRET_STORE_MASTER_KEY may have changed "
                "since this secret was stored."
            ) from e

    def delete(self, secret_ref: str) -> None:
        self.db.execute(text("DELETE FROM local_secrets WHERE secret_ref = :ref"), {"ref": secret_ref})
        self.db.commit()


class AzureKeyVaultSecretStore(SecretStore):
    """
    HONESTY NOTE: this defines the correct shape and calls the SDK the way
    Azure's documentation describes, but there is no Azure subscription or
    Key Vault instance available in this environment to actually run it
    against. Treat this exactly like the LLM provider code before it was
    first run against a real account — reasoned through carefully, but
    unverified until someone with real Azure access exercises it once.

    Requires: pip install azure-keyvault-secrets azure-identity
    Requires: AZURE_KEY_VAULT_URL env var (e.g. https://ryze-infinity.vault.azure.net/)
    Auth: DefaultAzureCredential — works with Managed Identity when
    deployed in Azure, or `az login` locally. Deliberately NOT a
    client-secret-in-env-var, since that would just move the
    "how do we protect A secret" problem up one level without
    solving it.
    """

    def __init__(self, vault_url: str):
        try:
            from azure.identity import DefaultAzureCredential
            from azure.keyvault.secrets import SecretClient
        except ImportError as e:
            raise SecretStoreError(
                "AzureKeyVaultSecretStore requires 'azure-keyvault-secrets' and 'azure-identity' "
                "to be installed — pip install azure-keyvault-secrets azure-identity"
            ) from e
        self._client = SecretClient(vault_url=vault_url, credential=DefaultAzureCredential())

    def store(self, ref_prefix: str, plaintext: str) -> str:
        # Key Vault secret names must be alphanumeric + dashes only.
        name = f"ryze-{ref_prefix}-{uuid.uuid4()}"
        try:
            self._client.set_secret(name, plaintext)
        except Exception as e:  # Azure SDK's own exception hierarchy — not narrowed further since unverified
            raise SecretStoreError(f"Failed to store secret in Key Vault (ref: {name})") from e
        return f"azure-kv:{name}"

    def retrieve(self, secret_ref: str) -> str:
        name = secret_ref.removeprefix("azure-kv:")
        try:
            return self._client.get_secret(name).value
        except Exception as e:
            raise SecretStoreError(f"Failed to retrieve secret from Key Vault (ref: {secret_ref})") from e

    def delete(self, secret_ref: str) -> None:
        name = secret_ref.removeprefix("azure-kv:")
        try:
            self._client.begin_delete_secret(name).wait()
        except Exception as e:
            raise SecretStoreError(f"Failed to delete secret from Key Vault (ref: {secret_ref})") from e


def get_secret_store(db: Session) -> SecretStore:
    """
    Single place that decides which SecretStore implementation is active.
    Everything else in the app calls this rather than constructing a
    store directly, so switching backends is a one-function change.
    """
    from app import config

    backend = getattr(config, "SECRET_STORE_BACKEND", "local")
    if backend == "azure_key_vault":
        return AzureKeyVaultSecretStore(config.AZURE_KEY_VAULT_URL)

    if not config.SECRET_STORE_MASTER_KEY:
        raise SecretStoreError(
            "SECRET_STORE_MASTER_KEY is not set. Generate one with: "
            "python -c \"from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())\" "
            "and add it to your .env file."
        )
    return LocalEncryptedSecretStore(db, config.SECRET_STORE_MASTER_KEY)


def mask_secret(plaintext: str, prefix_len: int = 4, suffix_len: int = 4) -> str:
    """
    'dapi1234567890abcdef' -> 'dapi••••••••••••cdef'
    Never called with a value that then gets logged or returned wholesale
    — only ever used to build the exact display string shown to the user.
    Short secrets (shorter than prefix+suffix) are fully masked rather
    than risking showing more than intended.
    """
    if len(plaintext) <= prefix_len + suffix_len:
        return "•" * 8
    return plaintext[:prefix_len] + "•" * 12 + plaintext[-suffix_len:]
