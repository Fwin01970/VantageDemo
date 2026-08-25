"""
Defines the shape of data the API sends back as JSON.
"""
from pydantic import BaseModel
from typing import List


class DemoUserOut(BaseModel):
    id: str
    display_name: str
    email: str
    tenant_name: str


class LoginRequest(BaseModel):
    user_id: str


class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class MeResponse(BaseModel):
    user_id: str
    display_name: str
    email: str
    tenant_id: str
    tenant_name: str
    industry: str
    roles: List[str]
    permissions: List[str]
