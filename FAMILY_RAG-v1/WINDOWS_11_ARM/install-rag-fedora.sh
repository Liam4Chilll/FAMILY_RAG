#!/bin/bash
#
# Setup FAMILY RAG sur Fedora Linux (Générique)
# Version STABLE pour déploiement GitHub
# Compatible avec toute infrastructure Linux + Ollama distant
#

set -e

# ============================================
# FONCTIONS UTILITAIRES
# ============================================

# Détection automatique IP Fedora
get_fedora_ip() {
    local ip=$(hostname -I | awk '{print $1}')
    if [[ -z "$ip" || "$ip" == "127.0.0.1" ]]; then
        echo "192.168.1.130"
    else
        echo "$ip"
    fi
}

# Calcul IP Windows (même subnet, dernier octet différent)
calculate_windows_ip() {
    local fedora_ip="$1"
    echo "$fedora_ip" | sed 's/\.[0-9]*$/\.131/'
}

# Validation format IP
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Test connectivité
test_connectivity() {
    local ip=$1
    local port=$2
    local service=$3
    
    if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$ip/$port" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# ============================================
# COULEURS
# ============================================

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
print_info() { echo -e "${CYAN}[→]${NC} $1"; }

# ============================================
# BANNER
# ============================================

clear
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════╗
║                                               ║
║         SETUP RAG - LINUX CLIENT              ║
║      Produit par Liam4Chill                   ║
║    (Compatible Fedora/Ubuntu/Debian)          ║
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

if command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
    print_success "Gestionnaire de paquets: DNF (Fedora/RHEL)"
elif command -v apt &>/dev/null; then
    PKG_MANAGER="apt"
    print_success "Gestionnaire de paquets: APT (Ubuntu/Debian)"
else
    print_error "Gestionnaire de paquets non supporté"
fi

# ============================================
# CONFIGURATION INTERACTIVE
# ============================================

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          CONFIGURATION DU SYSTÈME             ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Veuillez fournir les informations suivantes.${NC}"
echo -e "${YELLOW}Appuyez sur [Entrée] pour accepter la valeur par défaut.${NC}"
echo ""

# Détection automatique IP Fedora
DETECTED_FEDORA_IP=$(get_fedora_ip)
print_info "IP Fedora détectée automatiquement: $DETECTED_FEDORA_IP"

# Prompt IP Fedora
while true; do
    read -p "IP de cette machine Fedora [$DETECTED_FEDORA_IP]: " INPUT_FEDORA_IP
    FEDORA_IP="${INPUT_FEDORA_IP:-$DETECTED_FEDORA_IP}"
    
    if validate_ip "$FEDORA_IP"; then
        print_success "IP Fedora: $FEDORA_IP"
        break
    else
        print_warning "Format IP invalide. Exemple: 192.168.1.130"
    fi
done

# Prompt IP Windows (avec calcul automatique)
echo ""
CALCULATED_WINDOWS_IP=$(calculate_windows_ip "$FEDORA_IP")
print_info "IP Windows suggérée (même subnet): $CALCULATED_WINDOWS_IP"

while true; do
    read -p "IP du serveur Windows (Ollama) [$CALCULATED_WINDOWS_IP]: " INPUT_WINDOWS_IP
    WINDOWS_IP="${INPUT_WINDOWS_IP:-$CALCULATED_WINDOWS_IP}"
    
    if validate_ip "$WINDOWS_IP"; then
        print_success "IP Windows: $WINDOWS_IP"
        break
    else
        print_warning "Format IP invalide"
    fi
done

# Prompt Hostname Windows
echo ""
DEFAULT_WINDOWS_HOSTNAME="WINDOWS"
read -p "Hostname Windows [$DEFAULT_WINDOWS_HOSTNAME]: " INPUT_WINDOWS_HOSTNAME
WINDOWS_HOSTNAME="${INPUT_WINDOWS_HOSTNAME:-$DEFAULT_WINDOWS_HOSTNAME}"
print_success "Hostname Windows: $WINDOWS_HOSTNAME"

# Prompt Utilisateur Windows
echo ""
DEFAULT_WINDOWS_USER="user"
read -p "Utilisateur Windows (pour SMB) [$DEFAULT_WINDOWS_USER]: " INPUT_WINDOWS_USER
WINDOWS_USER="${INPUT_WINDOWS_USER:-$DEFAULT_WINDOWS_USER}"
print_success "Utilisateur Windows: $WINDOWS_USER"

# Prompt Utilisateur Fedora
echo ""
DEFAULT_FEDORA_USER=$(whoami)
read -p "Utilisateur Fedora [$DEFAULT_FEDORA_USER]: " INPUT_FEDORA_USER
FEDORA_USER="${INPUT_FEDORA_USER:-$DEFAULT_FEDORA_USER}"
print_success "Utilisateur Fedora: $FEDORA_USER"

# Prompt Nom du partage SMB
echo ""
DEFAULT_SMB_SHARE="RAG"
read -p "Nom du partage SMB sur Windows [$DEFAULT_SMB_SHARE]: " INPUT_SMB_SHARE
SMB_SHARE="${INPUT_SMB_SHARE:-$DEFAULT_SMB_SHARE}"
SMB_PATH="//$WINDOWS_IP/$SMB_SHARE"
print_success "Partage SMB: $SMB_PATH"

# Prompt Point de montage
echo ""
DEFAULT_MOUNT_POINT="$HOME/RAG"
read -p "Point de montage local [$DEFAULT_MOUNT_POINT]: " INPUT_MOUNT_POINT
MOUNT_POINT="${INPUT_MOUNT_POINT:-$DEFAULT_MOUNT_POINT}"
print_success "Point de montage: $MOUNT_POINT"

# Configuration Ollama
echo ""
print_info "Configuration Ollama (défauts recommandés)"

OLLAMA_HOST="http://$WINDOWS_IP:11434"
DEFAULT_EMBED_MODEL="nomic-embed-text"
read -p "Modèle d'embeddings [$DEFAULT_EMBED_MODEL]: " INPUT_EMBED_MODEL
EMBED_MODEL="${INPUT_EMBED_MODEL:-$DEFAULT_EMBED_MODEL}"

DEFAULT_LLM_MODEL="mistral:latest"
read -p "Modèle LLM [$DEFAULT_LLM_MODEL]: " INPUT_LLM_MODEL
LLM_MODEL="${INPUT_LLM_MODEL:-$DEFAULT_LLM_MODEL}"

# Chemins locaux
echo ""
print_info "Configuration des chemins locaux"

DEFAULT_FAISS_DB="$HOME/faiss_index"
read -p "Dossier index FAISS [$DEFAULT_FAISS_DB]: " INPUT_FAISS_DB
FAISS_DB="${INPUT_FAISS_DB:-$DEFAULT_FAISS_DB}"

DEFAULT_RAG_ENV="$HOME/rag_env"
read -p "Environnement Python virtuel [$DEFAULT_RAG_ENV]: " INPUT_RAG_ENV
RAG_ENV="${INPUT_RAG_ENV:-$DEFAULT_RAG_ENV}"

# Version Python
echo ""
DEFAULT_PYTHON_VERSION="3.13"
read -p "Version Python [$DEFAULT_PYTHON_VERSION]: " INPUT_PYTHON_VERSION
PYTHON_VERSION="${INPUT_PYTHON_VERSION:-$DEFAULT_PYTHON_VERSION}"
PYTHON_CMD="python${PYTHON_VERSION}"

# ============================================
# RÉSUMÉ CONFIGURATION
# ============================================

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          RÉSUMÉ DE LA CONFIGURATION          ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo "🖥️  Système         : $(cat /etc/*release | grep PRETTY_NAME | cut -d'"' -f2 2>/dev/null || echo 'Linux')"
echo "🏠 IP Fedora       : $FEDORA_IP"
echo "🔗 IP Windows      : $WINDOWS_IP"
echo "🤖 Ollama URL      : $OLLAMA_HOST"
echo "🗂️  Partage SMB     : $SMB_PATH"
echo "📂 Point montage   : $MOUNT_POINT"
echo "🐍 Python          : $PYTHON_VERSION"
echo "🧠 Modèle embed    : $EMBED_MODEL"
echo "💬 Modèle LLM      : $LLM_MODEL"
echo "🌐 WebUI           : http://$FEDORA_IP:5000"
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

CONFIG_FILE="$HOME/.rag_fedora_config"

cat > "$CONFIG_FILE" << EOF
# Configuration RAG Fedora - Généré le $(date)

# Réseau
WINDOWS_IP=$WINDOWS_IP
WINDOWS_HOSTNAME=$WINDOWS_HOSTNAME
WINDOWS_USER=$WINDOWS_USER
FEDORA_IP=$FEDORA_IP
FEDORA_USER=$FEDORA_USER

# Ollama
OLLAMA_HOST=$OLLAMA_HOST
EMBED_MODEL=$EMBED_MODEL
LLM_MODEL=$LLM_MODEL

# SMB
SMB_SHARE=$SMB_SHARE
SMB_PATH=$SMB_PATH
MOUNT_POINT=$MOUNT_POINT

# RAG
FAISS_DB=$FAISS_DB
RAG_ENV=$RAG_ENV

# Python
PYTHON_VERSION=$PYTHON_VERSION
PYTHON_CMD=$PYTHON_CMD
EOF

chmod 600 "$CONFIG_FILE"
print_success "Configuration sauvegardée: $CONFIG_FILE"

# ============================================
# MISE À JOUR SYSTÈME
# ============================================

echo ""
print_step "Mise à jour du système"

if [[ "$PKG_MANAGER" == "dnf" ]]; then
    sudo dnf update -y
elif [[ "$PKG_MANAGER" == "apt" ]]; then
    sudo apt update && sudo apt upgrade -y
fi

print_success "Système mis à jour"

# ============================================
# INSTALLATION DÉPENDANCES SYSTÈME
# ============================================

echo ""
print_step "Installation des dépendances système"

if [[ "$PKG_MANAGER" == "dnf" ]]; then
    PACKAGES=(
        python${PYTHON_VERSION}
        python${PYTHON_VERSION}-devel
        git curl wget
        cifs-utils samba-client
        gcc g++ make
    )
    
    print_info "Installation: ${PACKAGES[*]}"
    sudo dnf install -y "${PACKAGES[@]}" --skip-unavailable
    
elif [[ "$PKG_MANAGER" == "apt" ]]; then
    PACKAGES=(
        python${PYTHON_VERSION}
        python${PYTHON_VERSION}-dev python${PYTHON_VERSION}-venv
        git curl wget
        cifs-utils smbclient
        gcc g++ make
        build-essential
    )
    
    print_info "Installation: ${PACKAGES[*]}"
    sudo apt install -y "${PACKAGES[@]}" 2>/dev/null || true
fi

# Vérification Python
if command -v $PYTHON_CMD &>/dev/null; then
    PYTHON_CHECK=$($PYTHON_CMD --version 2>/dev/null)
    print_success "Python: $PYTHON_CHECK"
else
    print_error "Python $PYTHON_VERSION non installé"
fi

# ============================================
# TEST CONNECTIVITÉ WINDOWS
# ============================================

echo ""
print_step "Test de connectivité Windows"

print_info "Ping vers $WINDOWS_IP..."
if ping -c 3 -W 2 "$WINDOWS_IP" >/dev/null 2>&1; then
    print_success "Windows accessible via ping ✓"
else
    print_warning "Ping échoué (peut continuer si pare-feu bloque ICMP)"
fi

print_info "Test SMB (port 445)..."
if test_connectivity "$WINDOWS_IP" 445 "SMB"; then
    print_success "Port SMB 445 accessible ✓"
else
    print_error "Port SMB 445 non accessible - Vérifiez le pare-feu Windows"
fi

print_info "Test Ollama API (port 11434)..."
if test_connectivity "$WINDOWS_IP" 11434 "Ollama"; then
    print_success "Port Ollama 11434 accessible ✓"
else
    print_warning "Port Ollama 11434 non accessible - Assurez-vous qu'Ollama est démarré sur Windows"
fi

# Test API Ollama complet
if curl -s --connect-timeout 5 "$OLLAMA_HOST/api/tags" >/dev/null 2>&1; then
    print_success "Ollama API fonctionnelle ✓"
else
    print_warning "Ollama API non accessible - L'indexation nécessitera Ollama"
fi

# ============================================
# CONFIGURATION CREDENTIALS SMB
# ============================================

echo ""
print_step "Configuration des credentials SMB"

SMB_CREDS="$HOME/.smbcredentials"

if [[ -f "$SMB_CREDS" ]]; then
    print_info "Credentials existants trouvés"
    read -p "Réutiliser les credentials existants ? [Y/n]: " REUSE_CREDS
    
    if [[ "$REUSE_CREDS" =~ ^[Nn]$ ]]; then
        rm -f "$SMB_CREDS"
    fi
fi

if [[ ! -f "$SMB_CREDS" ]]; then
    echo ""
    print_info "Configuration des credentials Windows"
    echo ""
    
    read -p "Utilisateur Windows (défaut: $WINDOWS_USER): " INPUT_USER
    INPUT_USER=${INPUT_USER:-$WINDOWS_USER}
    
    read -sp "Mot de passe Windows: " INPUT_PASS
    echo ""
    
    cat > "$SMB_CREDS" << EOF
username=$INPUT_USER
password=$INPUT_PASS
domain=WORKGROUP
EOF
    
    chmod 600 "$SMB_CREDS"
    print_success "Credentials sauvegardés: $SMB_CREDS"
else
    print_success "Credentials existants réutilisés"
fi

# ============================================
# MONTAGE SMB
# ============================================

echo ""
print_step "Configuration du montage SMB"

if [[ ! -d "$MOUNT_POINT" ]]; then
    mkdir -p "$MOUNT_POINT"
    chmod 755 "$MOUNT_POINT"
    print_success "Point de montage créé: $MOUNT_POINT"
else
    print_info "Point de montage existe déjà"
    
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        print_info "Déjà monté, démontage..."
        sudo umount "$MOUNT_POINT" 2>/dev/null || true
        sleep 2
    fi
fi

print_info "Montage SMB: $SMB_PATH → $MOUNT_POINT"

MOUNT_CMD="sudo mount -t cifs $SMB_PATH $MOUNT_POINT \
    -o credentials=$SMB_CREDS,uid=$(id -u),gid=$(id -g),file_mode=0755,dir_mode=0755,vers=3.0"

if eval "$MOUNT_CMD" 2>&1; then
    print_success "SMB monté avec succès ✓"
else
    print_error "Échec du montage SMB - Vérifiez les credentials et le partage Windows"
fi

sleep 2
if mountpoint -q "$MOUNT_POINT"; then
    print_success "Vérification: Point monté ✓"
    
    if ls "$MOUNT_POINT" >/dev/null 2>&1; then
        FILE_COUNT=$(find "$MOUNT_POINT" -type f 2>/dev/null | wc -l)
        print_info "Fichiers détectés: $FILE_COUNT"
    fi
fi

# ============================================
# MONTAGE PERSISTANT (OPTIONNEL)
# ============================================

echo ""
print_step "Montage persistant au démarrage (optionnel)"

read -p "Ajouter le montage SMB à /etc/fstab ? [y/N]: " ADD_FSTAB

if [[ "$ADD_FSTAB" =~ ^[Yy]$ ]]; then
    FSTAB_ENTRY="$SMB_PATH $MOUNT_POINT cifs credentials=$SMB_CREDS,uid=$(id -u),gid=$(id -g),file_mode=0755,dir_mode=0755,vers=3.0,_netdev,noauto,x-systemd.automount 0 0"
    
    if grep -q "$SMB_PATH" /etc/fstab 2>/dev/null; then
        print_info "Entrée fstab existe déjà"
    else
        sudo cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)
        echo "$FSTAB_ENTRY" | sudo tee -a /etc/fstab >/dev/null
        print_success "Entrée fstab ajoutée"
    fi
fi

# ============================================
# CONFIGURATION ENVIRONNEMENT PYTHON
# ============================================

echo ""
print_step "Configuration de l'environnement Python"

if [[ -d "$RAG_ENV" ]]; then
    print_info "Suppression ancien environnement..."
    rm -rf "$RAG_ENV"
fi

print_info "Création environnement virtuel..."
if $PYTHON_CMD -m venv "$RAG_ENV"; then
    print_success "Environnement créé: $RAG_ENV"
else
    print_error "Échec création environnement virtuel"
fi

source "$RAG_ENV/bin/activate"

print_info "Vérification pip..."
if ! python -m pip --version >/dev/null 2>&1; then
    python -m ensurepip --upgrade
fi

print_info "Mise à jour pip..."
python -m pip install --upgrade pip setuptools wheel --quiet

print_success "Pip configuré: $(pip --version)"

# ============================================
# INSTALLATION PACKAGES PYTHON
# ============================================

echo ""
print_step "Installation des packages Python"

print_info "Phase 1: Packages de base (2-3 min)"

# IMPORTANT: Installation dans le bon ordre, sans langchain-ollama
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
    "flask-cors==5.0.0"
    "flask-socketio==5.4.1"
    "requests==2.32.3"
)

for pkg in "${BASE_PACKAGES[@]}"; do
    echo -ne "${BLUE}[→]${NC} Installation $pkg..."
    if pip install "$pkg" --quiet 2>&1; then
        echo -e "\r${GREEN}[✓]${NC} Installation $pkg"
    else
        echo -e "\r${RED}[✗]${NC} Échec $pkg"
    fi
done

print_info "Phase 2: Installation FAISS"

echo -ne "${BLUE}[→]${NC} Installation faiss-cpu..."
if pip install faiss-cpu --quiet 2>&1; then
    echo -e "\r${GREEN}[✓]${NC} Installation faiss-cpu"
else
    echo -e "\r${YELLOW}[!]${NC} Tentative version stable..."
    if pip install faiss-cpu==1.8.0 --quiet 2>&1; then
        echo -e "${GREEN}[✓]${NC} Installation faiss-cpu==1.8.0"
    else
        print_error "Échec installation FAISS"
    fi
fi

print_success "Packages Python installés"

# ============================================
# VÉRIFICATION IMPORTS
# ============================================

echo ""
print_step "Vérification des imports critiques"

python << 'EOFTEST'
import sys
errors = []

try:
    from langchain_community.embeddings import OllamaEmbeddings
    from langchain_community.llms import Ollama
    from langchain_community.vectorstores import FAISS
    from langchain.chains import RetrievalQA
    print("✓ LangChain imports OK (anciennes classes)")
except Exception as e:
    errors.append(f"LangChain: {e}")
    print(f"✗ LangChain: {e}")

try:
    import faiss
    print("✓ FAISS import OK")
except Exception as e:
    errors.append(f"FAISS: {e}")
    print(f"✗ FAISS: {e}")

try:
    from flask import Flask
    from flask_cors import CORS
    print("✓ Flask + CORS imports OK")
except Exception as e:
    errors.append(f"Flask: {e}")
    print(f"✗ Flask: {e}")

if errors:
    print("\n⚠️  Erreurs détectées:")
    for error in errors:
        print(f"  - {error}")
    sys.exit(1)
EOFTEST

if [[ $? -eq 0 ]]; then
    print_success "Tous les imports critiques validés ✓"
else
    print_error "Erreurs d'imports détectées"
fi

# ============================================
# CRÉATION SCRIPT RAG
# ============================================

echo ""
print_step "Création du script RAG"

RAG_SCRIPT="$HOME/rag.py"

cat > "$RAG_SCRIPT" << 'EOFRAG'
#!/usr/bin/env python3
"""
RAG Personnel - Script principal
Version STABLE avec anciennes classes LangChain
"""

import os
import sys
from pathlib import Path
from typing import List
import warnings

warnings.filterwarnings('ignore')

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
OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://172.16.113.131:11434")
EMBED_MODEL = os.getenv("EMBED_MODEL", "nomic-embed-text")
LLM_MODEL = os.getenv("LLM_MODEL", "mistral:latest")
RAG_DIR = Path(os.getenv("RAG_DIR", Path.home() / "RAG"))
FAISS_DB = Path(os.getenv("FAISS_DB", Path.home() / "faiss_index"))

LOADERS = {
    ".txt": TextLoader, ".md": TextLoader, ".pdf": PyPDFLoader,
    ".docx": Docx2txtLoader, ".odt": UnstructuredODTLoader,
    ".html": UnstructuredHTMLLoader, ".htm": UnstructuredHTMLLoader,
    ".eml": UnstructuredEmailLoader, ".epub": UnstructuredEPubLoader,
}

def load_documents(directory: Path) -> List:
    docs = []
    print(f"\n📂 Scan: {directory}")
    file_count = 0
    for file_path in directory.rglob("*"):
        if file_path.is_file() and file_path.suffix.lower() in LOADERS:
            file_count += 1
            try:
                loader_class = LOADERS[file_path.suffix.lower()]
                loader = loader_class(str(file_path))
                loaded = loader.load()
                docs.extend(loaded)
                print(f"✓ {file_path.name} ({len(loaded)} doc(s))")
            except Exception as e:
                print(f"✗ {file_path.name}: {e}")
    print(f"\n📊 Total: {file_count} fichier(s)")
    return docs

def index_documents():
    print(f"\n╔═══════════════════════════════════════╗")
    print(f"║     INDEXATION - RAG PERSONNEL        ║")
    print(f"╚═══════════════════════════════════════╝")
    print(f"\n🗂️  Source: {RAG_DIR}")
    print(f"💾 Destination: {FAISS_DB}")
    
    if not RAG_DIR.exists():
        print(f"\n✗ Dossier inexistant: {RAG_DIR}")
        sys.exit(1)
    
    print("\n⏳ Chargement documents...")
    docs = load_documents(RAG_DIR)
    
    if not docs:
        print("\n✗ Aucun document trouvé")
        sys.exit(1)
    
    print(f"\n✓ {len(docs)} document(s) chargé(s)")
    
    print("\n✂️  Découpage en chunks...")
    splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200)
    chunks = splitter.split_documents(docs)
    print(f"✓ {len(chunks)} chunks créés")
    
    print(f"\n🧠 Génération embeddings via {OLLAMA_HOST}...")
    print(f"   Modèle: {EMBED_MODEL}")
    
    try:
        embeddings = OllamaEmbeddings(model=EMBED_MODEL, base_url=OLLAMA_HOST)
        test_embed = embeddings.embed_query("test")
        print(f"   ✓ Test OK (dim: {len(test_embed)})")
    except Exception as e:
        print(f"\n✗ Erreur Ollama: {e}")
        sys.exit(1)
    
    print("\n📊 Création index FAISS...")
    vectorstore = FAISS.from_documents(chunks, embeddings)
    
    FAISS_DB.mkdir(parents=True, exist_ok=True)
    vectorstore.save_local(str(FAISS_DB))
    
    import subprocess
    size = subprocess.check_output(['du', '-sh', str(FAISS_DB)]).split()[0].decode()
    
    print(f"\n✓ Index sauvegardé: {FAISS_DB}")
    print(f"  Taille: {size}, Chunks: {len(chunks)}")

def query_documents(question: str):
    if not FAISS_DB.exists():
        print("\n✗ Index inexistant. Lancez: rag.py index")
        sys.exit(1)
    
    print(f"\n╔═══════════════════════════════════════╗")
    print(f"║          REQUÊTE - RAG PERSONNEL      ║")
    print(f"╚═══════════════════════════════════════╝")
    print(f"\n❓ Question: {question}")
    
    print("\n⏳ Chargement index...")
    embeddings = OllamaEmbeddings(model=EMBED_MODEL, base_url=OLLAMA_HOST)
    vectorstore = FAISS.load_local(str(FAISS_DB), embeddings, allow_dangerous_deserialization=True)
    print("✓ Index chargé")
    
    print(f"🤖 Connexion LLM: {LLM_MODEL}")
    llm = Ollama(model=LLM_MODEL, base_url=OLLAMA_HOST, temperature=0.3)
    
    qa_chain = RetrievalQA.from_chain_type(
        llm=llm,
        retriever=vectorstore.as_retriever(search_kwargs={"k": 3}),
        return_source_documents=True
    )
    
    print("\n⏳ Traitement...")
    result = qa_chain.invoke({"query": question})
    
    print("\n" + "="*60)
    print("💬 RÉPONSE:")
    print("="*60)
    print(result["result"])
    print("\n" + "="*60)
    print("📚 SOURCES:")
    print("="*60)
    
    for i, doc in enumerate(result["source_documents"], 1):
        source = Path(doc.metadata.get("source", "N/A")).name
        content = doc.page_content.replace("\n", " ")[:200] + "..."
        print(f"\n[{i}] {source}")
        print(f"    {content}")
    
    print("\n" + "="*60)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("\n╔═══════════════════════════════════════╗")
        print("║       RAG PERSONNEL - USAGE           ║")
        print("╚═══════════════════════════════════════╝\n")
        print("Usage:")
        print("  python rag.py index")
        print("  python rag.py query 'question'")
        print(f"\nConfig: Ollama={OLLAMA_HOST}, Docs={RAG_DIR}")
        sys.exit(1)
    
    cmd = sys.argv[1]
    if cmd == "index":
        index_documents()
    elif cmd == "query":
        if len(sys.argv) < 3:
            print("\n✗ Question manquante")
            sys.exit(1)
        query_documents(" ".join(sys.argv[2:]))
    else:
        print(f"\n✗ Commande inconnue: {cmd}")
        sys.exit(1)
EOFRAG

chmod +x "$RAG_SCRIPT"
print_success "Script RAG créé"

# ============================================
# CRÉATION WRAPPER CLI
# ============================================

print_step "Création du wrapper CLI"

cat > "$RAG_ENV/bin/rag" << EOFWRAPPER
#!/bin/bash
source "$RAG_ENV/bin/activate"
export OLLAMA_HOST="$OLLAMA_HOST"
export RAG_DIR="$MOUNT_POINT"
export FAISS_DB="$FAISS_DB"
export EMBED_MODEL="$EMBED_MODEL"
export LLM_MODEL="$LLM_MODEL"
python "$HOME/rag.py" "\$@"
EOFWRAPPER

chmod +x "$RAG_ENV/bin/rag"
print_success "Wrapper CLI créé"

# ============================================
# CRÉATION WEBUI
# ============================================

echo ""
print_step "Création de la WebUI Flask"

WEBUI_SCRIPT="$HOME/rag_webui.py"

cat > "$WEBUI_SCRIPT" << 'EOFWEBUI'
#!/usr/bin/env python3
"""RAG Personnel - Interface Web Flask"""

from flask import Flask, render_template_string, request, jsonify
from flask_cors import CORS
import subprocess
import os
import socket
from pathlib import Path
import warnings

warnings.filterwarnings('ignore')

app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}})

OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://172.16.113.131:11434")
RAG_DIR = Path(os.getenv("RAG_DIR", Path.home() / "RAG"))
FAISS_DB = Path(os.getenv("FAISS_DB", Path.home() / "faiss_index"))

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="fr">
<head>
    <title>RAG Personnel</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', system-ui, sans-serif;
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
        .header h1 { font-size: 2.5em; margin-bottom: 10px; }
        .badge {
            background: rgba(255,255,255,0.2);
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.8em;
            margin-top: 10px;
            display: inline-block;
        }
        .content { padding: 30px; }
        .info-box {
            background: #e3f2fd;
            padding: 15px;
            border-radius: 10px;
            margin-bottom: 20px;
            border-left: 4px solid #2196f3;
        }
        .status {
            display: inline-block;
            width: 10px;
            height: 10px;
            border-radius: 50%;
            margin-right: 8px;
        }
        .status.online { background: #4caf50; }
        .status.offline { background: #f44336; }
        .query-box h2 { color: #667eea; margin-bottom: 15px; }
        textarea {
            width: 100%;
            padding: 15px;
            border: 2px solid #667eea;
            border-radius: 10px;
            font-size: 16px;
            resize: vertical;
            min-height: 120px;
        }
        textarea:focus {
            outline: none;
            border-color: #764ba2;
            box-shadow: 0 0 0 3px rgba(118, 75, 162, 0.1);
        }
        .button-group {
            display: flex;
            gap: 10px;
            margin-top: 15px;
        }
        button {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 15px 40px;
            border-radius: 10px;
            font-size: 16px;
            cursor: pointer;
            flex: 1;
        }
        button:hover { opacity: 0.9; transform: translateY(-2px); }
        button:disabled { opacity: 0.5; cursor: not-allowed; }
        .loading {
            text-align: center;
            padding: 30px;
            display: none;
        }
        .loading-spinner {
            border: 4px solid #f3f3f3;
            border-top: 4px solid #667eea;
            border-radius: 50%;
            width: 50px;
            height: 50px;
            animation: spin 1s linear infinite;
            margin: 0 auto 15px;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        .response {
            margin-top: 20px;
            padding: 25px;
            background: #f8f9fa;
            border-radius: 10px;
            border-left: 4px solid #667eea;
            display: none;
        }
        .response h3 { color: #667eea; margin-bottom: 15px; }
        .response-text { line-height: 1.8; white-space: pre-wrap; }
        .error {
            color: #f44336;
            background: #ffebee;
            padding: 15px;
            border-radius: 5px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📚 Family RAG</h1>
            <p>Bibliothèque documentaire intelligente</p>
            <div class="badge">Linux + Ollama Distant</div>
        </div>
        <div class="content">
            <div class="info-box">
                <p><span class="status online"></span><strong>🤖 Ollama:</strong> {{ ollama_host }}</p>
                <p><span class="status {{ 'online' if index_exists else 'offline' }}"></span><strong>💾 Index:</strong> {{ 'Créé ✓' if index_exists else 'Non créé' }}</p>
            </div>
            
            <div class="query-box">
                <h2>💬 Posez votre question</h2>
                <textarea id="question" placeholder="Ex: Quelles sont les informations sur..."></textarea>
                <div class="button-group">
                    <button onclick="askQuestion()" id="btnQuery">🔍 Interroger</button>
                    <button onclick="indexDocuments()" id="btnIndex">🔄 Réindexer</button>
                </div>
            </div>
            
            <div class="loading" id="loading">
                <div class="loading-spinner"></div>
                <p id="loadingText">⏳ Traitement...</p>
            </div>
            
            <div class="response" id="response">
                <h3>💬 Réponse:</h3>
                <div class="response-text" id="responseText"></div>
            </div>
        </div>
    </div>
    
    <script>
        function setLoading(isLoading, msg) {
            document.getElementById('loading').style.display = isLoading ? 'block' : 'none';
            document.getElementById('response').style.display = 'none';
            document.getElementById('loadingText').textContent = msg || '⏳ Traitement...';
            document.getElementById('btnQuery').disabled = isLoading;
            document.getElementById('btnIndex').disabled = isLoading;
        }
        
        async function askQuestion() {
            const question = document.getElementById('question').value.trim();
            if (!question) { alert('⚠️ Veuillez saisir une question'); return; }
            
            setLoading(true, '⏳ Recherche...');
            
            try {
                const res = await fetch('/query', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({question})
                });
                
                const data = await res.json();
                
                setLoading(false);
                document.getElementById('response').style.display = 'block';
                
                if (data.answer) {
                    document.getElementById('responseText').innerHTML = data.answer.replace(/\\n/g, '<br>');
                } else {
                    document.getElementById('responseText').innerHTML = '<div class="error">❌ ' + (data.error || 'Erreur') + '</div>';
                }
            } catch (error) {
                setLoading(false);
                document.getElementById('response').style.display = 'block';
                document.getElementById('responseText').innerHTML = '<div class="error">❌ Erreur: ' + error.message + '</div>';
            }
        }
        
        async function indexDocuments() {
            if (!confirm('🔄 Réindexer tous les documents ?')) return;
            
            setLoading(true, '⏳ Indexation...');
            
            try {
                const res = await fetch('/index', {method: 'POST'});
                const data = await res.json();
                
                setLoading(false);
                alert(data.message || data.error || 'Terminé');
                if (data.message) location.reload();
            } catch (error) {
                setLoading(false);
                alert('❌ Erreur: ' + error.message);
            }
        }
        
        document.getElementById('question').addEventListener('keydown', function(e) {
            if (e.ctrlKey && e.key === 'Enter') askQuestion();
        });
    </script>
</body>
</html>
"""

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE, ollama_host=OLLAMA_HOST, index_exists=FAISS_DB.exists())

@app.route('/query', methods=['POST'])
def query():
    data = request.json
    question = data.get('question', '').strip()
    
    if not question:
        return jsonify({"error": "Question vide"}), 400
    
    if not FAISS_DB.exists():
        return jsonify({"error": "Index non créé"}), 400
    
    try:
        result = subprocess.run(
            [f"{Path.home()}/rag_env/bin/rag", "query", question],
            capture_output=True, text=True, timeout=180
        )
        
        output = result.stdout
        if "RÉPONSE:" in output and "SOURCES:" in output:
            answer = output.split("RÉPONSE:")[1].split("SOURCES:")[0].replace("="*60, "").strip()
            return jsonify({"answer": answer})
        return jsonify({"error": "Format inattendu"}), 500
    except subprocess.TimeoutExpired:
        return jsonify({"error": "Timeout"}), 504
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/index', methods=['POST'])
def index_docs():
    try:
        result = subprocess.run(
            [f"{Path.home()}/rag_env/bin/rag", "index"],
            capture_output=True, text=True, timeout=600
        )
        if result.returncode == 0:
            return jsonify({"message": "✓ Indexation terminée"})
        return jsonify({"error": result.stderr or "Erreur"}), 500
    except subprocess.TimeoutExpired:
        return jsonify({"error": "Timeout"}), 504
    except Exception as e:
        return jsonify({"error": str(e)}), 500

def get_local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
    except:
        ip = '127.0.0.1'
    finally:
        s.close()
    return ip

if __name__ == '__main__':
    ip = get_local_ip()
    
    print(f"""
╔═══════════════════════════════════════════════╗
║          RAG PERSONNEL - WEBUI                ║
╚═══════════════════════════════════════════════╝

🌐 Accès local   : http://127.0.0.1:5000
🌐 Accès réseau  : http://{ip}:5000
🤖 Ollama        : {OLLAMA_HOST}
🗂️  Documents     : {RAG_DIR}
💾 Index FAISS   : {FAISS_DB}
{'✓ Index existe' if FAISS_DB.exists() else '⚠️  Index à créer'}

Appuyez sur Ctrl+C pour arrêter
""")
    
    app.run(host='0.0.0.0', port=5000, debug=False)
EOFWEBUI

chmod +x "$WEBUI_SCRIPT"
print_success "WebUI créée"

# ============================================
# CONFIGURATION FIREWALL
# ============================================

echo ""
print_step "Configuration du pare-feu"

if systemctl is-active --quiet firewalld; then
    sudo firewall-cmd --permanent --add-port=5000/tcp
    sudo firewall-cmd --reload
    print_success "Port 5000 ouvert"
elif command -v ufw &>/dev/null; then
    sudo ufw allow 5000/tcp
    print_success "Port 5000 ouvert (UFW)"
else
    print_info "Firewall non détecté (OK si désactivé)"
fi

# ============================================
# RÉSUMÉ FINAL
# ============================================

echo ""
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════╗
║       INSTALLATION TERMINÉE AVEC SUCCÈS      ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo ""
echo "✅ Configuration complète:"
echo ""
echo "🖥️  Système        : $(cat /etc/*release | grep PRETTY_NAME | cut -d'"' -f2 2>/dev/null || echo 'Linux')"
echo "🏠 IP Fedora      : $FEDORA_IP"
echo "🔗 IP Windows     : $WINDOWS_IP"
echo "🤖 Ollama URL     : $OLLAMA_HOST"
echo "🗂️  Montage SMB    : $MOUNT_POINT"
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo "                   [✓ Monté]"
fi
echo "💾 Index FAISS    : $FAISS_DB"
echo "🌐 WebUI          : http://$FEDORA_IP:5000"
echo ""
echo "📝 Prochaines étapes:"
echo ""
echo "   1️⃣  Indexer documents:"
echo "      source ~/rag_env/bin/activate"
echo "      ~/rag_env/bin/rag index"
echo ""
echo "   2️⃣  Test requête:"
echo "      ~/rag_env/bin/rag query 'Votre question'"
echo ""
echo "   3️⃣  Lancer WebUI:"
echo "      python ~/rag_webui.py"
echo ""
echo -e "${CYAN}📄 Configuration:${NC} $CONFIG_FILE"
echo ""
print_success "Setup Linux terminé!"
