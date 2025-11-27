"""Configuration centralisée de l'application."""

from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    """Paramètres de l'application, chargés depuis les variables d'environnement."""
    
    # Ollama
    ollama_host: str = "host.docker.internal:11434"
    embedding_model: str = "nomic-embed-text"
    llm_model: str = ""  # Auto-détecté au démarrage si vide
    
    # RAG
    chunk_size: int = 1000
    chunk_overlap: int = 200
    top_k: int = 4
    
    # LLM
    temperature: float = 0.7
    
    # Chemins
    data_dir: str = "/data"
    index_dir: str = "/app/index"
    
    @property
    def ollama_base_url(self) -> str:
        return f"http://{self.ollama_host}"
    
    class Config:
        env_file = ".env"


@lru_cache
def get_settings() -> Settings:
    return Settings()
