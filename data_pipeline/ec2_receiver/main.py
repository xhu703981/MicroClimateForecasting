
from datetime import datetime
from typing import Optional, List

from fastapi import FastAPI, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import text

from .db import get_db
from .schemas import (
    ExperimentSessionCreate,
    ExperimentSessionOut,
    SensorReadingCreate,
    SensorReadingOut,
    SensorReadingBatchCreate,
)

app = FastAPI(title="TEWL / Sensor API", version="0.1.0")


@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/experiment-sessions", response_model=ExperimentSessionOut)
def create_experiment_session(payload: ExperimentSessionCreate, db: Session = Depends(get_db)):
    q = text("""
        INSERT INTO experiment_session (subject_id, body_site, condition_label, note, start_time)
        VALUES (:subject_id, :body_site, :condition_label, :note, :start_time)
        RETURNING session_id, subject_id, body_site, condition_label, note, start_time, end_time
    """)
    try:
        row = db.execute(q, payload.model_dump()).mappings().one()
        db.commit()
        return dict(row)
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to create session: {e}")

@app.get("/experiment-sessions/{session_id}", response_model=ExperimentSessionOut)
def get_experiment_session(session_id: str, db: Session = Depends(get_db)):
    q = text("""
        SELECT session_id, subject_id, body_site, condition_label, note, start_time, end_time
        FROM experiment_session
        WHERE session_id = :session_id
    """)
    row = db.execute(q, {"session_id": session_id}).mappings().first()
    if not row:
        raise HTTPException(status_code=404, detail="Session not found")
    return dict(row)

@app.get("/experiment-sessions", response_model=List[ExperimentSessionOut])
def list_experiment_sessions(
    limit: int = Query(50, ge=1, le=500),
    db: Session = Depends(get_db),
):
    q = text("""
        SELECT session_id, subject_id, body_site, condition_label, note, start_time, end_time
        FROM experiment_session
        ORDER BY start_time DESC
        LIMIT :limit
    """)
    rows = db.execute(q, {"limit": limit}).mappings().all()
    return [dict(r) for r in rows]

@app.post("/sensor-readings", response_model=SensorReadingOut)
def ingest_sensor_reading(payload: SensorReadingCreate, db: Session = Depends(get_db)):
    q = text("""
        INSERT INTO sensor_reading (session_id, time, humidity, temperature, pressure)
        VALUES (:session_id, :time, :humidity, :temperature, :pressure)
        RETURNING session_id, time, humidity, temperature, pressure
    """)

    # Optional: enforce that session exists
    exists_q = text("SELECT 1 FROM experiment_session WHERE session_id = :session_id")
    if not db.execute(exists_q, {"session_id": payload.session_id}).first():
        raise HTTPException(status_code=400, detail="session_id does not exist")

    try:
        row = db.execute(q, payload.model_dump()).mappings().one()
        db.commit()
        return dict(row)
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to ingest reading: {e}")

@app.post("/sensor-readings/batch")
def ingest_sensor_readings_batch(payload: SensorReadingBatchCreate, db: Session = Depends(get_db)):
    if not payload.readings:
        return {"inserted": 0}

    # Validate all sessions exist (simple version: check unique ids)
    session_ids = sorted({r.session_id for r in payload.readings})
    exists_q = text("SELECT session_id FROM experiment_session WHERE session_id = ANY(:ids)")
    existing = db.execute(exists_q, {"ids": session_ids}).scalars().all()
    missing = sorted(set(session_ids) - set(existing))
    if missing:
        raise HTTPException(status_code=400, detail=f"Missing session_id(s): {missing}")

    insert_q = text("""
        INSERT INTO sensor_reading (session_id, time, humidity, temperature, pressure)
        VALUES (:session_id, :time, :humidity, :temperature, :pressure)
    """)

    try:
        db.execute(insert_q, [r.model_dump() for r in payload.readings])
        db.commit()
        return {"inserted": len(payload.readings)}
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed batch insert: {e}")

@app.get("/sensor-readings", response_model=List[SensorReadingOut])
def query_sensor_readings(
    session_id: str = Query(..., description="session_id for the experiment"),
    start: Optional[datetime] = Query(None),
    end: Optional[datetime] = Query(None),
    limit: int = Query(5000, ge=1, le=200000),
    db: Session = Depends(get_db),
):
    # Build WHERE dynamically but safely
    where = ["session_id = :session_id"]
    params = {"session_id": session_id, "limit": limit}

    if start is not None:
        where.append("time >= :start")
        params["start"] = start
    if end is not None:
        where.append("time <= :end")
        params["end"] = end
      
     q = text(f"""
        SELECT session_id, time, humidity, temperature, pressure
        FROM sensor_reading
        WHERE {" AND ".join(where)}
        ORDER BY time ASC
        LIMIT :limit
    """)

    rows = db.execute(q, params).mappings().all()
    return [dict(r) for r in rows]