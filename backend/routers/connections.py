# this file deals with API endpoints whose responses need Ricgraph
# (e.g. to return all connections between a person and their publications)

from fastapi import APIRouter
from pydantic import BaseModel
from typing import List
from backend.utils.ricgraph.connections import fetch_collaborators

# these endpoints can be reached using the /connections URL prefix
router = APIRouter(prefix = "/connections")

# a person is represented as both a name and an identifier because there can be multiple valid variations of the same name
class Person(BaseModel):
    author_id: str
    name: str

class Publication(BaseModel):
    doi: str
    title: str
    publication_rootid: str
    year: int
    category: str
    name: str

class Organization(BaseModel):
    organization_id: str

class Connections(BaseModel):
    persons: List[Person]
    publications: List[Publication]
    organizations: List[Organization]


@router.get("/person/{author_id}", response_model=Connections)
def get_person_connections(author_id: str):
    return fetch_collaborators(author_id)

@router.get("/organization/{organization_id}", response_model=Connections)
def get_person_publication_connections(organization_id: str):
    return fetch_collaborators(organization_id)