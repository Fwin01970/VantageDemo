"""
RBAC (Role-Based Access Control) check.

Usage in an endpoint:

    @router.get("/admin/tenants")
    def list_tenants(ctx: TenantContext = Depends(require_permission("tenant:manage"))):
        ...

If the logged-in user's roles don't grant that permission, the request is
rejected with 403 Forbidden before the endpoint's own code ever runs.
"""
from fastapi import Depends, HTTPException, status

from app.auth.dependencies import get_current_user
from app.services.tenant_resolver import TenantContext


def require_permission(permission_code: str):
    def checker(ctx: TenantContext = Depends(get_current_user)) -> TenantContext:
        if not ctx.has_permission(permission_code):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Missing required permission: {permission_code}",
            )
        return ctx
    return checker
