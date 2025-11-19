#!/bin/bash
#
# Setup RAG sur VM Fedora pour RAG Familial
# Prérequis: SSH déjà configuré vers le Mac
#

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_info() { echo -e "${CYAN}[i]${NC} $1"; }

# Banner
clear
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════╗
║                                               ║
║         SETUP RAG - RAG FAMILIAL             ║
║            VM Fedora Configuration            ║
║                                               ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# ============================================
# VÉRIFICATION SYSTÈME
# ============================================

print_step "Vérification du système"

if [[ "$(uname -s)" != "Linux" ]]; then
    print_error "Ce script est conçu pour Linux uniquement"
fi

if [[ -f /etc/fedora-release ]]; then
    FEDORA_VERSION=$(cat /etc/fedora-release)
    print_success "Fedora détecté: $FEDORA_VERSION"
else
    print_warning "Fedora non détecté, tentative de continuer..."
fi

# ============================================
# CHARGEMENT CONFIG EXISTANTE
# ============================================

CONFIG_FILE="$HOME/.rag_vm_config"

if [[ -f "$CONFIG_FILE" ]]; then
    echo ""
    print_info "Configuration existante trouvée"
    echo ""
    source "$CONFIG_FILE"
    echo "Configuration actuelle:"
    echo "  - Interface réseau : $NETWORK_INTERFACE"
    echo "  - IP VM            : $VM_IP"
    echo "  - IP Mac           : $MAC_IP"
    echo "  - User Mac         : $MAC_USER"
    echo "  - Point de montage : $MOUNT_POINT"
    echo "  - Ollama URL       : $OLLAMA_HOST"
    echo ""
    read -p "Réutiliser cette configuration ? [y/N]: " REUSE
    
    if [[ "$REUSE" =~ ^[Yy]$ ]]; then
        SKIP_CONFIG=true
        print_success "Configuration rechargée"
    else
        print_info "Nouvelle configuration..."
        rm -f "$CONFIG_FILE"
    fi
fi

# ============================================
# DÉTECTION INTERFACES RÉSEAU
# ============================================

if [[ "$SKIP_CONFIG" != true ]]; then
    echo ""
    print_step "Détection des interfaces réseau avec IP privée"
    echo ""

    # Récupération interfaces avec IPs privées
    declare -a NETWORK_LIST
    declare -a IP_LIST
    
    while IFS= read -r iface; do
        IP=$(ip -4 addr show "$iface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
        if [[ -n "$IP" && "$IP" != "127.0.0.1" ]]; then
            # Filter IPs privées: 10.x, 172.16-31.x, 192.168.x
            if echo "$IP" | grep -qE '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)'; then
                NETWORK_LIST+=("$iface")
                IP_LIST+=("$IP")
            fi
        fi
    done < <(ip -o link show | awk -F': ' '{print $2}' | grep -v 'lo')

    # Vérification
    if [[ ${#NETWORK_LIST[@]} -eq 0 ]]; then
        print_error "Aucune interface réseau privée détectée"
    fi

    # Affichage menu
    echo "Interfaces réseau détectées:"
    echo ""
    for i in "${!NETWORK_LIST[@]}"; do
        printf "  ${MAGENTA}%d)${NC} %-10s → ${CYAN}%s${NC}\n" "$((i+1))" "${NETWORK_LIST[$i]}" "${IP_LIST[$i]}"
    done
    echo ""
    
    # Sélection interface
    while true; do
        read -p "Sélectionnez l'interface pour communiquer avec le Mac [1-${#NETWORK_LIST[@]}]: " IFACE_CHOICE
        
        if [[ "$IFACE_CHOICE" =~ ^[0-9]+$ ]] && \
           [[ "$IFACE_CHOICE" -ge 1 ]] && \
           [[ "$IFACE_CHOICE" -le ${#NETWORK_LIST[@]} ]]; then
            break
        else
            print_warning "Choix invalide, réessayez"
        fi
    done

    NETWORK_INTERFACE="${NETWORK_LIST[$((IFACE_CHOICE-1))]}"
    VM_IP="${IP_LIST[$((IFACE_CHOICE-1))]}"

    echo ""
    print_success "Interface sélectionnée: ${MAGENTA}$NETWORK_INTERFACE${NC} (${CYAN}$VM_IP${NC})"
fi

# ============================================
# CONFIGURATION MAC
# ============================================

if [[ "$SKIP_CONFIG" != true ]]; then
    echo ""
    print_step "Configuration du Mac"
    echo ""
    
    # IP Mac
    while true; do
        read -p "IP du Mac: " MAC_IP
        if [[ "$MAC_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            break
        else
            print_warning "Format IP invalide, réessayez"
        fi
    done
    
    # User Mac
    read -p "Utilisateur sur le Mac (défaut: $(whoami)): " MAC_USER
    MAC_USER=${MAC_USER:-$(whoami)}
    
    # Test SSH
    echo ""
    print_info "Test de connexion SSH vers ${CYAN}$MAC_USER@$MAC_IP${NC}..."
    
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "$MAC_USER@$MAC_IP" "exit" 2>/dev/null; then
        print_success "Connexion SSH validée ✓"
    else
        echo ""
        print_error "Échec connexion SSH. Vérifiez:\n  - SSH configuré avec clés\n  - IP correcte\n  - Mac accessible\n  - Remote Login activé sur Mac"
    fi
    
    # Configuration Ollama
    echo ""
    read -p "URL Ollama (défaut: http://$MAC_IP:11434): " OLLAMA_HOST
    OLLAMA_HOST=${OLLAMA_HOST:-"http://$MAC_IP:11434"}
    
    # Test Ollama
    print_info "Test d'accès à Ollama..."
    if curl -s --connect-timeout 5 "$OLLAMA_HOST/api/tags" >/dev/null 2>&1; then
        print_success "Ollama accessible ✓"
    else
        print_warning "Ollama non accessible depuis la VM"
        echo "  Vérifiez le pare-feu Mac et que Ollama écoute sur 0.0.0.0"
    fi
fi

# ============================================
# CONFIGURATION MONTAGE SSHFS
# ============================================

if [[ "$SKIP_CONFIG" != true ]]; then
    echo ""
    print_step "Configuration du montage SSHFS"
    echo ""
    
    read -p "Chemin du dossier partagé sur le Mac: " MAC_SHARED_DIR
    read -p "Point de montage local (défaut: ~/rag_shared): " MOUNT_POINT
    MOUNT_POINT=${MOUNT_POINT:-"$HOME/rag_shared"}
    
    # Expansion tilde
    MOUNT_POINT="${MOUNT_POINT/#\~/$HOME}"
fi

# ============================================
# RÉSUMÉ CONFIGURATION
# ============================================

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          RÉSUMÉ DE LA CONFIGURATION          ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo "🖥️  Système         : Fedora Linux"
echo "🌐 Interface VM    : $NETWORK_INTERFACE"
echo "📍 IP VM           : $VM_IP"
echo "🔗 Mac             : $MAC_USER@$MAC_IP"
echo "🤖 Ollama URL      : $OLLAMA_HOST"
echo "📁 Dossier Mac     : $MAC_SHARED_DIR"
echo "📂 Point montage   : $MOUNT_POINT"
echo ""

read -p "Confirmer et lancer l'installation ? [y/N]: " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    print_warning "Installation annulée par l'utilisateur"
    exit 0
fi

# ============================================
# SAUVEGARDE CONFIGURATION
# ============================================

print_step "Sauvegarde de la configuration"

cat > "$CONFIG_FILE" << EOF
# Configuration RAG VM Familial - Générée le $(date)

# Réseau
NETWORK_INTERFACE=$NETWORK_INTERFACE
VM_IP=$VM_IP
MAC_IP=$MAC_IP
MAC_USER=$MAC_USER

# Ollama
OLLAMA_HOST=$OLLAMA_HOST

# Montage
MAC_SHARED_DIR=$MAC_SHARED_DIR
MOUNT_POINT=$MOUNT_POINT
EOF

chmod 600 "$CONFIG_FILE"
print_success "Configuration sauvegardée: $CONFIG_FILE"

# ============================================
# MISE À JOUR SYSTÈME
# ============================================

echo ""
print_step "Mise à jour du système"

sudo dnf update -y
print_success "Système mis à jour"

# ============================================
# INSTALLATION DÉPENDANCES SYSTÈME
# ============================================

echo ""
print_step "Installation des dépendances système"

PACKAGES=(
    python3.14
    python3.14-devel
    python3-pip
    git
    curl
    wget
    fuse-sshfs
    gcc
    g++
    make
)

print_info "Installation: ${PACKAGES[*]}"

if sudo dnf install -y "${PACKAGES[@]}"; then
    print_success "Dépendances installées"
else
    print_error "Échec installation dépendances"
fi

# Vérification Python
PYTHON_VERSION=$(python3.14 --version 2>/dev/null || echo "non installé")
print_success "Python: $PYTHON_VERSION"

# ============================================
# MONTAGE SSHFS
# ============================================

echo ""
print_step "Configuration du montage SSHFS"

# Création point de montage avec permissions correctes
if [[ ! -d "$MOUNT_POINT" ]]; then
    mkdir -p "$MOUNT_POINT"
    chmod 755 "$MOUNT_POINT"
    print_success "Point de montage créé: $MOUNT_POINT"
else
    print_info "Point de montage existe déjà"
    
    # Vérifier si déjà monté
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        print_info "Déjà monté, démontage..."
        fusermount -u "$MOUNT_POINT" 2>/dev/null || sudo umount "$MOUNT_POINT" 2>/dev/null || true
        sleep 1
    fi
fi

# Montage SSHFS
print_info "Montage SSHFS: $MAC_USER@$MAC_IP:$MAC_SHARED_DIR → $MOUNT_POINT"

SSHFS_CMD="sshfs $MAC_USER@$MAC_IP:$MAC_SHARED_DIR $MOUNT_POINT \
    -o reconnect \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=3 \
    -o follow_symlinks"

if eval "$SSHFS_CMD" 2>&1; then
    print_success "SSHFS monté avec succès ✓"
else
    print_error "Échec du montage SSHFS. Vérifiez:\n  - Dossier Mac existe: $MAC_SHARED_DIR\n  - SSH fonctionne: ssh $MAC_USER@$MAC_IP ls $MAC_SHARED_DIR"
fi

# Vérification montage
sleep 1
if mountpoint -q "$MOUNT_POINT"; then
    print_success "Vérification: Point monté ✓"
    print_info "Contenu du dossier partagé:"
    ls -la "$MOUNT_POINT" | head -5 || print_warning "Impossible de lister le contenu"
else
    print_error "Le point de montage n'est pas actif"
fi

# ============================================
# CONFIGURATION ENVIRONNEMENT PYTHON
# ============================================

echo ""
print_step "Configuration de l'environnement Python"

RAG_ENV="$HOME/rag_env"

# Suppression ancien environnement
if [[ -d "$RAG_ENV" ]]; then
    print_info "Suppression ancien environnement..."
    rm -rf "$RAG_ENV"
fi

# Création environnement virtuel
print_info "Création environnement virtuel..."
if python3.14 -m venv "$RAG_ENV"; then
    print_success "Environnement créé: $RAG_ENV"
else
    print_error "Échec création environnement virtuel"
fi

# Activation et mise à jour pip
source "$RAG_ENV/bin/activate"

print_info "Mise à jour pip..."
pip install --upgrade pip setuptools wheel

# ============================================
# INSTALLATION PACKAGES PYTHON
# ============================================

echo ""
print_step "Installation des packages Python"

# Installation en deux phases pour gérer FAISS
print_info "Phase 1: Packages de base"

BASE_PACKAGES=(
    "langchain==0.3.13"
    "langchain-community==0.3.13"
    "pypdf==5.1.0"
    "python-docx==1.1.2"
    "odfpy==1.4.1"
    "beautifulsoup4==4.12.3"
    "ebooklib==0.18"
    "python-magic==0.4.27"
    "flask==3.1.0"
    "flask-socketio==5.4.1"
    "requests==2.32.3"
)

for pkg in "${BASE_PACKAGES[@]}"; do
    echo -ne "${BLUE}[→]${NC} Installation $pkg..."
    if pip install "$pkg" >/dev/null 2>&1; then
        echo -e "\r${GREEN}[✓]${NC} Installation $pkg"
    else
        echo -e "\r${RED}[✗]${NC} Échec $pkg"
    fi
done

# Installation FAISS avec fallback
print_info "Phase 2: Installation FAISS"

# Tentative version récente
echo -ne "${BLUE}[→]${NC} Installation faiss-cpu (dernière version)..."
if pip install faiss-cpu >/dev/null 2>&1; then
    echo -e "\r${GREEN}[✓]${NC} Installation faiss-cpu"
else
    echo -e "\r${YELLOW}[!]${NC} Version récente échouée, tentative version stable..."
    
    # Fallback sur version stable
    if pip install faiss-cpu==1.8.0 >/dev/null 2>&1; then
        echo -e "${GREEN}[✓]${NC} Installation faiss-cpu==1.8.0"
    else
        print_error "Échec installation FAISS. Python 3.14 peut nécessiter compilation manuelle."
    fi
fi

print_success "Packages Python installés"

# ============================================
# CRÉATION SCRIPT RAG
# ============================================

echo ""
print_step "Création du script RAG"

RAG_SCRIPT="$HOME/rag.py"

cat > "$RAG_SCRIPT" << 'EOFRAG'
#!/usr/bin/env python3
"""
RAG Familial - Script principal
Indexation et requêtes sur base vectorielle FAISS
"""

import os
import sys
from pathlib import Path
from typing import List
from langchain_community.document_loaders import (
    TextLoader, PyPDFLoader, Docx2txtLoader, UnstructuredODTLoader,
    UnstructuredHTMLLoader, UnstructuredEmailLoader, UnstructuredEPubLoader
)
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_community.embeddings import OllamaEmbeddings
from langchain_community.llms import Ollama
from langchain_community.vectorstores import FAISS
from langchain.chains import RetrievalQA

# Configuration
OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://192.168.198.1:11434")
EMBED_MODEL = os.getenv("EMBED_MODEL", "nomic-embed-text")
LLM_MODEL = os.getenv("LLM_MODEL", "mistral:latest")
RAG_DIR = Path(os.getenv("RAG_DIR", Path.home() / "rag_shared"))
FAISS_DB = Path(os.getenv("FAISS_DB", Path.home() / "faiss_index"))

# Formats supportés
LOADERS = {
    ".txt": TextLoader,
    ".md": TextLoader,
    ".pdf": PyPDFLoader,
    ".docx": Docx2txtLoader,
    ".odt": UnstructuredODTLoader,
    ".html": UnstructuredHTMLLoader,
    ".htm": UnstructuredHTMLLoader,
    ".eml": UnstructuredEmailLoader,
    ".epub": UnstructuredEPubLoader,
}

def load_documents(directory: Path) -> List:
    """Charge tous les documents supportés"""
    docs = []
    for file_path in directory.rglob("*"):
        if file_path.is_file() and file_path.suffix.lower() in LOADERS:
            try:
                loader_class = LOADERS[file_path.suffix.lower()]
                loader = loader_class(str(file_path))
                docs.extend(loader.load())
                print(f"✓ {file_path.name}")
            except Exception as e:
                print(f"✗ {file_path.name}: {e}")
    return docs

def index_documents():
    """Indexe les documents dans FAISS"""
    print(f"\n[INDEXATION] Dossier: {RAG_DIR}")
    
    if not RAG_DIR.exists():
        print(f"✗ Dossier inexistant: {RAG_DIR}")
        sys.exit(1)
    
    # Chargement documents
    print("\nChargement des documents...")
    docs = load_documents(RAG_DIR)
    
    if not docs:
        print("✗ Aucun document trouvé")
        sys.exit(1)
    
    print(f"\n✓ {len(docs)} documents chargés")
    
    # Découpage
    print("\nDécoupage en chunks...")
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=1000,
        chunk_overlap=200
    )
    chunks = splitter.split_documents(docs)
    print(f"✓ {len(chunks)} chunks créés")
    
    # Embeddings
    print(f"\nGénération embeddings via {OLLAMA_HOST}...")
    embeddings = OllamaEmbeddings(
        model=EMBED_MODEL,
        base_url=OLLAMA_HOST
    )
    
    # Création index FAISS
    print("Création index FAISS...")
    vectorstore = FAISS.from_documents(chunks, embeddings)
    
    # Sauvegarde
    FAISS_DB.mkdir(parents=True, exist_ok=True)
    vectorstore.save_local(str(FAISS_DB))
    print(f"\n✓ Index sauvegardé: {FAISS_DB}")

def query_documents(question: str):
    """Interroge la base vectorielle"""
    if not FAISS_DB.exists():
        print("✗ Index FAISS inexistant. Lancer: rag.py index")
        sys.exit(1)
    
    print(f"\n[REQUÊTE] {question}")
    
    # Chargement index
    embeddings = OllamaEmbeddings(
        model=EMBED_MODEL,
        base_url=OLLAMA_HOST
    )
    vectorstore = FAISS.load_local(
        str(FAISS_DB),
        embeddings,
        allow_dangerous_deserialization=True
    )
    
    # Configuration LLM
    llm = Ollama(
        model=LLM_MODEL,
        base_url=OLLAMA_HOST,
        temperature=0.3
    )
    
    # Chaîne QA
    qa_chain = RetrievalQA.from_chain_type(
        llm=llm,
        retriever=vectorstore.as_retriever(search_kwargs={"k": 3}),
        return_source_documents=True
    )
    
    # Exécution
    result = qa_chain.invoke({"query": question})
    
    print("\n" + "="*60)
    print("RÉPONSE:")
    print("="*60)
    print(result["result"])
    print("\n" + "="*60)
    print("SOURCES:")
    print("="*60)
    for i, doc in enumerate(result["source_documents"], 1):
        source = doc.metadata.get("source", "N/A")
        print(f"\n[{i}] {Path(source).name}")
        print(f"    {doc.page_content[:150]}...")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python rag.py index              # Indexer les documents")
        print("  python rag.py query 'question'   # Interroger")
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == "index":
        index_documents()
    elif command == "query":
        if len(sys.argv) < 3:
            print("✗ Question manquante")
            sys.exit(1)
        query_documents(" ".join(sys.argv[2:]))
    else:
        print(f"✗ Commande inconnue: {command}")
        sys.exit(1)
EOFRAG

chmod +x "$RAG_SCRIPT"
print_success "Script RAG créé: $RAG_SCRIPT"

# ============================================
# CRÉATION WRAPPER CLI
# ============================================

print_step "Création du wrapper CLI"

cat > "$HOME/rag_env/bin/rag" << 'EOFWRAPPER'
#!/bin/bash
source "$HOME/rag_env/bin/activate"
export OLLAMA_HOST="__OLLAMA_HOST__"
export RAG_DIR="__MOUNT_POINT__"
export FAISS_DB="$HOME/faiss_index"
python "$HOME/rag.py" "$@"
EOFWRAPPER

# Remplacement variables
sed -i "s|__OLLAMA_HOST__|$OLLAMA_HOST|g" "$HOME/rag_env/bin/rag"
sed -i "s|__MOUNT_POINT__|$MOUNT_POINT|g" "$HOME/rag_env/bin/rag"

chmod +x "$HOME/rag_env/bin/rag"
print_success "Wrapper CLI créé: ~/rag_env/bin/rag"

# ============================================
# CRÉATION WEBUI FLASK
# ============================================

echo ""
print_step "Création de la WebUI Flask"

WEBUI_SCRIPT="$HOME/rag_webui.py"

cat > "$WEBUI_SCRIPT" << 'EOFWEBUI'
#!/usr/bin/env python3
"""
RAG Familial - Interface Web Flask
"""

from flask import Flask, render_template_string, request, jsonify
import subprocess
import os
from pathlib import Path

app = Flask(__name__)

OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://192.168.198.1:11434")
RAG_DIR = Path(os.getenv("RAG_DIR", Path.home() / "rag_shared"))

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>RAG Familial</title>
    <meta charset="utf-8">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        .content {
            padding: 30px;
        }
        .query-box {
            margin-bottom: 20px;
        }
        textarea {
            width: 100%;
            padding: 15px;
            border: 2px solid #667eea;
            border-radius: 10px;
            font-size: 16px;
            resize: vertical;
        }
        button {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 15px 40px;
            border-radius: 10px;
            font-size: 16px;
            cursor: pointer;
            margin-top: 10px;
        }
        button:hover { opacity: 0.9; }
        .response {
            margin-top: 20px;
            padding: 20px;
            background: #f8f9fa;
            border-radius: 10px;
            display: none;
        }
        .loading {
            text-align: center;
            padding: 20px;
            display: none;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📚 RAG Familial</h1>
            <p>Bibliothèque documentaire intelligente</p>
        </div>
        <div class="content">
            <div class="query-box">
                <h2>💬 Posez votre question</h2>
                <textarea id="question" rows="4" placeholder="Ex: Quelles sont les informations sur..."></textarea>
                <button onclick="askQuestion()">Interroger</button>
                <button onclick="indexDocuments()">Réindexer</button>
            </div>
            <div class="loading" id="loading">
                <p>⏳ Traitement en cours...</p>
            </div>
            <div class="response" id="response"></div>
        </div>
    </div>
    
    <script>
        async function askQuestion() {
            const question = document.getElementById('question').value;
            if (!question) return alert('Veuillez saisir une question');
            
            document.getElementById('loading').style.display = 'block';
            document.getElementById('response').style.display = 'none';
            
            const res = await fetch('/query', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({question})
            });
            
            const data = await res.json();
            
            document.getElementById('loading').style.display = 'none';
            document.getElementById('response').style.display = 'block';
            document.getElementById('response').innerHTML = `
                <h3>Réponse:</h3>
                <p>${data.answer || data.error}</p>
            `;
        }
        
        async function indexDocuments() {
            if (!confirm('Réindexer tous les documents ?')) return;
            
            document.getElementById('loading').style.display = 'block';
            
            const res = await fetch('/index', {method: 'POST'});
            const data = await res.json();
            
            document.getElementById('loading').style.display = 'none';
            alert(data.message || data.error);
        }
    </script>
</body>
</html>
"""

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE)

@app.route('/query', methods=['POST'])
def query():
    data = request.json
    question = data.get('question', '')
    
    try:
        result = subprocess.run(
            [f"{Path.home()}/rag_env/bin/rag", "query", question],
            capture_output=True,
            text=True,
            timeout=60
        )
        
        # Extraction réponse
        output = result.stdout
        if "RÉPONSE:" in output:
            answer = output.split("RÉPONSE:")[1].split("SOURCES:")[0].strip()
            return jsonify({"answer": answer.replace("="*60, "").strip()})
        
        return jsonify({"error": "Erreur traitement"})
    except Exception as e:
        return jsonify({"error": str(e)})

@app.route('/index', methods=['POST'])
def index_docs():
    try:
        result = subprocess.run(
            [f"{Path.home()}/rag_env/bin/rag", "index"],
            capture_output=True,
            text=True,
            timeout=300
        )
        return jsonify({"message": "Indexation terminée ✓"})
    except Exception as e:
        return jsonify({"error": str(e)})

if __name__ == '__main__':
    print(f"""
╔═══════════════════════════════════════════════╗
║          RAG FAMILIAL - WEBUI                ║
╚═══════════════════════════════════════════════╝

🌐 Accès: http://{os.getenv('VM_IP', 'localhost')}:5000
🤖 Ollama: {OLLAMA_HOST}
📁 Documents: {RAG_DIR}

Appuyez sur Ctrl+C pour arrêter
""")
    app.run(host='0.0.0.0', port=5000, debug=False)
EOFWEBUI

chmod +x "$WEBUI_SCRIPT"
print_success "WebUI créée: $WEBUI_SCRIPT"

# ============================================
# CONFIGURATION FIREWALL
# ============================================

echo ""
print_step "Configuration du pare-feu"

if systemctl is-active --quiet firewalld; then
    print_info "Ouverture du port 5000 (Flask)..."
    sudo firewall-cmd --permanent --add-port=5000/tcp
    sudo firewall-cmd --reload
    print_success "Port 5000 ouvert ✓"
else
    print_info "Firewalld inactif, pas de configuration nécessaire"
fi

# ============================================
# TEST OLLAMA
# ============================================

echo ""
print_step "Test de connectivité Ollama"

if curl -s --connect-timeout 5 "$OLLAMA_HOST/api/tags" >/dev/null 2>&1; then
    print_success "Ollama accessible depuis la VM ✓"
    
    # Liste modèles
    print_info "Modèles disponibles:"
    curl -s "$OLLAMA_HOST/api/tags" | python3 -m json.tool 2>/dev/null | grep '"name"' | head -5
else
    print_warning "Ollama non accessible"
    echo "  Vérifiez:"
    echo "    - URL: $OLLAMA_HOST"
    echo "    - Pare-feu Mac"
    echo "    - Ollama écoute sur 0.0.0.0"
fi

# ============================================
# RÉSUMÉ FINAL
# ============================================

echo ""
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════╗
║                                               ║
║       INSTALLATION TERMINÉE AVEC SUCCÈS      ║
║                                               ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo ""
echo "✅ Configuration complète:"
echo ""
echo "🖥️  Système:"
echo "   - IP VM            : $VM_IP"
echo "   - IP Mac           : $MAC_IP"
echo "   - Python           : $(python3.14 --version 2>/dev/null)"
echo ""
echo "📁 Dossiers:"
echo "   - Point de montage : $MOUNT_POINT"
echo "   - Index FAISS      : ~/faiss_index"
echo "   - Environnement    : ~/rag_env"
echo ""
echo "🤖 Ollama:"
echo "   - URL              : $OLLAMA_HOST"
echo ""
echo "🌐 WebUI:"
echo "   - URL              : http://$VM_IP:5000"
echo ""
echo "📝 Commandes utiles:"
echo ""
echo "   # Activer l'environnement"
echo "   source ~/rag_env/bin/activate"
echo ""
echo "   # Indexer les documents"
echo "   ~/rag_env/bin/rag index"
echo ""
echo "   # Interroger"
echo "   ~/rag_env/bin/rag query 'Votre question'"
echo ""
echo "   # Lancer la WebUI"
echo "   python ~/rag_webui.py"
echo ""
echo "   # Vérifier le montage"
echo "   ls -la $MOUNT_POINT"
echo ""
echo "   # Remonter SSHFS si déconnecté"
echo "   fusermount -u $MOUNT_POINT"
echo "   sshfs $MAC_USER@$MAC_IP:$MAC_SHARED_DIR $MOUNT_POINT -o reconnect"
echo ""
echo -e "${CYAN}📄 Configuration sauvegardée:${NC} $CONFIG_FILE"
echo ""
print_success "Setup VM terminé!"
