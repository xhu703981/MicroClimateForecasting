import os
from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

load_dotenv()

DATABASE_URL=os.getenv("DATABASE_URL")
if not DATABASE_URL:
        raise RuntimeError("Database is not set")

engine=create_engine(
DATABASE_URL,
pool_pre_ping=True,
pool_size=5,
max_overflow=10,
)

SessionLocal=sessionmaker(autocommit=False,autoflush=False,bind=engine)

def get_db():
        db=SessionLocal()
        try:
                yield db
        finally:
                db.close()