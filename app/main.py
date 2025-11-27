"""API FastAPI pour le système RAG."""

import httpx
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel
from typing import Optional

from config import get_settings
from rag_engine import RAGEngine


# Instance globale du moteur RAG
rag_engine: Optional[RAGEngine] = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialisation et nettoyage de l'application."""
    global rag_engine
    rag_engine = RAGEngine()
    yield


app = FastAPI(
    title="Family RAG",
    description="Système RAG local pour la famille",
    version="2.0.0",
    lifespan=lifespan
)

# Templates et fichiers statiques
templates = Jinja2Templates(directory="templates")
app.mount("/static", StaticFiles(directory="static"), name="static")


# --- Modèles Pydantic ---

class QueryRequest(BaseModel):
    question: str
    top_k: Optional[int] = None


class SettingsUpdate(BaseModel):
    temperature: Optional[float] = None
    top_k: Optional[int] = None
    llm_model: Optional[str] = None


# --- Routes API ---

@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    """Page d'accueil avec l'interface web."""
    return templates.TemplateResponse("index.html", {"request": request})


@app.get("/health")
async def health():
    """Endpoint de health check."""
    settings = get_settings()
    
    # Vérifier la connexion Ollama
    ollama_ok = False
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{settings.ollama_base_url}/api/tags",
                timeout=5.0
            )
            ollama_ok = response.status_code == 200
    except:
        pass
    
    return {
        "status": "healthy" if ollama_ok else "degraded",
        "ollama_connected": ollama_ok,
        "ollama_host": settings.ollama_host
    }


@app.get("/api/files")
async def list_files():
    """Liste les fichiers disponibles dans le dossier data."""
    return {"files": rag_engine.doc_loader.list_files()}


@app.post("/api/index")
async def index_documents():
    """Indexe tous les documents."""
    result = rag_engine.index_documents()
    if not result['success']:
        raise HTTPException(status_code=400, detail=result.get('error', 'Indexation échouée'))
    return result


@app.post("/api/query")
async def query(request: QueryRequest):
    """Exécute une requête RAG."""
    if not request.question.strip():
        raise HTTPException(status_code=400, detail="La question ne peut pas être vide")
    
    result = rag_engine.query(request.question, request.top_k)
    
    return {
        "answer": result.answer,
        "sources": result.sources,
        "metrics": {
            "query_time_ms": result.query_time_ms,
            "chunks_found": result.chunks_found,
            "model": result.model_used
        }
    }


@app.get("/api/stats")
async def get_stats():
    """Retourne les statistiques de l'index."""
    stats = rag_engine.get_stats()
    settings = get_settings()
    
    return {
        "index": {
            "exists": stats.index_exists,
            "total_documents": stats.total_documents,
            "total_chunks": stats.total_chunks
        },
        "settings": {
            "embedding_model": settings.embedding_model,
            "llm_model": rag_engine.settings.llm_model,
            "chunk_size": settings.chunk_size,
            "chunk_overlap": settings.chunk_overlap,
            "temperature": rag_engine.settings.temperature,
            "top_k": rag_engine.settings.top_k
        }
    }


@app.put("/api/settings")
async def update_settings(settings: SettingsUpdate):
    """Met à jour les paramètres du moteur RAG."""
    rag_engine.update_settings(
        temperature=settings.temperature,
        top_k=settings.top_k,
        llm_model=settings.llm_model
    )
    return {
        "status": "ok",
        "llm_model": rag_engine.settings.llm_model,
        "temperature": rag_engine.settings.temperature,
        "top_k": rag_engine.settings.top_k
    }


@app.get("/api/ollama/models")
async def get_ollama_models():
    """Liste les modèles disponibles sur Ollama."""
    settings = get_settings()
    
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{settings.ollama_base_url}/api/tags",
                timeout=10.0
            )
            response.raise_for_status()
            data = response.json()
            
            return {
                "models": [
                    {
                        "name": m["name"],
                        "size": m.get("size", 0),
                        "modified": m.get("modified_at", "")
                    }
                    for m in data.get("models", [])
                ]
            }
    except httpx.RequestError as e:
        raise HTTPException(
            status_code=503,
            detail=f"Impossible de contacter Ollama: {str(e)}"
        )
