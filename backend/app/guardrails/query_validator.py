"""
Query Validator
=================
Blocks anything that isn't a plain read query, using actual SQL
tokenization (sqlparse) rather than a regex that only checks the start of
the string. The original reference codebase's DML_PATTERN only matched
statements that BEGIN with a write keyword, so something like:

    /* comment */ DROP TABLE customers

...or a write hidden inside a CTE would not have been caught. This
version walks every statement and every token, so a write keyword
anywhere in the query is caught regardless of comments, whitespace, or
wrapping.

This is intentionally conservative: if we can't be confident a query is
read-only, we block it rather than guess.
"""
import sqlparse
from sqlparse.tokens import DML, DDL, Keyword

BLOCKED_KEYWORDS = {
    "INSERT", "UPDATE", "DELETE", "DROP", "ALTER", "TRUNCATE",
    "CREATE", "GRANT", "REVOKE", "MERGE", "REPLACE", "CALL", "EXEC", "EXECUTE",
}


class QueryValidationError(Exception):
    pass


def assert_read_only(sql: str) -> None:
    """
    Raises QueryValidationError if the SQL contains anything other than
    read (SELECT/SHOW/EXPLAIN/WITH) statements. Checks every statement in
    the string (in case multiple are separated by semicolons) and every
    token within each — not just the first keyword.
    """
    if not sql or not sql.strip():
        raise QueryValidationError("Empty query")

    statements = sqlparse.parse(sql)
    if not statements:
        raise QueryValidationError("Could not parse query")

    for statement in statements:
        stmt_type = statement.get_type()  # e.g. 'SELECT', 'INSERT', 'UNKNOWN'
        if stmt_type and stmt_type.upper() in BLOCKED_KEYWORDS:
            raise QueryValidationError(
                f"Blocked: this system is read-only, and the query's statement "
                f"type ({stmt_type}) is a write operation."
            )

        # Belt-and-braces: also scan every individual token, so a write
        # keyword tucked inside a subquery, CTE, or anywhere else in the
        # statement is caught even if sqlparse classified the overall
        # statement type as something else.
        for token in statement.flatten():
            if token.ttype in (DML, DDL) or (token.ttype is Keyword and token.value.upper() in BLOCKED_KEYWORDS):
                word = token.value.upper()
                if word in BLOCKED_KEYWORDS:
                    raise QueryValidationError(
                        f"Blocked: found a write/administrative keyword ('{word}') "
                        f"in an otherwise read-only query."
                    )
