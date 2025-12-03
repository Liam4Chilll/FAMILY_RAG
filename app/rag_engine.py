"""Moteur RAG avec FAISS et LangChain."""

import os
import time
import base64
import httpx
from pathlib import Path
from typing import Optional, List
from dataclasses import dataclass

from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_community.vectorstores import FAISS
from langchain_ollama import OllamaEmbeddings, ChatOllama
from langchain.schema import Document
from langchain.prompts import ChatPromptTemplate
from langchain.schema.runnable import RunnablePassthrough

from config import get_settings
from document_loader import DocumentLoader


@dataclass
class QueryResult:
    """Résultat d'une requête RAG."""
    answer: str
    sources: List[dict]
    query_time_ms: float
    chunks_found: int
    model_used: str


@dataclass 
class IndexStats:
    """Statistiques de l'index."""
    total_documents: int
    total_chunks: int
    index_exists: bool
    last_updated: Optional[str] = None


class RAGEngine:
    """Moteur RAG principal."""
    
    def __init__(self):
        self.settings = get_settings()
        self.index_path = Path(self.settings.index_dir) / "faiss_index"
        self.vectorstore: Optional[FAISS] = None
        self.doc_loader = DocumentLoader()
        self.llm: Optional[ChatOllama] = None
        
        # Auto-détecter le modèle LLM si non spécifié
        if not self.settings.llm_model:
            self.settings.llm_model = self._detect_llm_model()
        
        # Initialiser les composants Ollama
        self.embeddings = OllamaEmbeddings(
            model=self.settings.embedding_model,
            base_url=self.settings.ollama_base_url
        )
        
        # Initialiser le LLM seulement si un modèle est disponible
        if self.settings.llm_model:
            self.llm = ChatOllama(
                model=self.settings.llm_model,
                base_url=self.settings.ollama_base_url,
                temperature=self.settings.temperature
            )
        
        # Charger l'index existant si disponible
        self._load_index()
    
    def _detect_llm_model(self) -> str:
        """Détecte automatiquement un modèle LLM disponible dans Ollama."""
        try:
            response = httpx.get(
                f"{self.settings.ollama_base_url}/api/tags",
                timeout=5.0
            )
            if response.status_code == 200:
                models = response.json().get("models", [])
                # Exclure les modèles d'embedding connus
                embedding_models = {"nomic-embed-text", "mxbai-embed-large", "all-minilm", "snowflake-arctic-embed"}
                for model in models:
                    name = model.get("name", "")
                    # Vérifier que ce n'est pas un modèle d'embedding
                    base_name = name.split(":")[0]
                    if base_name not in embedding_models:
                        print(f"[Family RAG] Modèle LLM auto-détecté : {name}")
                        return name
        except Exception as e:
            print(f"[Family RAG] Impossible de détecter les modèles Ollama : {e}")
        
        print("[Family RAG] Aucun modèle LLM trouvé. Installez un modèle avec 'ollama pull <modele>'")
        return ""
    
    def _load_index(self) -> bool:
        """Charge l'index FAISS depuis le disque."""
        if self.index_path.exists():
            try:
                self.vectorstore = FAISS.load_local(
                    str(self.index_path),
                    self.embeddings,
                    allow_dangerous_deserialization=True
                )
                return True
            except Exception as e:
                print(f"Erreur chargement index: {e}")
        return False
    
    def _save_index(self):
        """Sauvegarde l'index FAISS sur le disque."""
        if self.vectorstore:
            self.index_path.parent.mkdir(parents=True, exist_ok=True)
            self.vectorstore.save_local(str(self.index_path))
    
    def index_documents(self) -> dict:
        """Indexe tous les documents du dossier data."""
        start_time = time.time()
        
        # Charger les documents
        documents = self.doc_loader.load_all()
        if not documents:
            return {
                'success': False,
                'error': 'Aucun document trouvé dans /data',
                'documents': 0,
                'chunks': 0
            }
        
        # Découper en chunks
        splitter = RecursiveCharacterTextSplitter(
            chunk_size=self.settings.chunk_size,
            chunk_overlap=self.settings.chunk_overlap,
            separators=["\n\n", "\n", ". ", " ", ""]
        )
        chunks = splitter.split_documents(documents)
        
        if not chunks:
            return {
                'success': False,
                'error': 'Aucun contenu extractible des documents',
                'documents': len(documents),
                'chunks': 0
            }
        
        # Créer l'index vectoriel
        self.vectorstore = FAISS.from_documents(chunks, self.embeddings)
        self._save_index()
        
        elapsed = time.time() - start_time
        
        return {
            'success': True,
            'documents': len(documents),
            'chunks': len(chunks),
            'time_seconds': round(elapsed, 2)
        }
    
    def query(self, question: str, top_k: Optional[int] = None) -> QueryResult:
        """Exécute une requête RAG."""
        if not self.llm or not self.settings.llm_model:
            return QueryResult(
                answer="Aucun modèle LLM disponible. Installez un modèle avec 'ollama pull <modele>' puis sélectionnez-le dans les paramètres.",
                sources=[],
                query_time_ms=0,
                chunks_found=0,
                model_used="Aucun"
            )
        
        if not self.vectorstore:
            return QueryResult(
                answer="Aucun document n'a été indexé. Veuillez d'abord indexer vos documents.",
                sources=[],
                query_time_ms=0,
                chunks_found=0,
                model_used=self.settings.llm_model
            )
        
        start_time = time.time()
        k = top_k or self.settings.top_k
        
        # Recherche des chunks pertinents
        docs_with_scores = self.vectorstore.similarity_search_with_score(question, k=k)
        
        if not docs_with_scores:
            return QueryResult(
                answer="Aucun document pertinent trouvé pour cette question.",
                sources=[],
                query_time_ms=0,
                chunks_found=0,
                model_used=self.settings.llm_model
            )
        
        # Préparer le contexte
        context_parts = []
        sources = []
        
        for doc, score in docs_with_scores:
            context_parts.append(doc.page_content)
            sources.append({
                'source': doc.metadata.get('source', 'Unknown'),
                'score': round(float(score), 4),
                'preview': doc.page_content[:200] + '...' if len(doc.page_content) > 200 else doc.page_content
            })
        
        context = "\n\n---\n\n".join(context_parts)
        
        # Prompt RAG
        prompt = ChatPromptTemplate.from_template("""Tu es un assistant qui répond aux questions en te basant uniquement sur le contexte fourni.
Si le contexte ne contient pas l'information nécessaire, dis-le clairement.
Réponds en français de manière concise et précise.

Contexte:
{context}

Question: {question}

Réponse:""")
        
        # Générer la réponse
        chain = prompt | self.llm
        response = chain.invoke({"context": context, "question": question})
        
        elapsed_ms = (time.time() - start_time) * 1000
        
        return QueryResult(
            answer=response.content,
            sources=sources,
            query_time_ms=round(elapsed_ms, 2),
            chunks_found=len(docs_with_scores),
            model_used=self.settings.llm_model
        )
    
    def get_stats(self) -> IndexStats:
        """Retourne les statistiques de l'index."""
        if not self.vectorstore:
            return IndexStats(
                total_documents=0,
                total_chunks=0,
                index_exists=False
            )
        
        # FAISS ne stocke pas directement le nombre de documents originaux
        # On compte les chunks dans l'index
        try:
            total_chunks = self.vectorstore.index.ntotal
        except:
            total_chunks = 0
        
        return IndexStats(
            total_documents=len(self.doc_loader.list_files()),
            total_chunks=total_chunks,
            index_exists=self.index_path.exists()
        )
    
    def update_settings(
        self, 
        temperature: Optional[float] = None, 
        top_k: Optional[int] = None,
        llm_model: Optional[str] = None
    ):
        """Met à jour les paramètres du moteur."""
        rebuild_llm = False
        
        if temperature is not None:
            self.settings.temperature = temperature
            rebuild_llm = True
        
        if llm_model is not None:
            self.settings.llm_model = llm_model
            rebuild_llm = True
        
        if rebuild_llm and self.settings.llm_model:
            self.llm = ChatOllama(
                model=self.settings.llm_model,
                base_url=self.settings.ollama_base_url,
                temperature=self.settings.temperature
            )
        
        if top_k is not None:
            self.settings.top_k = top_k
    
    async def analyze_image_with_vision(self, image_path: str, question: str) -> dict:
        """Analyse une image avec un modèle vision (Ministral 3)."""
        start_time = time.time()
        
        # Construire le chemin complet
        full_path = Path(self.settings.data_dir) / image_path
        
        if not full_path.exists():
            return {
                "success": False,
                "error": f"Image non trouvée: {image_path}",
                "analysis": None,
                "time_ms": 0
            }
        
        # Lire et encoder l'image en base64
        with open(full_path, "rb") as f:
            image_data = base64.b64encode(f.read()).decode("utf-8")
        
        # Détecter le modèle vision disponible
        vision_model = self._detect_vision_model()
        if not vision_model:
            return {
                "success": False,
                "error": "Aucun modèle vision disponible. Installez ministral-3 avec 'ollama pull ministral-3:latest'",
                "analysis": None,
                "time_ms": 0
            }
        
        # Appel API Ollama avec image
        try:
            async with httpx.AsyncClient(timeout=120.0) as client:
                response = await client.post(
                    f"{self.settings.ollama_base_url}/api/chat",
                    json={
                        "model": vision_model,
                        "messages": [
                            {
                                "role": "user",
                                "content": question,
                                "images": [image_data]
                            }
                        ],
                        "stream": False
                    }
                )
                response.raise_for_status()
                data = response.json()
                
                elapsed_ms = (time.time() - start_time) * 1000
                
                return {
                    "success": True,
                    "analysis": data.get("message", {}).get("content", ""),
                    "model": vision_model,
                    "time_ms": round(elapsed_ms, 2)
                }
                
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "analysis": None,
                "time_ms": 0
            }
    
    def _detect_vision_model(self) -> Optional[str]:
        """Détecte un modèle vision disponible dans Ollama."""
        vision_models = ["ministral-3:latest", "ministral-3:8b", "ministral-3:14b", "ministral-3:3b", "llava:latest", "moondream:latest"]
        
        try:
            response = httpx.get(
                f"{self.settings.ollama_base_url}/api/tags",
                timeout=5.0
            )
            if response.status_code == 200:
                models = response.json().get("models", [])
                available = [m.get("name", "") for m in models]
                
                for vm in vision_models:
                    if vm in available:
                        return vm
                    # Check without tag
                    base = vm.split(":")[0]
                    for a in available:
                        if a.startswith(base):
                            return a
        except:
            pass
        
        return None
    
    async def analyze_image_base64(self, image_data: str, question: str) -> dict:
        """Analyse une image encodée en base64 avec un modèle vision."""
        start_time = time.time()
        
        # Nettoyer le base64 si nécessaire (retirer le préfixe data:image/...)
        if ',' in image_data:
            image_data = image_data.split(',')[1]
        
        # Détecter le modèle vision disponible
        vision_model = self._detect_vision_model()
        if not vision_model:
            return {
                "success": False,
                "error": "Aucun modèle vision disponible. Installez ministral-3 avec 'ollama pull ministral-3:latest'",
                "analysis": None,
                "time_ms": 0
            }
        
        # Appel API Ollama avec image base64
        try:
            async with httpx.AsyncClient(timeout=120.0) as client:
                response = await client.post(
                    f"{self.settings.ollama_base_url}/api/chat",
                    json={
                        "model": vision_model,
                        "messages": [
                            {
                                "role": "user",
                                "content": question,
                                "images": [image_data]
                            }
                        ],
                        "stream": False
                    }
                )
                response.raise_for_status()
                data = response.json()
                
                elapsed_ms = (time.time() - start_time) * 1000
                
                return {
                    "success": True,
                    "analysis": data.get("message", {}).get("content", ""),
                    "model": vision_model,
                    "time_ms": round(elapsed_ms, 2)
                }
                
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "analysis": None,
                "time_ms": 0
            }
