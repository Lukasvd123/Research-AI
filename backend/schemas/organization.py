from pydantic import BaseModel

class Organization(BaseModel):
    organization_id: str
    name: str