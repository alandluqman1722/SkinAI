
import os
from contextlib import asynccontextmanager

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from backend.ai_service import router as analyze_router
from backend.admin_api import router as admin_router
from backend.admin_appointments import router as admin_appointments_router
from backend.admin_users import router as admin_users_router
from backend.doctor_directory import router as doctor_directory_router
from backend.firebase_app import PROJECT_ROOT, initialize_firebase_app
from backend.medical_records import router as medical_router
from backend.patient_assessments import router as patient_assessments_router
from backend.skinchat_service import router as skinchat_router


# Load backend environment variables.
load_dotenv(PROJECT_ROOT / ".env", override=False)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Initialize Firebase Admin before serving requests.
    initialize_firebase_app()
    yield


app = FastAPI(
    title="SkinAI Scan API",
    description=(
        "Authenticated image screening, "
        "medical records, and SkinChat AI APIs."
    ),
    version="1.0.0",
    lifespan=lifespan,
)

# Register API routers.
app.include_router(analyze_router)
app.include_router(medical_router)
app.include_router(patient_assessments_router)
app.include_router(skinchat_router)
app.include_router(doctor_directory_router)
app.include_router(admin_router)
app.include_router(admin_appointments_router)
app.include_router(admin_users_router)

# CORS configuration.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict:
    return {
        "status": "ok",
        "provider": "Ivy AI",
        "mock_mode": os.getenv("MOCK_API", "").strip() == "1",
        "skinchat_enabled": False,
        "skinchat_history_enabled": True,
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app:app",
        host="0.0.0.0",
        port=8000,
        reload=False,
    )
