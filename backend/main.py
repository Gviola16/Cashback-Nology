from fastapi import FastAPI, Request, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, field_validator
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime
from sqlalchemy.orm import declarative_base, sessionmaker
from datetime import datetime
import os
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://cashback_user:cashback_pass@localhost:5432/cashback_db"
)

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class QueryRecord(Base):
    __tablename__ = "queries"

    id = Column(Integer, primary_key=True, index=True)
    ip = Column(String(45), index=True, nullable=False)
    client_type = Column(String(10), nullable=False)
    purchase_value = Column(Float, nullable=False)
    cashback_value = Column(Float, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)


Base.metadata.create_all(bind=engine)

app = FastAPI(title="Cashback API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class CashbackRequest(BaseModel):
    client_type: str
    purchase_value: float
    discount_percent: float = 0.0

    @field_validator("client_type")
    @classmethod
    def validate_client_type(cls, v: str) -> str:
        normalized = v.strip().lower()
        if normalized not in ("regular", "vip"):
            raise ValueError("Tipo de cliente deve ser 'regular' ou 'vip'")
        return normalized

    @field_validator("purchase_value")
    @classmethod
    def validate_purchase_value(cls, v: float) -> float:
        if v <= 0:
            raise ValueError("Valor da compra deve ser positivo")
        return round(v, 2)

    @field_validator("discount_percent")
    @classmethod
    def validate_discount_percent(cls, v: float) -> float:
        if v < 0 or v > 100:
            raise ValueError("Desconto deve estar entre 0 e 100")
        return round(v, 2)


def calculate_cashback(client_type: str, purchase_value: float, discount_percent: float = 0.0) -> dict:
    """
    Regras de negócio:
    1. [Doc 1] Cashback base = 5% do valor da compra
    2. [Doc 2] Se compra > R$ 500 → dobrar o cashback base (vale para todos)
    3. [Doc 1 + Reunião] Se VIP → aplicar 10% de bônus SOBRE o cashback base resultante
    """
    discount_value = round(purchase_value * (discount_percent / 100), 2)
    discounted_purchase_value = round(purchase_value - discount_value, 2)
    base_cashback = round(discounted_purchase_value * 0.05, 2)

    doubled = discounted_purchase_value > 500
    if doubled:
        base_cashback = round(base_cashback * 2, 2)

    vip_bonus = 0.0
    if client_type == "vip":
        vip_bonus = round(base_cashback * 0.10, 2)

    total = round(base_cashback + vip_bonus, 2)

    return {
        "discount_percent": discount_percent,
        "discount_value": discount_value,
        "discounted_purchase_value": discounted_purchase_value,
        "base_cashback": base_cashback,
        "vip_bonus": vip_bonus,
        "total_cashback": total,
        "doubled": doubled,
    }


def get_client_ip(request: Request) -> str:
    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        return forwarded.split(",")[0].strip()
    real_ip = request.headers.get("X-Real-IP")
    if real_ip:
        return real_ip.strip()
    return request.client.host if request.client else "unknown"


@app.post("/api/cashback")
def create_cashback(data: CashbackRequest, request: Request):
    result = calculate_cashback(
        data.client_type,
        data.purchase_value,
        data.discount_percent,
    )
    ip = get_client_ip(request)

    db = SessionLocal()
    try:
        record = QueryRecord(
            ip=ip,
            client_type=data.client_type,
            purchase_value=data.purchase_value,
            cashback_value=result["total_cashback"],
        )
        db.add(record)
        db.commit()
        db.refresh(record)
    finally:
        db.close()

    return {
        "success": True,
        "ip": ip,
        **result,
    }


@app.get("/api/history")
def get_history(request: Request):
    ip = get_client_ip(request)

    db = SessionLocal()
    try:
        records = (
            db.query(QueryRecord)
            .filter(QueryRecord.ip == ip)
            .order_by(QueryRecord.created_at.desc())
            .limit(50)
            .all()
        )
        return {
            "ip": ip,
            "history": [
                {
                    "id": r.id,
                    "client_type": r.client_type,
                    "purchase_value": r.purchase_value,
                    "cashback_value": r.cashback_value,
                    "created_at": r.created_at.isoformat() + "Z",
                }
                for r in records
            ],
        }
    finally:
        db.close()


@app.get("/api/health")
def health():
    return {"status": "ok", "timestamp": datetime.utcnow().isoformat()}
