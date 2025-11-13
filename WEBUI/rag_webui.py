#!/usr/bin/env python3
"""
RAG Familial - Interface Web Flask
Interface moderne et complète pour interagir avec le système RAG
"""

import os
import sys
import json
import time
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Optional
import threading
import subprocess

from flask import Flask, render_template, request, jsonify, session, send_file
from flask_socketio import SocketIO, emit
from werkzeug.utils import secure_filename

# Langchain
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_community.vectorstores import FAISS
from langchain_ollama import OllamaEmbeddings, OllamaLLM

# Parsers
import pypdf
from docx import Document as DocxDocument
from odf import text as odf_text, teletype
from odf.opendocument import load as odf_load
from bs4 import BeautifulSoup
import ebooklib
from ebooklib import epub
import email
from email import policy

# Configuration
CONFIG_FILE = Path.home() / ".rag_config"
HISTORY_FILE = Path.home() / ".rag_history.json"
SETTINGS_FILE = Path.home() / ".rag_settings.json"

# Valeurs par défaut
DEFAULT_SETTINGS = {
    "ollama_host": "http://localhost:11434",
    "embed_model": "nomic-embed-text:latest",
    "llm_model": "mistral:latest",
    "chunk_size": 1000,
    "chunk_overlap": 200,
    "retrieval_k": 5,
    "temperature": 0.7,
    "max_history": 100,
    "theme": "dark"
}

# Charger configuration
def load_config():
    settings = DEFAULT_SETTINGS.copy()
    
    # Charger depuis .rag_config
    if CONFIG_FILE.exists():
        with open(CONFIG_FILE) as f:
            for line in f:
                if "=" in line and not line.startswith("#"):
                    key, value = line.strip().split("=", 1)
                    if key == "OLLAMA_URL":
                        settings["ollama_host"] = value
                    elif key == "EMBED_MODEL":
                        settings["embed_model"] = value
                    elif key == "LLM_MODEL":
                        settings["llm_model"] = value
    
    # Charger settings personnalisés
    if SETTINGS_FILE.exists():
        with open(SETTINGS_FILE) as f:
            custom_settings = json.load(f)
            settings.update(custom_settings)
    
    return settings

# Sauvegarder settings
def save_settings(settings):
    with open(SETTINGS_FILE, 'w') as f:
        json.dump(settings, f, indent=2)

# Configuration initiale
SETTINGS = load_config()

OLLAMA_HOST = SETTINGS["ollama_host"]
EMBED_MODEL = SETTINGS["embed_model"]
LLM_MODEL = SETTINGS["llm_model"]
RAG_DIR = Path.home() / "RAG"
FAISS_DB = Path.home() / "rag_system" / "faiss_db"

# Flask app
app = Flask(__name__)
app.config['SECRET_KEY'] = 'rag_familial_secret_2024'
app.config['MAX_CONTENT_LENGTH'] = 100 * 1024 * 1024  # 100MB max
socketio = SocketIO(app, cors_allowed_origins="*")

# État global
indexing_in_progress = False
indexing_stats = {}

# ============================================
# DOCUMENT LOADERS
# ============================================

class DocumentLoader:
    @staticmethod
    def load_txt(file_path: Path) -> str:
        return file_path.read_text(encoding='utf-8', errors='ignore')
    
    @staticmethod
    def load_pdf(file_path: Path) -> str:
        text = []
        with open(file_path, 'rb') as f:
            pdf_reader = pypdf.PdfReader(f)
            for page in pdf_reader.pages:
                text.append(page.extract_text())
        return "\n".join(text)
    
    @staticmethod
    def load_docx(file_path: Path) -> str:
        doc = DocxDocument(file_path)
        return "\n".join([para.text for para in doc.paragraphs])
    
    @staticmethod
    def load_odt(file_path: Path) -> str:
        doc = odf_load(file_path)
        paragraphs = doc.getElementsByType(odf_text.P)
        return "\n".join([teletype.extractText(p) for p in paragraphs])
    
    @staticmethod
    def load_html(file_path: Path) -> str:
        html = file_path.read_text(encoding='utf-8', errors='ignore')
        soup = BeautifulSoup(html, 'lxml')
        for script in soup(["script", "style"]):
            script.decompose()
        return soup.get_text(separator='\n', strip=True)
    
    @staticmethod
    def load_epub(file_path: Path) -> str:
        book = epub.read_epub(str(file_path))
        text = []
        for item in book.get_items():
            if item.get_type() == ebooklib.ITEM_DOCUMENT:
                soup = BeautifulSoup(item.get_content(), 'html.parser')
                text.append(soup.get_text())
        return "\n".join(text)
    
    @staticmethod
    def load_eml(file_path: Path) -> str:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            msg = email.message_from_file(f, policy=policy.default)
        
        subject = msg['subject'] or ''
        body_parts = []
        
        if msg.is_multipart():
            for part in msg.walk():
                if part.get_content_type() == "text/plain":
                    body_parts.append(part.get_payload(decode=True).decode('utf-8', errors='ignore'))
        else:
            body_parts.append(msg.get_payload(decode=True).decode('utf-8', errors='ignore'))
        
        return f"Sujet: {subject}\n\n" + "\n".join(body_parts)

# ============================================
# GESTION HISTORIQUE
# ============================================

def load_history() -> List[Dict]:
    if HISTORY_FILE.exists():
        with open(HISTORY_FILE) as f:
            return json.load(f)
    return []

def save_history(history: List[Dict]):
    # Limiter l'historique
    max_history = SETTINGS.get("max_history", 100)
    if len(history) > max_history:
        history = history[-max_history:]
    
    with open(HISTORY_FILE, 'w') as f:
        json.dump(history, f, indent=2, ensure_ascii=False)

def add_to_history(query: str, response: str, sources: List[str], duration: float):
    history = load_history()
    history.append({
        "timestamp": datetime.now().isoformat(),
        "query": query,
        "response": response,
        "sources": sources,
        "duration": duration,
        "model": LLM_MODEL,
        "k": SETTINGS.get("retrieval_k", 5)
    })
    save_history(history)

# ============================================
# FONCTIONS RAG
# ============================================

def scan_documents(directory: Path) -> List[dict]:
    supported_extensions = {
        '.txt': DocumentLoader.load_txt,
        '.md': DocumentLoader.load_txt,
        '.pdf': DocumentLoader.load_pdf,
        '.docx': DocumentLoader.load_docx,
        '.odt': DocumentLoader.load_odt,
        '.html': DocumentLoader.load_html,
        '.htm': DocumentLoader.load_html,
        '.epub': DocumentLoader.load_epub,
        '.eml': DocumentLoader.load_eml,
    }
    
    documents = []
    for ext, loader_func in supported_extensions.items():
        for file_path in directory.rglob(f"*{ext}"):
            documents.append({
                'path': file_path,
                'loader': loader_func,
                'extension': ext
            })
    
    return documents

def index_documents_background():
    global indexing_in_progress, indexing_stats
    
    indexing_in_progress = True
    indexing_stats = {
        "status": "running",
        "progress": 0,
        "total_docs": 0,
        "processed_docs": 0,
        "total_chunks": 0,
        "current_file": "",
        "errors": []
    }
    
    try:
        # Scan documents
        socketio.emit('indexing_update', {"message": "Scan des documents...", "progress": 5})
        documents = scan_documents(RAG_DIR)
        indexing_stats["total_docs"] = len(documents)
        
        if not documents:
            indexing_stats["status"] = "error"
            indexing_stats["errors"].append("Aucun document trouvé")
            socketio.emit('indexing_complete', indexing_stats)
            return
        
        socketio.emit('indexing_update', {
            "message": f"{len(documents)} documents trouvés",
            "progress": 10
        })
        
        # Traiter documents
        all_texts = []
        all_metadatas = []
        
        chunk_size = SETTINGS.get("chunk_size", 1000)
        chunk_overlap = SETTINGS.get("chunk_overlap", 200)
        
        text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=chunk_size,
            chunk_overlap=chunk_overlap,
            length_function=len,
        )
        
        for i, doc in enumerate(documents):
            try:
                indexing_stats["current_file"] = doc['path'].name
                indexing_stats["processed_docs"] = i + 1
                progress = 10 + int((i / len(documents)) * 70)
                indexing_stats["progress"] = progress
                
                socketio.emit('indexing_update', {
                    "message": f"Traitement: {doc['path'].name}",
                    "progress": progress,
                    "stats": indexing_stats
                })
                
                text = doc['loader'](doc['path'])
                chunks = text_splitter.split_text(text)
                
                for chunk in chunks:
                    all_texts.append(chunk)
                    all_metadatas.append({
                        'source': str(doc['path']),
                        'filename': doc['path'].name,
                        'extension': doc['extension']
                    })
                
                indexing_stats["total_chunks"] = len(all_texts)
                
            except Exception as e:
                error_msg = f"Erreur {doc['path'].name}: {str(e)}"
                indexing_stats["errors"].append(error_msg)
                socketio.emit('indexing_error', {"error": error_msg})
        
        # Vectorisation
        socketio.emit('indexing_update', {
            "message": f"Vectorisation de {len(all_texts)} chunks...",
            "progress": 85
        })
        
        embeddings = OllamaEmbeddings(
            model=EMBED_MODEL,
            base_url=OLLAMA_HOST
        )
        
        vectorstore = FAISS.from_texts(
            texts=all_texts,
            embedding=embeddings,
            metadatas=all_metadatas
        )
        
        FAISS_DB.parent.mkdir(parents=True, exist_ok=True)
        vectorstore.save_local(str(FAISS_DB))
        
        indexing_stats["status"] = "completed"
        indexing_stats["progress"] = 100
        
        socketio.emit('indexing_complete', indexing_stats)
        
    except Exception as e:
        indexing_stats["status"] = "error"
        indexing_stats["errors"].append(f"Erreur critique: {str(e)}")
        socketio.emit('indexing_error', {"error": str(e), "stats": indexing_stats})
    
    finally:
        indexing_in_progress = False

def query_rag(question: str, k: int = None) -> Dict:
    if k is None:
        k = SETTINGS.get("retrieval_k", 5)
    
    if not FAISS_DB.exists():
        return {
            "success": False,
            "error": "Base vectorielle non initialisée. Lancez l'indexation d'abord."
        }
    
    start_time = time.time()
    
    try:
        embeddings = OllamaEmbeddings(
            model=EMBED_MODEL,
            base_url=OLLAMA_HOST
        )
        
        vectorstore = FAISS.load_local(
            str(FAISS_DB),
            embeddings,
            allow_dangerous_deserialization=True
        )
        
        results = vectorstore.similarity_search(question, k=k)
        
        if not results:
            return {
                "success": False,
                "error": "Aucun document pertinent trouvé"
            }
        
        context = "\n\n".join([doc.page_content for doc in results])
        
        llm = OllamaLLM(
            model=LLM_MODEL,
            base_url=OLLAMA_HOST,
            temperature=SETTINGS.get("temperature", 0.7)
        )
        
        prompt = f"""Tu es un assistant familial bienveillant. Réponds à la question en te basant UNIQUEMENT sur le contexte fourni.
Si l'information n'est pas dans le contexte, dis-le clairement et poliment.

Contexte :
{context}

Question : {question}

Réponse :"""
        
        response = llm.invoke(prompt)
        
        duration = time.time() - start_time
        
        sources = []
        for doc in results:
            sources.append({
                "filename": doc.metadata.get('filename', 'Inconnu'),
                "extension": doc.metadata.get('extension', ''),
                "preview": doc.page_content[:200] + "..."
            })
        
        # Ajouter à l'historique
        source_names = [s["filename"] for s in sources]
        add_to_history(question, response, source_names, duration)
        
        return {
            "success": True,
            "response": response,
            "sources": sources,
            "duration": duration,
            "model": LLM_MODEL,
            "k": k
        }
        
    except Exception as e:
        return {
            "success": False,
            "error": f"Erreur lors de la requête: {str(e)}"
        }

# ============================================
# MÉTRIQUES SYSTÈME
# ============================================

def get_system_metrics():
    metrics = {
        "rag_directory": {
            "exists": RAG_DIR.exists(),
            "accessible": False,
            "file_count": 0,
            "size": 0
        },
        "vector_db": {
            "exists": FAISS_DB.exists(),
            "size": 0,
            "last_update": None,
            "chunks": 0
        },
        "ollama": {
            "accessible": False,
            "models": []
        },
        "history": {
            "count": len(load_history()),
            "last_query": None
        }
    }
    
    # RAG Directory
    if RAG_DIR.exists():
        try:
            metrics["rag_directory"]["accessible"] = True
            files = list(RAG_DIR.rglob("*"))
            metrics["rag_directory"]["file_count"] = len([f for f in files if f.is_file()])
            metrics["rag_directory"]["size"] = sum(f.stat().st_size for f in files if f.is_file())
        except:
            pass
    
    # Vector DB
    if FAISS_DB.exists():
        try:
            index_file = FAISS_DB / "index.faiss"
            if index_file.exists():
                stat = index_file.stat()
                metrics["vector_db"]["size"] = stat.st_size
                metrics["vector_db"]["last_update"] = datetime.fromtimestamp(stat.st_mtime).isoformat()
                # Approximation du nombre de chunks
                metrics["vector_db"]["chunks"] = stat.st_size // 4096
        except:
            pass
    
    # Ollama
    try:
        import requests
        response = requests.get(f"{OLLAMA_HOST}/api/tags", timeout=2)
        if response.status_code == 200:
            metrics["ollama"]["accessible"] = True
            models_data = response.json()
            metrics["ollama"]["models"] = [m["name"] for m in models_data.get("models", [])]
    except:
        pass
    
    # History
    history = load_history()
    if history:
        metrics["history"]["last_query"] = history[-1]["timestamp"]
    
    return metrics

# ============================================
# ROUTES FLASK
# ============================================

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/query', methods=['POST'])
def api_query():
    data = request.json
    question = data.get('question', '')
    k = data.get('k', None)
    
    if not question:
        return jsonify({"success": False, "error": "Question vide"}), 400
    
    result = query_rag(question, k)
    return jsonify(result)

@app.route('/api/index', methods=['POST'])
def api_index():
    global indexing_in_progress
    
    if indexing_in_progress:
        return jsonify({
            "success": False,
            "error": "Indexation déjà en cours"
        }), 409
    
    # Lancer indexation en arrière-plan
    thread = threading.Thread(target=index_documents_background)
    thread.daemon = True
    thread.start()
    
    return jsonify({"success": True, "message": "Indexation démarrée"})

@app.route('/api/indexing/status')
def api_indexing_status():
    return jsonify({
        "in_progress": indexing_in_progress,
        "stats": indexing_stats
    })

@app.route('/api/metrics')
def api_metrics():
    return jsonify(get_system_metrics())

@app.route('/api/history')
def api_history():
    return jsonify(load_history())

@app.route('/api/history/clear', methods=['POST'])
def api_clear_history():
    try:
        if HISTORY_FILE.exists():
            HISTORY_FILE.unlink()
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@app.route('/api/history/export')
def api_export_history():
    history = load_history()
    
    # Créer fichier temporaire
    export_file = Path("/tmp/rag_history_export.json")
    with open(export_file, 'w') as f:
        json.dump(history, f, indent=2, ensure_ascii=False)
    
    return send_file(export_file, as_attachment=True, download_name=f"rag_history_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json")

@app.route('/api/settings', methods=['GET'])
def api_get_settings():
    return jsonify(SETTINGS)

@app.route('/api/settings', methods=['POST'])
def api_save_settings():
    global SETTINGS, OLLAMA_HOST, EMBED_MODEL, LLM_MODEL
    
    data = request.json
    
    # Mettre à jour settings
    SETTINGS.update(data)
    save_settings(SETTINGS)
    
    # Mettre à jour variables globales
    OLLAMA_HOST = SETTINGS["ollama_host"]
    EMBED_MODEL = SETTINGS["embed_model"]
    LLM_MODEL = SETTINGS["llm_model"]
    
    return jsonify({"success": True, "settings": SETTINGS})

@app.route('/api/documents')
def api_documents():
    if not RAG_DIR.exists():
        return jsonify({"success": False, "error": "Dossier RAG non trouvé"}), 404
    
    documents = []
    for file_path in RAG_DIR.rglob("*"):
        if file_path.is_file():
            stat = file_path.stat()
            documents.append({
                "name": file_path.name,
                "path": str(file_path.relative_to(RAG_DIR)),
                "size": stat.st_size,
                "modified": datetime.fromtimestamp(stat.st_mtime).isoformat(),
                "extension": file_path.suffix
            })
    
    return jsonify({"success": True, "documents": documents})

# ============================================
# SOCKETIO EVENTS
# ============================================

@socketio.on('connect')
def handle_connect():
    print(f"Client connecté: {request.sid}")
    emit('connected', {"message": "Connecté au serveur RAG"})

@socketio.on('disconnect')
def handle_disconnect():
    print(f"Client déconnecté: {request.sid}")

@socketio.on('query_stream')
def handle_query_stream(data):
    """Requête avec streaming de la réponse"""
    question = data.get('question', '')
    k = data.get('k', SETTINGS.get("retrieval_k", 5))
    
    if not question:
        emit('query_error', {"error": "Question vide"})
        return
    
    # Récupération contexte
    emit('query_update', {"status": "Recherche de documents pertinents..."})
    
    try:
        if not FAISS_DB.exists():
            emit('query_error', {"error": "Base vectorielle non initialisée"})
            return
        
        embeddings = OllamaEmbeddings(
            model=EMBED_MODEL,
            base_url=OLLAMA_HOST
        )
        
        vectorstore = FAISS.load_local(
            str(FAISS_DB),
            embeddings,
            allow_dangerous_deserialization=True
        )
        
        results = vectorstore.similarity_search(question, k=k)
        
        if not results:
            emit('query_error', {"error": "Aucun document pertinent trouvé"})
            return
        
        emit('query_update', {"status": f"{len(results)} documents trouvés, génération de la réponse..."})
        
        context = "\n\n".join([doc.page_content for doc in results])
        
        llm = OllamaLLM(
            model=LLM_MODEL,
            base_url=OLLAMA_HOST,
            temperature=SETTINGS.get("temperature", 0.7)
        )
        
        prompt = f"""Tu es un assistant familial bienveillant. Réponds à la question en te basant UNIQUEMENT sur le contexte fourni.
Si l'information n'est pas dans le contexte, dis-le clairement et poliment.

Contexte :
{context}

Question : {question}

Réponse :"""
        
        # Streaming response
        response_text = ""
        for chunk in llm.stream(prompt):
            response_text += chunk
            emit('query_chunk', {"chunk": chunk})
        
        sources = [{"filename": doc.metadata.get('filename', 'Inconnu')} for doc in results]
        
        emit('query_complete', {
            "response": response_text,
            "sources": sources
        })
        
        # Ajouter à l'historique
        add_to_history(question, response_text, [s["filename"] for s in sources], 0)
        
    except Exception as e:
        emit('query_error', {"error": str(e)})

# ============================================
# TEMPLATES HTML
# ============================================

# Créer dossier templates
TEMPLATE_DIR = Path(__file__).parent / "templates"
TEMPLATE_DIR.mkdir(exist_ok=True)

# Template HTML principal
INDEX_HTML = """
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>RAG Familial - Interface Web</title>
    <script src="https://cdn.socket.io/4.5.4/socket.io.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        :root {
            --bg-primary: #0f1419;
            --bg-secondary: #1a1f2e;
            --bg-tertiary: #252b3b;
            --accent-primary: #3b82f6;
            --accent-secondary: #8b5cf6;
            --accent-success: #10b981;
            --accent-warning: #f59e0b;
            --accent-danger: #ef4444;
            --text-primary: #e5e7eb;
            --text-secondary: #9ca3af;
            --border-color: #374151;
        }

        body {
            font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            line-height: 1.6;
        }

        .app-container {
            display: grid;
            grid-template-columns: 280px 1fr 320px;
            height: 100vh;
            gap: 1px;
            background: var(--border-color);
        }

        /* SIDEBAR */
        .sidebar {
            background: var(--bg-secondary);
            padding: 1.5rem;
            overflow-y: auto;
        }

        .logo {
            display: flex;
            align-items: center;
            gap: 0.75rem;
            margin-bottom: 2rem;
            padding-bottom: 1rem;
            border-bottom: 1px solid var(--border-color);
        }

        .logo-icon {
            width: 40px;
            height: 40px;
            background: linear-gradient(135deg, var(--accent-primary), var(--accent-secondary));
            border-radius: 10px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 1.5rem;
        }

        .logo-text {
            font-size: 1.25rem;
            font-weight: 700;
            background: linear-gradient(135deg, var(--accent-primary), var(--accent-secondary));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }

        .nav-section {
            margin-bottom: 1.5rem;
        }

        .nav-title {
            font-size: 0.75rem;
            font-weight: 600;
            color: var(--text-secondary);
            text-transform: uppercase;
            letter-spacing: 0.05em;
            margin-bottom: 0.5rem;
        }

        .nav-item {
            display: flex;
            align-items: center;
            gap: 0.75rem;
            padding: 0.75rem;
            border-radius: 8px;
            cursor: pointer;
            transition: all 0.2s;
            margin-bottom: 0.25rem;
        }

        .nav-item:hover {
            background: var(--bg-tertiary);
        }

        .nav-item.active {
            background: var(--accent-primary);
            color: white;
        }

        .nav-icon {
            font-size: 1.25rem;
        }

        /* MAIN CONTENT */
        .main-content {
            background: var(--bg-primary);
            display: flex;
            flex-direction: column;
            overflow: hidden;
        }

        .header {
            background: var(--bg-secondary);
            padding: 1.25rem 2rem;
            border-bottom: 1px solid var(--border-color);
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .header-title {
            font-size: 1.5rem;
            font-weight: 600;
        }

        .header-actions {
            display: flex;
            gap: 0.75rem;
        }

        .btn {
            padding: 0.625rem 1.25rem;
            border: none;
            border-radius: 8px;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.2s;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }

        .btn-primary {
            background: var(--accent-primary);
            color: white;
        }

        .btn-primary:hover {
            background: #2563eb;
            transform: translateY(-1px);
        }

        .btn-secondary {
            background: var(--bg-tertiary);
            color: var(--text-primary);
        }

        .btn-secondary:hover {
            background: var(--border-color);
        }

        .btn:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }

        /* CHAT AREA */
        .chat-container {
            flex: 1;
            display: flex;
            flex-direction: column;
            overflow: hidden;
            padding: 2rem;
        }

        .messages {
            flex: 1;
            overflow-y: auto;
            display: flex;
            flex-direction: column;
            gap: 1.5rem;
            padding-right: 1rem;
        }

        .message {
            display: flex;
            gap: 1rem;
            animation: slideIn 0.3s ease-out;
        }

        @keyframes slideIn {
            from {
                opacity: 0;
                transform: translateY(10px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }

        .message-avatar {
            width: 40px;
            height: 40px;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 1.25rem;
            flex-shrink: 0;
        }

        .message.user .message-avatar {
            background: linear-gradient(135deg, var(--accent-primary), var(--accent-secondary));
        }

        .message.assistant .message-avatar {
            background: var(--bg-tertiary);
        }

        .message-content {
            flex: 1;
            background: var(--bg-secondary);
            padding: 1rem 1.25rem;
            border-radius: 12px;
        }

        .message-meta {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 0.5rem;
            font-size: 0.875rem;
            color: var(--text-secondary);
        }

        .message-text {
            color: var(--text-primary);
            line-height: 1.6;
        }

        .message-sources {
            margin-top: 1rem;
            padding-top: 1rem;
            border-top: 1px solid var(--border-color);
        }

        .source-tag {
            display: inline-flex;
            align-items: center;
            gap: 0.5rem;
            padding: 0.375rem 0.75rem;
            background: var(--bg-tertiary);
            border-radius: 6px;
            font-size: 0.875rem;
            margin-right: 0.5rem;
            margin-bottom: 0.5rem;
        }

        /* INPUT AREA */
        .input-area {
            background: var(--bg-secondary);
            padding: 1.5rem 2rem;
            border-top: 1px solid var(--border-color);
        }

        .input-container {
            display: flex;
            gap: 1rem;
            align-items: flex-end;
        }

        .input-wrapper {
            flex: 1;
            position: relative;
        }

        .input-field {
            width: 100%;
            background: var(--bg-tertiary);
            border: 2px solid var(--border-color);
            border-radius: 12px;
            padding: 1rem 3rem 1rem 1rem;
            color: var(--text-primary);
            font-size: 1rem;
            resize: none;
            font-family: inherit;
            transition: border-color 0.2s;
        }

        .input-field:focus {
            outline: none;
            border-color: var(--accent-primary);
        }

        .input-actions {
            position: absolute;
            right: 0.75rem;
            bottom: 0.75rem;
            display: flex;
            gap: 0.5rem;
        }

        .input-btn {
            width: 36px;
            height: 36px;
            border: none;
            border-radius: 8px;
            background: var(--bg-secondary);
            color: var(--text-secondary);
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            transition: all 0.2s;
        }

        .input-btn:hover {
            background: var(--border-color);
            color: var(--text-primary);
        }

        .send-btn {
            width: 48px;
            height: 48px;
            background: var(--accent-primary);
            border: none;
            border-radius: 12px;
            color: white;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            transition: all 0.2s;
        }

        .send-btn:hover:not(:disabled) {
            background: #2563eb;
            transform: translateY(-2px);
        }

        .send-btn:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }

        /* RIGHT PANEL */
        .right-panel {
            background: var(--bg-secondary);
            padding: 1.5rem;
            overflow-y: auto;
        }

        .panel-section {
            margin-bottom: 2rem;
        }

        .panel-title {
            font-size: 0.875rem;
            font-weight: 600;
            color: var(--text-secondary);
            text-transform: uppercase;
            letter-spacing: 0.05em;
            margin-bottom: 1rem;
        }

        .metric-card {
            background: var(--bg-tertiary);
            padding: 1rem;
            border-radius: 10px;
            margin-bottom: 0.75rem;
        }

        .metric-label {
            font-size: 0.875rem;
            color: var(--text-secondary);
            margin-bottom: 0.25rem;
        }

        .metric-value {
            font-size: 1.5rem;
            font-weight: 600;
            color: var(--text-primary);
        }

        .metric-icon {
            display: inline-block;
            margin-right: 0.5rem;
        }

        .status-indicator {
            display: flex;
            align-items: center;
            gap: 0.5rem;
            padding: 0.75rem;
            background: var(--bg-tertiary);
            border-radius: 8px;
            margin-bottom: 0.5rem;
        }

        .status-dot {
            width: 10px;
            height: 10px;
            border-radius: 50%;
        }

        .status-dot.online {
            background: var(--accent-success);
            box-shadow: 0 0 10px var(--accent-success);
        }

        .status-dot.offline {
            background: var(--accent-danger);
        }

        /* MODALS */
        .modal {
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.7);
            z-index: 1000;
            align-items: center;
            justify-content: center;
        }

        .modal.active {
            display: flex;
        }

        .modal-content {
            background: var(--bg-secondary);
            border-radius: 16px;
            max-width: 600px;
            width: 90%;
            max-height: 80vh;
            overflow-y: auto;
        }

        .modal-header {
            padding: 1.5rem;
            border-bottom: 1px solid var(--border-color);
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .modal-title {
            font-size: 1.25rem;
            font-weight: 600;
        }

        .modal-close {
            width: 32px;
            height: 32px;
            border: none;
            background: var(--bg-tertiary);
            border-radius: 8px;
            color: var(--text-primary);
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
        }

        .modal-body {
            padding: 1.5rem;
        }

        .form-group {
            margin-bottom: 1.5rem;
        }

        .form-label {
            display: block;
            margin-bottom: 0.5rem;
            font-weight: 500;
            color: var(--text-primary);
        }

        .form-input {
            width: 100%;
            padding: 0.75rem;
            background: var(--bg-tertiary);
            border: 2px solid var(--border-color);
            border-radius: 8px;
            color: var(--text-primary);
            font-size: 1rem;
            transition: border-color 0.2s;
        }

        .form-input:focus {
            outline: none;
            border-color: var(--accent-primary);
        }

        /* LOADING */
        .loading {
            display: inline-block;
            width: 20px;
            height: 20px;
            border: 3px solid var(--bg-tertiary);
            border-top-color: var(--accent-primary);
            border-radius: 50%;
            animation: spin 0.8s linear infinite;
        }

        @keyframes spin {
            to { transform: rotate(360deg); }
        }

        /* PROGRESS BAR */
        .progress-bar {
            width: 100%;
            height: 6px;
            background: var(--bg-tertiary);
            border-radius: 3px;
            overflow: hidden;
            margin: 1rem 0;
        }

        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, var(--accent-primary), var(--accent-secondary));
            transition: width 0.3s ease;
        }

        /* SCROLLBAR */
        ::-webkit-scrollbar {
            width: 8px;
        }

        ::-webkit-scrollbar-track {
            background: var(--bg-secondary);
        }

        ::-webkit-scrollbar-thumb {
            background: var(--bg-tertiary);
            border-radius: 4px;
        }

        ::-webkit-scrollbar-thumb:hover {
            background: var(--border-color);
        }

        /* RESPONSIVE */
        @media (max-width: 1200px) {
            .app-container {
                grid-template-columns: 1fr;
            }

            .sidebar, .right-panel {
                display: none;
            }
        }

        /* EMPTY STATE */
        .empty-state {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            height: 100%;
            text-align: center;
            padding: 2rem;
        }

        .empty-icon {
            font-size: 4rem;
            margin-bottom: 1rem;
            opacity: 0.5;
        }

        .empty-title {
            font-size: 1.5rem;
            font-weight: 600;
            margin-bottom: 0.5rem;
        }

        .empty-text {
            color: var(--text-secondary);
            max-width: 400px;
        }
    </style>
</head>
<body>
    <div class="app-container">
        <!-- SIDEBAR -->
        <aside class="sidebar">
            <div class="logo">
                <div class="logo-icon">📚</div>
                <div class="logo-text">RAG Familial</div>
            </div>

            <div class="nav-section">
                <div class="nav-title">Navigation</div>
                <div class="nav-item active" onclick="switchView('chat')">
                    <span class="nav-icon">💬</span>
                    <span>Chat</span>
                </div>
                <div class="nav-item" onclick="switchView('history')">
                    <span class="nav-icon">📜</span>
                    <span>Historique</span>
                </div>
                <div class="nav-item" onclick="switchView('documents')">
                    <span class="nav-icon">📁</span>
                    <span>Documents</span>
                </div>
            </div>

            <div class="nav-section">
                <div class="nav-title">Gestion</div>
                <div class="nav-item" onclick="startIndexing()">
                    <span class="nav-icon">🔄</span>
                    <span>Indexer</span>
                </div>
                <div class="nav-item" onclick="openSettings()">
                    <span class="nav-icon">⚙️</span>
                    <span>Paramètres</span>
                </div>
            </div>
        </aside>

        <!-- MAIN CONTENT -->
        <main class="main-content">
            <header class="header">
                <div>
                    <h1 class="header-title" id="viewTitle">Chat</h1>
                    <div class="header-subtitle" id="viewSubtitle"></div>
                </div>
                <div class="header-actions">
                    <button class="btn btn-secondary" onclick="clearChat()">
                        <span>🗑️</span>
                        <span>Effacer</span>
                    </button>
                    <button class="btn btn-primary" onclick="openSettings()">
                        <span>⚙️</span>
                        <span>Paramètres</span>
                    </button>
                </div>
            </header>

            <!-- CHAT VIEW -->
            <div id="chatView" class="chat-container">
                <div class="messages" id="messages">
                    <div class="empty-state">
                        <div class="empty-icon">🤖</div>
                        <div class="empty-title">Bienvenue dans RAG Familial</div>
                        <p class="empty-text">
                            Posez une question sur vos documents et je vous aiderai à trouver les informations pertinentes.
                        </p>
                    </div>
                </div>
            </div>

            <!-- HISTORY VIEW -->
            <div id="historyView" class="chat-container" style="display: none;">
                <div class="messages" id="historyList">
                    <!-- Populated by JS -->
                </div>
            </div>

            <!-- DOCUMENTS VIEW -->
            <div id="documentsView" class="chat-container" style="display: none;">
                <div class="messages" id="documentsList">
                    <!-- Populated by JS -->
                </div>
            </div>

            <!-- INPUT AREA -->
            <div class="input-area">
                <div class="input-container">
                    <div class="input-wrapper">
                        <textarea 
                            id="queryInput" 
                            class="input-field" 
                            placeholder="Posez votre question..."
                            rows="1"
                            onkeydown="handleKeyPress(event)"
                        ></textarea>
                        <div class="input-actions">
                            <button class="input-btn" onclick="toggleAdvanced()">
                                <span>🎛️</span>
                            </button>
                        </div>
                    </div>
                    <button class="send-btn" onclick="sendQuery()" id="sendBtn">
                        <span>➤</span>
                    </button>
                </div>
            </div>
        </main>

        <!-- RIGHT PANEL -->
        <aside class="right-panel">
            <div class="panel-section">
                <div class="panel-title">État du système</div>
                <div class="status-indicator">
                    <div class="status-dot" id="ollamaStatus"></div>
                    <span>Ollama</span>
                </div>
                <div class="status-indicator">
                    <div class="status-dot" id="vectorDbStatus"></div>
                    <span>Base vectorielle</span>
                </div>
                <div class="status-indicator">
                    <div class="status-dot" id="ragDirStatus"></div>
                    <span>Dossier RAG</span>
                </div>
            </div>

            <div class="panel-section">
                <div class="panel-title">Métriques</div>
                <div class="metric-card">
                    <div class="metric-label">📄 Documents</div>
                    <div class="metric-value" id="docCount">-</div>
                </div>
                <div class="metric-card">
                    <div class="metric-label">🧩 Chunks</div>
                    <div class="metric-value" id="chunkCount">-</div>
                </div>
                <div class="metric-card">
                    <div class="metric-label">📊 Requêtes</div>
                    <div class="metric-value" id="queryCount">-</div>
                </div>
            </div>

            <div class="panel-section">
                <div class="panel-title">Modèles</div>
                <div class="metric-card">
                    <div class="metric-label">Embeddings</div>
                    <div class="metric-value" style="font-size: 0.875rem;" id="embedModel">-</div>
                </div>
                <div class="metric-card">
                    <div class="metric-label">LLM</div>
                    <div class="metric-value" style="font-size: 0.875rem;" id="llmModel">-</div>
                </div>
            </div>
        </aside>
    </div>

    <!-- SETTINGS MODAL -->
    <div class="modal" id="settingsModal">
        <div class="modal-content">
            <div class="modal-header">
                <h2 class="modal-title">⚙️ Paramètres</h2>
                <button class="modal-close" onclick="closeSettings()">✕</button>
            </div>
            <div class="modal-body">
                <div class="form-group">
                    <label class="form-label">URL Ollama</label>
                    <input type="text" class="form-input" id="settingOllamaHost" placeholder="http://localhost:11434">
                </div>
                <div class="form-group">
                    <label class="form-label">Modèle Embeddings</label>
                    <input type="text" class="form-input" id="settingEmbedModel" placeholder="nomic-embed-text:latest">
                </div>
                <div class="form-group">
                    <label class="form-label">Modèle LLM</label>
                    <input type="text" class="form-input" id="settingLlmModel" placeholder="mistral:latest">
                </div>
                <div class="form-group">
                    <label class="form-label">Taille des chunks (tokens)</label>
                    <input type="number" class="form-input" id="settingChunkSize" value="1000">
                </div>
                <div class="form-group">
                    <label class="form-label">Chevauchement (tokens)</label>
                    <input type="number" class="form-input" id="settingChunkOverlap" value="200">
                </div>
                <div class="form-group">
                    <label class="form-label">Nombre de documents (k)</label>
                    <input type="number" class="form-input" id="settingRetrievalK" value="5" min="1" max="20">
                </div>
                <div class="form-group">
                    <label class="form-label">Température (créativité)</label>
                    <input type="number" class="form-input" id="settingTemperature" value="0.7" min="0" max="2" step="0.1">
                </div>
                <div class="form-group">
                    <button class="btn btn-primary" style="width: 100%;" onclick="saveSettings()">
                        💾 Sauvegarder
                    </button>
                </div>
            </div>
        </div>
    </div>

    <!-- INDEXING MODAL -->
    <div class="modal" id="indexingModal">
        <div class="modal-content">
            <div class="modal-header">
                <h2 class="modal-title">🔄 Indexation en cours</h2>
            </div>
            <div class="modal-body">
                <div class="progress-bar">
                    <div class="progress-fill" id="indexingProgress" style="width: 0%"></div>
                </div>
                <div style="text-align: center; margin-top: 1rem;">
                    <p id="indexingMessage">Démarrage...</p>
                    <p style="color: var(--text-secondary); font-size: 0.875rem; margin-top: 0.5rem;" id="indexingStats"></p>
                </div>
            </div>
        </div>
    </div>

    <script>
        // Socket.IO connection
        const socket = io();

        let currentView = 'chat';
        let settings = {};

        // Initialize
        document.addEventListener('DOMContentLoaded', () => {
            loadSettings();
            loadMetrics();
            autoResizeTextarea();
            
            // Refresh metrics every 10s
            setInterval(loadMetrics, 10000);
        });

        // Socket events
        socket.on('connected', (data) => {
            console.log('Connected:', data);
        });

        socket.on('indexing_update', (data) => {
            document.getElementById('indexingProgress').style.width = data.progress + '%';
            document.getElementById('indexingMessage').textContent = data.message;
            if (data.stats) {
                document.getElementById('indexingStats').textContent = 
                    `${data.stats.processed_docs}/${data.stats.total_docs} documents • ${data.stats.total_chunks} chunks`;
            }
        });

        socket.on('indexing_complete', (data) => {
            document.getElementById('indexingProgress').style.width = '100%';
            document.getElementById('indexingMessage').textContent = '✅ Indexation terminée !';
            setTimeout(() => {
                closeModal('indexingModal');
                loadMetrics();
            }, 2000);
        });

        socket.on('indexing_error', (data) => {
            document.getElementById('indexingMessage').innerHTML = '❌ Erreur: ' + data.error;
        });

        // Load settings
        function loadSettings() {
            fetch('/api/settings')
                .then(r => r.json())
                .then(data => {
                    settings = data;
                    document.getElementById('embedModel').textContent = settings.embed_model;
                    document.getElementById('llmModel').textContent = settings.llm_model;
                });
        }

        // Load metrics
        function loadMetrics() {
            fetch('/api/metrics')
                .then(r => r.json())
                .then(data => {
                    // Status indicators
                    document.getElementById('ollamaStatus').className = 
                        'status-dot ' + (data.ollama.accessible ? 'online' : 'offline');
                    document.getElementById('vectorDbStatus').className = 
                        'status-dot ' + (data.vector_db.exists ? 'online' : 'offline');
                    document.getElementById('ragDirStatus').className = 
                        'status-dot ' + (data.rag_directory.accessible ? 'online' : 'offline');
                    
                    // Metrics
                    document.getElementById('docCount').textContent = data.rag_directory.file_count || 0;
                    document.getElementById('chunkCount').textContent = data.vector_db.chunks || 0;
                    document.getElementById('queryCount').textContent = data.history.count || 0;
                });
        }

        // Switch view
        function switchView(view) {
            currentView = view;
            
            // Update nav
            document.querySelectorAll('.nav-item').forEach(item => {
                item.classList.remove('active');
            });
            event.currentTarget.classList.add('active');
            
            // Hide all views
            document.getElementById('chatView').style.display = 'none';
            document.getElementById('historyView').style.display = 'none';
            document.getElementById('documentsView').style.display = 'none';
            
            // Show selected view
            if (view === 'chat') {
                document.getElementById('viewTitle').textContent = 'Chat';
                document.getElementById('chatView').style.display = 'flex';
            } else if (view === 'history') {
                document.getElementById('viewTitle').textContent = 'Historique';
                document.getElementById('historyView').style.display = 'flex';
                loadHistory();
            } else if (view === 'documents') {
                document.getElementById('viewTitle').textContent = 'Documents';
                document.getElementById('documentsView').style.display = 'flex';
                loadDocuments();
            }
        }

        // Send query
        function sendQuery() {
            const input = document.getElementById('queryInput');
            const question = input.value.trim();
            
            if (!question) return;
            
            // Add user message
            addMessage('user', question);
            
            // Clear input
            input.value = '';
            autoResizeTextarea();
            
            // Disable send button
            const sendBtn = document.getElementById('sendBtn');
            sendBtn.disabled = true;
            sendBtn.innerHTML = '<div class="loading"></div>';
            
            // Send to API
            fetch('/api/query', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({question, k: settings.retrieval_k})
            })
            .then(r => r.json())
            .then(data => {
                sendBtn.disabled = false;
                sendBtn.innerHTML = '<span>➤</span>';
                
                if (data.success) {
                    addMessage('assistant', data.response, data.sources, data.duration);
                } else {
                    addMessage('assistant', '❌ ' + data.error);
                }
            })
            .catch(err => {
                sendBtn.disabled = false;
                sendBtn.innerHTML = '<span>➤</span>';
                addMessage('assistant', '❌ Erreur de connexion');
            });
        }

        // Add message to chat
        function addMessage(role, text, sources = null, duration = null) {
            const messages = document.getElementById('messages');
            
            // Remove empty state
            const emptyState = messages.querySelector('.empty-state');
            if (emptyState) emptyState.remove();
            
            const messageDiv = document.createElement('div');
            messageDiv.className = `message ${role}`;
            
            const avatar = role === 'user' ? '👤' : '🤖';
            const name = role === 'user' ? 'Vous' : 'Assistant';
            
            let html = `
                <div class="message-avatar">${avatar}</div>
                <div class="message-content">
                    <div class="message-meta">
                        <span>${name}</span>
                        ${duration ? `<span>⏱️ ${duration.toFixed(2)}s</span>` : ''}
                    </div>
                    <div class="message-text">${text}</div>
            `;
            
            if (sources && sources.length > 0) {
                html += '<div class="message-sources">';
                html += '<div class="panel-title">📚 Sources</div>';
                sources.forEach(source => {
                    html += `<span class="source-tag">📄 ${source.filename}</span>`;
                });
                html += '</div>';
            }
            
            html += '</div>';
            messageDiv.innerHTML = html;
            
            messages.appendChild(messageDiv);
            messages.scrollTop = messages.scrollHeight;
        }

        // Clear chat
        function clearChat() {
            if (confirm('Effacer toute la conversation ?')) {
                const messages = document.getElementById('messages');
                messages.innerHTML = `
                    <div class="empty-state">
                        <div class="empty-icon">🤖</div>
                        <div class="empty-title">Conversation effacée</div>
                        <p class="empty-text">Posez une nouvelle question pour commencer.</p>
                    </div>
                `;
            }
        }

        // Load history
        function loadHistory() {
            fetch('/api/history')
                .then(r => r.json())
                .then(history => {
                    const list = document.getElementById('historyList');
                    list.innerHTML = '';
                    
                    if (history.length === 0) {
                        list.innerHTML = `
                            <div class="empty-state">
                                <div class="empty-icon">📜</div>
                                <div class="empty-title">Aucun historique</div>
                            </div>
                        `;
                        return;
                    }
                    
                    history.reverse().forEach(item => {
                        const date = new Date(item.timestamp).toLocaleString('fr-FR');
                        const div = document.createElement('div');
                        div.className = 'message assistant';
                        div.innerHTML = `
                            <div class="message-avatar">📜</div>
                            <div class="message-content">
                                <div class="message-meta">
                                    <span>${date}</span>
                                    <span>⏱️ ${item.duration.toFixed(2)}s</span>
                                </div>
                                <div class="message-text"><strong>Q:</strong> ${item.query}</div>
                                <div class="message-text" style="margin-top: 0.5rem;"><strong>R:</strong> ${item.response}</div>
                                ${item.sources.length > 0 ? `
                                    <div class="message-sources">
                                        ${item.sources.map(s => `<span class="source-tag">📄 ${s}</span>`).join('')}
                                    </div>
                                ` : ''}
                            </div>
                        `;
                        list.appendChild(div);
                    });
                });
        }

        // Load documents
        function loadDocuments() {
            fetch('/api/documents')
                .then(r => r.json())
                .then(data => {
                    const list = document.getElementById('documentsList');
                    list.innerHTML = '';
                    
                    if (!data.success || data.documents.length === 0) {
                        list.innerHTML = `
                            <div class="empty-state">
                                <div class="empty-icon">📁</div>
                                <div class="empty-title">Aucun document</div>
                            </div>
                        `;
                        return;
                    }
                    
                    data.documents.forEach(doc => {
                        const size = formatSize(doc.size);
                        const date = new Date(doc.modified).toLocaleString('fr-FR');
                        const div = document.createElement('div');
                        div.className = 'metric-card';
                        div.innerHTML = `
                            <div style="display: flex; justify-content: space-between; align-items: center;">
                                <div>
                                    <div style="font-weight: 600;">${doc.extension} ${doc.name}</div>
                                    <div style="font-size: 0.875rem; color: var(--text-secondary); margin-top: 0.25rem;">
                                        ${size} • ${date}
                                    </div>
                                </div>
                            </div>
                        `;
                        list.appendChild(div);
                    });
                });
        }

        // Format file size
        function formatSize(bytes) {
            if (bytes < 1024) return bytes + ' B';
            if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
            if (bytes < 1073741824) return (bytes / 1048576).toFixed(1) + ' MB';
            return (bytes / 1073741824).toFixed(1) + ' GB';
        }

        // Start indexing
        function startIndexing() {
            if (confirm('Lancer l\'indexation des documents ? Cela peut prendre plusieurs minutes.')) {
                openModal('indexingModal');
                fetch('/api/index', {method: 'POST'})
                    .then(r => r.json())
                    .then(data => {
                        if (!data.success) {
                            alert('Erreur: ' + data.error);
                            closeModal('indexingModal');
                        }
                    });
            }
        }

        // Settings modal
        function openSettings() {
            fetch('/api/settings')
                .then(r => r.json())
                .then(data => {
                    document.getElementById('settingOllamaHost').value = data.ollama_host;
                    document.getElementById('settingEmbedModel').value = data.embed_model;
                    document.getElementById('settingLlmModel').value = data.llm_model;
                    document.getElementById('settingChunkSize').value = data.chunk_size;
                    document.getElementById('settingChunkOverlap').value = data.chunk_overlap;
                    document.getElementById('settingRetrievalK').value = data.retrieval_k;
                    document.getElementById('settingTemperature').value = data.temperature;
                    
                    openModal('settingsModal');
                });
        }

        function closeSettings() {
            closeModal('settingsModal');
        }

        function saveSettings() {
            const newSettings = {
                ollama_host: document.getElementById('settingOllamaHost').value,
                embed_model: document.getElementById('settingEmbedModel').value,
                llm_model: document.getElementById('settingLlmModel').value,
                chunk_size: parseInt(document.getElementById('settingChunkSize').value),
                chunk_overlap: parseInt(document.getElementById('settingChunkOverlap').value),
                retrieval_k: parseInt(document.getElementById('settingRetrievalK').value),
                temperature: parseFloat(document.getElementById('settingTemperature').value)
            };
            
            fetch('/api/settings', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify(newSettings)
            })
            .then(r => r.json())
            .then(data => {
                if (data.success) {
                    settings = data.settings;
                    loadSettings();
                    closeSettings();
                    alert('✅ Paramètres sauvegardés ! Rechargez la page pour appliquer les changements.');
                }
            });
        }

        // Modal helpers
        function openModal(id) {
            document.getElementById(id).classList.add('active');
        }

        function closeModal(id) {
            document.getElementById(id).classList.remove('active');
        }

        // Textarea auto-resize
        function autoResizeTextarea() {
            const textarea = document.getElementById('queryInput');
            textarea.style.height = 'auto';
            textarea.style.height = Math.min(textarea.scrollHeight, 200) + 'px';
        }

        document.getElementById('queryInput').addEventListener('input', autoResizeTextarea);

        // Handle Enter key
        function handleKeyPress(event) {
            if (event.key === 'Enter' && !event.shiftKey) {
                event.preventDefault();
                sendQuery();
            }
        }

        // Toggle advanced options
        function toggleAdvanced() {
            // TODO: Implement advanced options panel
            alert('Options avancées à venir !');
        }
    </script>
</body>
</html>
"""

# Écrire le template
with open(TEMPLATE_DIR / "index.html", "w", encoding="utf-8") as f:
    f.write(INDEX_HTML)

# ============================================
# MAIN
# ============================================

if __name__ == '__main__':
    print("""
╔═══════════════════════════════════════════════╗
║                                               ║
║      RAG FAMILIAL - INTERFACE WEB            ║
║         Démarrage du serveur Flask           ║
║                                               ║
╚═══════════════════════════════════════════════╝

Configuration:
  - Ollama    : {ollama}
  - Embeddings: {embed}
  - LLM       : {llm}
  - Dossier   : {rag_dir}
  - Base FAISS: {faiss_db}

Serveur Flask démarré sur http://0.0.0.0:5000
Accessible depuis: http://localhost:5000

Appuyez sur Ctrl+C pour arrêter.
""".format(
        ollama=OLLAMA_HOST,
        embed=EMBED_MODEL,
        llm=LLM_MODEL,
        rag_dir=RAG_DIR,
        faiss_db=FAISS_DB
    ))
    
    socketio.run(app, host='0.0.0.0', port=5000, debug=False)
