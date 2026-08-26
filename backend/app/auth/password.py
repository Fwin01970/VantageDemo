from passlib.context import CryptContext

_pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(plain: str) -> str:
    return _pwd_context.hash(plain)


def verify_password(plain: str, hashed: str | None) -> bool:
    # A None hash means this account has no password at all (an
    # OAuth-only account) — never let that compare as a "match" against
    # anything, including an empty string.
    if not hashed:
        return False
    return _pwd_context.verify(plain, hashed)
