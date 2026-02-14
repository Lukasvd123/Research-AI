# this file deals with API endpoints whose responses need Ricgraph
# (e.g. to return all connections between a person and their publications)

from fastapi import APIRouter
from pydantic import BaseModel
from typing import List
from backend.utils.ricgraph.connections import fetch_collaborators
from backend.schemas import Person, Publication, Organization, Connections


# these endpoints can be reached using the /connections URL prefix
router = APIRouter(prefix = "/connections")

@router.get("/person/{author_id}", response_model=Connections)
def get_person_connections(author_id: str):
    return Connections(
        persons=[],
        publications=[],
        organizations=[]
    )

@router.get("/organization/{organization_id}", response_model=Connections)
def get_person_publication_connections(organization_id: str):
    return fetch_collaborators(organization_id)