from pydantic import BaseModel
from typing import List
from backend.schemas import Person, Publication, Organization

class Connections(BaseModel):
    persons: List[Person]
    publications: List[Publication]
    organizations: List[Organization]