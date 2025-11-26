"""Moteur RAG avec FAISS et LangChain."""

import os
import time
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
        
        # Initialiser les composants Ollama
        self.embeddings = OllamaEmbeddings(
            model=self.settings.embedding_model,
            base_url=self.settings.ollama_base_url
        )
        
        self.llm = ChatOllama(
            model=self.settings.llm_model,
            base_url=self.settings.ollama_base_url,
            temperature=self.settings.temperature
        )
        
        # Charger l'index existant si disponible
        self._load_index()
    
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
    
    def update_settings(self, temperature: Optional[float] = None, top_k: Optional[int] = None):
        """Met à jour les paramètres du moteur."""
        if temperature is not None:
            self.settings.temperature = temperature
            self.llm = ChatOllama(
                model=self.settings.llm_model,
                base_url=self.settings.ollama_base_url,
                temperature=temperature
            )
        
        if top_k is not None:
            self.settings.top_k = top_k
