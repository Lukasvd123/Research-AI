from pydantic import BaseModel

class Person(BaseModel):
    """ 
    a person is represented as both a name and an identifier because there can be multiple valid variations of the same name
    """

    author_id: str
    name: str