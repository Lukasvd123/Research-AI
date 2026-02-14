from pydantic import BaseModel

class Publication(BaseModel):
    """
    a publication can be many things (e.g. journal article, report, review, etc.), but it always has a unique DOI
    """
    doi: str
    title: str
    publication_rootid: str
    year: int
    category: str
    name: str