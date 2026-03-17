from uuid import UUID
from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional, List
class ExperimentSessionCreate(BaseModel):
        subject_id:Optional[str]=Field(default=None,description='Subject Identifier')
        body_site:Optional[str]=Field(default=None,description='where on a body')
        condition_label:Optional[str]=Field(default=None,description='under what condition is the experiment done')
        note:Optional[str]=Field(default=None,description='any additional information to note')
        start_time:Optional[datetime]=Field(default=None, description='the starting time of the experiment')

class ExperimentSessionOut(BaseModel):
        session_id:UUID
        subject_id:Optional[str]=Field(default=None,description='Subject Identifier')
        body_site:Optional[str]=Field(default=None,description='where on a body')
        condition_label:Optional[str]=Field(default=None,description='under what condition is the experiment done')
        note:Optional[str]=Field(default=None,description='any additional information to note')
        start_time:Optional[datetime]=Field(default=None, description='the starting time of the experiment')
        end_time:Optional[datetime]=Field(default=None, description='the ending time of the experiment')

class SensorReadingCreate(BaseModel):
        session_id:UUID
        time:datetime
        humidity:float
        temperature:float
        pressure:float

class SensorReadingOut(BaseModel):
        session_id:UUID
        time:datetime
        humidity:float
        temperature:float
        pressure:float

class SensorReadingBatchCreate(BaseModel):
        readings:List[SensorReadingCreate]