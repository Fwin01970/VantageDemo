"""
Tenant Resolver
================
Given "this is user X, logged in for tenant Y," this module looks up
everything the rest of the app needs to know: which company they belong
to, what industry that company is in, what roles the user has, and what
permissions those roles grant.

Nothing about a specific company or role is hardcoded here — it's all
read from the database.
"""
from dataclasses import dataclass
from typing import List, Optional
from sqlalchemy.orm import Session
from sqlalchemy import select

from app.models import User, Tenant, Role, Permission


@dataclass
class TenantContext:
    """Everything the rest of the app needs to know about 'who is asking.'"""
    user_id: str
    display_name: str
    email: str
    tenant_id: str
    tenant_name: str
    industry: str
    roles: List[str]
    permissions: List[str]

    def has_permission(self, code: str) -> bool:
        return code in self.permissions


def resolve_tenant_context(db: Session, user_id: str, tenant_id: str) -> Optional[TenantContext]:
    user = db.get(User, user_id)
    if user is None or str(user.tenant_id) != str(tenant_id):
        # Either the user doesn't exist, or the token's tenant claim
        # doesn't match the user's actual tenant — refuse either way.
        return None

    tenant = db.get(Tenant, tenant_id)
    if tenant is None or not tenant.is_active:
        return None

    roles: List[Role] = user.roles
    role_names = [r.name for r in roles]

    permission_codes = set()
    for role in roles:
        for perm in role.permissions:
            permission_codes.add(perm.code)

    return TenantContext(
        user_id=str(user.id),
        display_name=user.display_name,
        email=user.email,
        tenant_id=str(tenant.id),
        tenant_name=tenant.name,
        industry=tenant.industry,
        roles=role_names,
        permissions=sorted(permission_codes),
    )
