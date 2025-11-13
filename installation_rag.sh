#!/bin/bash
#
# Script de déploiement RAG Familial sur VM Fedora
# Automatise la configuration complète du système
#

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Banner
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════╗
║                                               ║
║         RAG FAMILIAL - DÉPLOIEMENT           ║
║              Installation VM                  ║
║                                               ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# ============================================
# VÉRIFICATION SYSTÈME
# ============================================

print_step "Vérification du système"

if [[ "$(uname)" != "Darwin" ]]; then
    print_error "Ce script doit être exécuté depuis le Mac"
    exit 1
fi

print_success "Exécution depuis le Mac"

# ============================================
# CHARGEMENT CONFIGURATIONS EXISTANTES
# ============================================

print_step "Chargement des configurations"

NETWORK_CONFIG="$HOME/.rag_network_config"
VM_CONFIG="$HOME/.rag_vm_config"
SSH_CONFIG="$HOME/.rag_ssh_config"
OLLAMA_CONFIG="$HOME/.rag_ollama_config"

CONFIGS_LOADED=0

if [[ -f "$NETWORK_CONFIG" ]]; then
    source "$NETWORK_CONFIG"
    print_success "✓ Configuration réseau chargée"
    CONFIGS_LOADED=$((CONFIGS_LOADED + 1))
else
    print_warning "✗ Configuration réseau manquante"
fi

if [[ -f "$VM_CONFIG" ]]; then
    source "$VM_CONFIG"
    print_success "✓ Configuration VM chargée"
    CONFIGS_LOADED=$((CONFIGS_LOADED + 1))
else
    print_warning "✗ Configuration VM manquante"
fi

if [[ -f "$SSH_CONFIG" ]]; then
    source "$SSH_CONFIG"
    print_success "✓ Configuration SSH chargée"
    CONFIGS_LOADED=$((CONFIGS_LOADED + 1))
else
    print_warning "✗ Configuration SSH manquante"
fi

if [[ -f "$OLLAMA_CONFIG" ]]; then
    source "$OLLAMA_CONFIG"
    print_success "✓ Configuration Ollama chargée"
    CONFIGS_LOADED=$((CONFIGS_LOADED + 1))
else
    print_warning "✗ Configuration Ollama manquante"
fi

if [[ $CONFIGS_LOADED -lt 3 ]]; then
    echo ""
    print_error "Configurations insuffisantes pour le déploiement"
    echo ""
    echo "Exécuter d'abord les scripts de configuration :"
    echo "  1. ./setup_network_mac.sh"
    echo "  2. ./setup_vm_fedora.sh"
    echo "  3. ./setup_ssh.sh"
    echo "  4. ./setup_ollama.sh"
    exit 1
fi

echo ""

# ============================================
# COLLECTE INFORMATIONS MANQUANTES
# ============================================

print_step "Configuration du déploiement RAG"
echo ""

# VM Target
if [[ -z "$VM_HOSTNAME" ]]; then
    read -p "Hostname/Alias SSH de la VM (ex: playground): " VM_HOSTNAME
fi

# Vérifier connexion SSH
print_step "Vérification de la connexion SSH vers $VM_HOSTNAME"

if ! ssh -o BatchMode=yes -o ConnectTimeout=5 $VM_HOSTNAME exit 2>/dev/null; then
    print_error "Impossible de se connecter à $VM_HOSTNAME via SSH"
    echo "Vérifier :"
    echo "  1. La VM est démarrée"
    echo "  2. SSH est configuré: ./setup_ssh.sh"
    echo "  3. Tester: ssh $VM_HOSTNAME"
    exit 1
fi

print_success "Connexion SSH fonctionnelle"

# IP Mac
if [[ -z "$HOST_IP" ]]; then
    read -p "IP du Mac sur le réseau privé (ex: 172.16.74.1): " HOST_IP
fi

# Utilisateur Mac
MAC_USER=$(whoami)

# Dossier RAG source sur Mac
echo ""
read -p "Dossier source RAG sur le Mac (défaut: ~/Documents/RAG): " RAG_SOURCE_DIR
RAG_SOURCE_DIR=${RAG_SOURCE_DIR:-"$HOME/Documents/RAG"}

# Vérifier si le dossier existe
if [[ ! -d "$RAG_SOURCE_DIR" ]]; then
    print_warning "Le dossier $RAG_SOURCE_DIR n'existe pas"
    read -p "Créer le dossier maintenant ? (y/n): " CREATE_DIR
    
    if [[ $CREATE_DIR =~ ^[Yy]$ ]]; then
        mkdir -p "$RAG_SOURCE_DIR"
        print_success "Dossier créé: $RAG_SOURCE_DIR"
        
        # Créer un fichier de test
        cat > "$RAG_SOURCE_DIR/README.md" << EOF
# RAG Familial - Bibliothèque documentaire

Ce dossier contient les documents de la bibliothèque familiale.

## Formats supportés
- Texte: .txt, .md
- PDF: .pdf
- Word: .docx
- LibreOffice: .odt
- Web: .html, .htm
- Ebook: .epub
- Email: .eml

## Utilisation
1. Placer les documents dans ce dossier (ou sous-dossiers)
2. Sur la VM, lancer: rag index
3. Interroger: rag query "Votre question"

Créé le $(date)
EOF
        print_success "Fichier README.md créé"
    else
        print_error "Le dossier source est requis pour continuer"
        exit 1
    fi
fi

# Modèles Ollama
if [[ -z "$EMBED_MODEL" ]]; then
    read -p "Modèle d'embeddings (défaut: nomic-embed-text:latest): " EMBED_MODEL
    EMBED_MODEL=${EMBED_MODEL:-nomic-embed-text:latest}
fi

if [[ -z "$LLM_MODEL" ]]; then
    read -p "Modèle LLM (défaut: mistral:latest): " LLM_MODEL
    LLM_MODEL=${LLM_MODEL:-mistral:latest}
fi

# URL Ollama
if [[ -z "$OLLAMA_URL" ]]; then
    OLLAMA_URL="http://$HOST_IP:11434"
fi

# ============================================
# RÉCAPITULATIF
# ============================================

echo ""
print_step "Récapitulatif de la configuration"
echo "════════════════════════════════════════════"
echo "Mac (Hôte):"
echo "  - Utilisateur  : $MAC_USER"
echo "  - IP           : $HOST_IP"
echo "  - Dossier RAG  : $RAG_SOURCE_DIR"
echo ""
echo "VM (Fedora):"
echo "  - Hostname     : $VM_HOSTNAME"
echo "  - Utilisateur  : $VM_USER"
echo "  - Point montage: ~/RAG"
echo ""
echo "Ollama:"
echo "  - URL          : $OLLAMA_URL"
echo "  - Embeddings   : $EMBED_MODEL"
echo "  - LLM          : $LLM_MODEL"
echo ""
echo "Configuration:"
echo "  - Base FAISS   : ~/rag_system/faiss_db"
echo "  - Script RAG   : ~/rag.py"
echo "  - Env Python   : ~/rag_env"
echo "════════════════════════════════════════════"
echo ""
read -p "Démarrer le déploiement ? (y/n): " CONFIRM
[[ ! $CONFIRM =~ ^[Yy]$ ]] && { print_error "Déploiement annulé"; exit 1; }

# ============================================
# TEST CONNECTIVITÉ OLLAMA DEPUIS MAC
# ============================================

echo ""
print_step "Test de connectivité Ollama depuis le Mac"

if curl -s --connect-timeout 5 $OLLAMA_URL/api/tags > /dev/null 2>&1; then
    print_success "Ollama accessible depuis le Mac ($OLLAMA_URL)"
else
    print_error "Ollama non accessible depuis le Mac"
    echo "Vérifier :"
    echo "  1. Ollama est démarré: ./setup_ollama.sh"
    echo "  2. Service actif: launchctl list | grep ollama"
    echo "  3. Test: curl $OLLAMA_URL/api/tags"
    exit 1
fi

# ============================================
# PRÉPARATION SCRIPT DE DÉPLOIEMENT VM
# ============================================

print_step "Génération du script de déploiement pour la VM"

DEPLOY_SCRIPT=$(cat << 'EOFSCRIPT'
#!/bin/bash
set -e

# Variables injectées
HOST_IP="{{HOST_IP}}"
MAC_USER="{{MAC_USER}}"
RAG_SOURCE_DIR="{{RAG_SOURCE_DIR}}"
OLLAMA_URL="{{OLLAMA_URL}}"
EMBED_MODEL="{{EMBED_MODEL}}"
LLM_MODEL="{{LLM_MODEL}}"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

echo "════════════════════════════════════════════"
echo "  RAG FAMILIAL - DÉPLOIEMENT SUR VM"
echo "════════════════════════════════════════════"
echo ""

# ============================================
# INSTALLATION DÉPENDANCES SYSTÈME
# ============================================

print_step "Installation des dépendances système"

sudo dnf install -y \
    python3 \
    python3-pip \
    python3-devel \
    gcc \
    gcc-c++ \
    make \
    fuse-sshfs \
    file-libs \
    git \
    curl

print_success "Dépendances système installées"

# ============================================
# CONFIGURATION SSH (VÉRIFICATION)
# ============================================

print_step "Vérification de l'authentification SSH Mac → VM"

if [[ ! -f ~/.ssh/authorized_keys ]] || ! grep -q "mac-rag" ~/.ssh/authorized_keys 2>/dev/null; then
    print_warning "Clé SSH Mac non trouvée dans authorized_keys"
    echo "La configuration SSH sera à finaliser manuellement"
fi

# ============================================
# MONTAGE SSHFS
# ============================================

print_step "Configuration du montage SSHFS"

mkdir -p ~/RAG

# Vérifier si déjà monté
if mountpoint -q ~/RAG 2>/dev/null; then
    print_warning "~/RAG déjà monté, démontage..."
    fusermount -u ~/RAG 2>/dev/null || true
fi

# Test connexion SSH vers Mac
print_step "Test connexion SSH vers le Mac..."
if ssh -o BatchMode=yes -o ConnectTimeout=5 $MAC_USER@$HOST_IP exit 2>/dev/null; then
    print_success "Connexion SSH vers le Mac OK"
else
    print_error "Impossible de se connecter au Mac via SSH"
    echo "Configuration SSH bidirectionnelle requise"
    exit 1
fi

# Montage SSHFS
print_step "Montage SSHFS: $RAG_SOURCE_DIR → ~/RAG"

if sshfs $MAC_USER@$HOST_IP:$RAG_SOURCE_DIR ~/RAG -o follow_symlinks,allow_other 2>/dev/null; then
    print_success "SSHFS monté avec succès"
else
    print_warning "Montage SSHFS échoué, tentative sans allow_other..."
    if sshfs $MAC_USER@$HOST_IP:$RAG_SOURCE_DIR ~/RAG -o follow_symlinks; then
        print_success "SSHFS monté (sans allow_other)"
    else
        print_error "Impossible de monter SSHFS"
        exit 1
    fi
fi

# Vérifier le contenu
echo ""
echo "Contenu de ~/RAG:"
ls -lah ~/RAG | head -10

# ============================================
# ENVIRONNEMENT PYTHON
# ============================================

print_step "Création de l'environnement virtuel Python"

# Supprimer ancien si existe
if [[ -d ~/rag_env ]]; then
    print_warning "Environnement existant, suppression..."
    rm -rf ~/rag_env
fi

python3 -m venv ~/rag_env
source ~/rag_env/bin/activate

print_success "Environnement virtuel créé"

# ============================================
# INSTALLATION PACKAGES PYTHON
# ============================================

print_step "Mise à jour de pip"
pip install --upgrade pip --quiet

print_step "Installation des packages RAG (peut prendre 5-10 minutes)..."

# Core RAG
pip install --no-cache-dir \
    langchain \
    langchain-community \
    langchain-text-splitters \
    langchain-ollama \
    faiss-cpu \
    ollama \
    pydantic-settings

print_success "Packages RAG installés"

# Parsers de documents
print_step "Installation des parsers de documents..."

pip install --no-cache-dir \
    pypdf \
    python-docx \
    odfpy \
    beautifulsoup4 \
    lxml \
    ebooklib \
    python-magic

print_success "Parsers installés"

# Vérification
print_step "Vérification des imports..."
python3 << 'EOFPY'
try:
    import langchain
    import faiss
    import ollama
    from langchain_ollama import OllamaEmbeddings, OllamaLLM
    print("✓ Tous les imports OK")
except ImportError as e:
    print(f"✗ Erreur import: {e}")
    exit(1)
EOFPY

print_success "Environnement Python validé"

# ============================================
# TEST CONNECTIVITÉ OLLAMA
# ============================================

print_step "Test de connectivité vers Ollama"

if curl -s --connect-timeout 5 $OLLAMA_URL/api/tags > /dev/null 2>&1; then
    print_success "Ollama accessible: $OLLAMA_URL"
    
    # Vérifier les modèles
    MODELS=$(curl -s $OLLAMA_URL/api/tags | python3 -c "import sys,json; print(','.join([m['name'] for m in json.load(sys.stdin)['models']]))" 2>/dev/null || echo "")
    
    if [[ "$MODELS" == *"$EMBED_MODEL"* ]] && [[ "$MODELS" == *"$LLM_MODEL"* ]]; then
        print_success "Modèles requis présents: $EMBED_MODEL, $LLM_MODEL"
    else
        print_warning "Modèles manquants détectés"
        echo "Modèles disponibles: $MODELS"
        echo "Modèles requis: $EMBED_MODEL, $LLM_MODEL"
    fi
else
    print_error "Impossible de contacter Ollama"
    echo "Vérifier la configuration Ollama sur le Mac"
    exit 1
fi

# ============================================
# CRÉATION SCRIPT RAG
# ============================================

print_step "Création du script RAG"

cat > ~/rag.py << 'EOFRAG'
#!/usr/bin/env python3
"""
RAG Familial - Système de Retrieval Augmented Generation
Supporte : .txt, .md, .pdf, .docx, .odt, .html, .epub, .eml
Version FAISS (compatible Python 3.14+)
"""

import os
import sys
from pathlib import Path
from typing import List
import argparse

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
OLLAMA_HOST = "{{OLLAMA_URL}}"
EMBED_MODEL = "{{EMBED_MODEL}}"
LLM_MODEL = "{{LLM_MODEL}}"
RAG_DIR = Path.home() / "RAG"
FAISS_DB = Path.home() / "rag_system" / "faiss_db"


class DocumentLoader:
    """Charge et parse différents formats de documents"""
    
    @staticmethod
    def load_txt(file_path: Path) -> str:
        """Charge fichiers texte brut"""
        return file_path.read_text(encoding='utf-8', errors='ignore')
    
    @staticmethod
    def load_pdf(file_path: Path) -> str:
        """Charge fichiers PDF"""
        text = []
        with open(file_path, 'rb') as f:
            pdf_reader = pypdf.PdfReader(f)
            for page in pdf_reader.pages:
                text.append(page.extract_text())
        return "\n".join(text)
    
    @staticmethod
    def load_docx(file_path: Path) -> str:
        """Charge fichiers Word .docx"""
        doc = DocxDocument(file_path)
        return "\n".join([para.text for para in doc.paragraphs])
    
    @staticmethod
    def load_odt(file_path: Path) -> str:
        """Charge fichiers LibreOffice .odt"""
        doc = odf_load(file_path)
        paragraphs = doc.getElementsByType(odf_text.P)
        return "\n".join([teletype.extractText(p) for p in paragraphs])
    
    @staticmethod
    def load_html(file_path: Path) -> str:
        """Charge fichiers HTML"""
        html = file_path.read_text(encoding='utf-8', errors='ignore')
        soup = BeautifulSoup(html, 'lxml')
        for script in soup(["script", "style"]):
            script.decompose()
        return soup.get_text(separator='\n', strip=True)
    
    @staticmethod
    def load_epub(file_path: Path) -> str:
        """Charge fichiers EPUB"""
        book = epub.read_epub(str(file_path))
        text = []
        for item in book.get_items():
            if item.get_type() == ebooklib.ITEM_DOCUMENT:
                soup = BeautifulSoup(item.get_content(), 'html.parser')
                text.append(soup.get_text())
        return "\n".join(text)
    
    @staticmethod
    def load_eml(file_path: Path) -> str:
        """Charge fichiers Email .eml"""
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


def scan_documents(directory: Path) -> List[dict]:
    """Scanne le répertoire RAG et retourne la liste des documents"""
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


def index_documents():
    """Indexe tous les documents du dossier RAG"""
    print(f"🔍 Scan du répertoire : {RAG_DIR}")
    
    if not RAG_DIR.exists():
        print(f"❌ Erreur : Le dossier {RAG_DIR} n'existe pas")
        return
    
    documents = scan_documents(RAG_DIR)
    print(f"📄 {len(documents)} documents trouvés")
    
    if not documents:
        print("⚠️  Aucun document à indexer")
        return
    
    all_texts = []
    all_metadatas = []
    
    for doc in documents:
        try:
            print(f"📖 Lecture : {doc['path'].name}")
            text = doc['loader'](doc['path'])
            
            text_splitter = RecursiveCharacterTextSplitter(
                chunk_size=1000,
                chunk_overlap=200,
                length_function=len,
            )
            chunks = text_splitter.split_text(text)
            
            for chunk in chunks:
                all_texts.append(chunk)
                all_metadatas.append({
                    'source': str(doc['path']),
                    'filename': doc['path'].name,
                    'extension': doc['extension']
                })
            
            print(f"  ✓ {len(chunks)} chunks créés")
            
        except Exception as e:
            print(f"  ✗ Erreur : {e}")
    
    print(f"\n🧠 Vectorisation avec {EMBED_MODEL}...")
    
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
    
    print(f"✅ Indexation terminée : {len(all_texts)} chunks stockés dans FAISS")


def query_rag(question: str, k: int = 5):
    """Interroge le système RAG"""
    
    if not FAISS_DB.exists():
        print("❌ Erreur : Base vectorielle non initialisée. Lance d'abord : rag index")
        return
    
    print(f"🔎 Question : {question}\n")
    
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
        print("❌ Aucun document pertinent trouvé")
        return
    
    context = "\n\n".join([doc.page_content for doc in results])
    
    llm = OllamaLLM(
        model=LLM_MODEL,
        base_url=OLLAMA_HOST
    )
    
    prompt = f"""Tu es un assistant familial. Réponds à la question en te basant UNIQUEMENT sur le contexte fourni.
Si l'information n'est pas dans le contexte, dis-le clairement.

Contexte :
{context}

Question : {question}

Réponse :"""
    
    print("💬 Réponse :\n")
    response = llm.invoke(prompt)
    print(response)
    
    print("\n📚 Sources utilisées :")
    for i, doc in enumerate(results, 1):
        print(f"  {i}. {doc.metadata['filename']}")


def main():
    parser = argparse.ArgumentParser(description='RAG Familial - Système de recherche documentaire')
    subparsers = parser.add_subparsers(dest='command', help='Commandes disponibles')
    
    subparsers.add_parser('index', help='Indexer tous les documents du dossier RAG')
    
    query_parser = subparsers.add_parser('query', help='Interroger le système RAG')
    query_parser.add_argument('question', type=str, help='Question à poser')
    query_parser.add_argument('-k', type=int, default=5, help='Nombre de documents à récupérer (défaut: 5)')
    
    args = parser.parse_args()
    
    if args.command == 'index':
        index_documents()
    elif args.command == 'query':
        query_rag(args.question, args.k)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
EOFRAG

# Remplacer les placeholders
sed -i "s|{{OLLAMA_URL}}|$OLLAMA_URL|g" ~/rag.py
sed -i "s|{{EMBED_MODEL}}|$EMBED_MODEL|g" ~/rag.py
sed -i "s|{{LLM_MODEL}}|$LLM_MODEL|g" ~/rag.py

chmod +x ~/rag.py

print_success "Script RAG créé: ~/rag.py"

# ============================================
# CONFIGURATION ALIAS
# ============================================

print_step "Configuration de l'alias 'rag'"

if ! grep -q "alias rag=" ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc << 'EOFALIAS'

# RAG Familial alias
alias rag="source ~/rag_env/bin/activate && python ~/rag.py"
EOFALIAS
    print_success "Alias 'rag' ajouté à ~/.bashrc"
else
    print_success "Alias 'rag' déjà configuré"
fi

# ============================================
# SAUVEGARDE CONFIGURATION
# ============================================

print_step "Sauvegarde de la configuration"

cat > ~/.rag_config << EOFCONFIG
# Configuration RAG Familial
# Générée le $(date)

HOST_IP=$HOST_IP
MAC_USER=$MAC_USER
RAG_SOURCE_DIR=$RAG_SOURCE_DIR
OLLAMA_URL=$OLLAMA_URL
EMBED_MODEL=$EMBED_MODEL
LLM_MODEL=$LLM_MODEL

# Chemins
RAG_MOUNT=~/RAG
RAG_SCRIPT=~/rag.py
RAG_ENV=~/rag_env
FAISS_DB=~/rag_system/faiss_db

# Commandes utiles
# Monter SSHFS       : sshfs $MAC_USER@$HOST_IP:$RAG_SOURCE_DIR ~/RAG
# Démonter SSHFS     : fusermount -u ~/RAG
# Activer env        : source ~/rag_env/bin/activate
# Indexer            : rag index
# Interroger         : rag query "Question"
EOFCONFIG

print_success "Configuration sauvegardée: ~/.rag_config"

# ============================================
# TEST FINAL
# ============================================

print_step "Test de l'installation"

# Activer l'environnement
source ~/rag_env/bin/activate

# Test import
python3 << 'EOFTEST'
import sys
try:
    from langchain_ollama import OllamaEmbeddings
    import faiss
    print("✓ Imports Python OK")
except Exception as e:
    print(f"✗ Erreur import: {e}")
    sys.exit(1)
EOFTEST

if [[ $? -eq 0 ]]; then
    print_success "Installation validée"
else
    print_error "Problème détecté dans l'installation"
    exit 1
fi

# ============================================
# RÉSUMÉ
# ============================================

echo ""
echo "════════════════════════════════════════════"
echo "  DÉPLOIEMENT RAG TERMINÉ AVEC SUCCÈS"
echo "════════════════════════════════════════════"
echo ""
echo "📁 Configuration:"
echo "   - Dossier RAG  : ~/RAG (monté via SSHFS)"
echo "   - Script       : ~/rag.py"
echo "   - Environnement: ~/rag_env"
echo "   - Base FAISS   : ~/rag_system/faiss_db"
echo ""
echo "🔧 Commandes:"
echo "   rag index                  # Indexer les documents"
echo "   rag query \"Question\"       # Interroger le système"
echo "   rag query \"Question\" -k 10  # Plus de contexte"
echo ""
echo "📝 Note: Redémarrer le shell ou sourcer ~/.bashrc pour l'alias"
echo "   source ~/.bashrc"
echo ""

EOFSCRIPT
)

# Remplacer les placeholders
DEPLOY_SCRIPT="${DEPLOY_SCRIPT//\{\{HOST_IP\}\}/$HOST_IP}"
DEPLOY_SCRIPT="${DEPLOY_SCRIPT//\{\{MAC_USER\}\}/$MAC_USER}"
DEPLOY_SCRIPT="${DEPLOY_SCRIPT//\{\{RAG_SOURCE_DIR\}\}/$RAG_SOURCE_DIR}"
DEPLOY_SCRIPT="${DEPLOY_SCRIPT//\{\{OLLAMA_URL\}\}/$OLLAMA_URL}"
DEPLOY_SCRIPT="${DEPLOY_SCRIPT//\{\{EMBED_MODEL\}\}/$EMBED_MODEL}"
DEPLOY_SCRIPT="${DEPLOY_SCRIPT//\{\{LLM_MODEL\}\}/$LLM_MODEL}"

# Sauvegarder le script temporairement
TEMP_SCRIPT=$(mktemp)
echo "$DEPLOY_SCRIPT" > "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

print_success "Script de déploiement généré"

# ============================================
# TRANSFERT ET EXÉCUTION SUR LA VM
# ============================================

echo ""
print_step "Transfert du script vers la VM"

if scp "$TEMP_SCRIPT" $VM_HOSTNAME:/tmp/rag_deploy.sh; then
    print_success "Script transféré vers la VM"
else
    print_error "Échec du transfert"
    rm "$TEMP_SCRIPT"
    exit 1
fi

rm "$TEMP_SCRIPT"

# ============================================
# EXÉCUTION DU DÉPLOIEMENT
# ============================================

echo ""
print_step "Exécution du déploiement sur la VM"
echo "Cette étape peut prendre 10-15 minutes (installation packages Python)..."
echo ""

if ssh $VM_HOSTNAME "bash /tmp/rag_deploy.sh"; then
    print_success "Déploiement sur la VM terminé"
else
    print_error "Échec du déploiement sur la VM"
    echo "Consulter les logs sur la VM pour plus de détails"
    exit 1
fi

# Nettoyer le script temporaire sur la VM
ssh $VM_HOSTNAME "rm /tmp/rag_deploy.sh" 2>/dev/null || true

# ============================================
# TESTS POST-DÉPLOIEMENT
# ============================================

echo ""
print_step "Tests post-déploiement"

# Test 1: Vérifier montage SSHFS
print_step "Test 1: Vérification montage SSHFS"
MOUNT_TEST=$(ssh $VM_HOSTNAME "mountpoint -q ~/RAG && echo 'MOUNTED' || echo 'NOT_MOUNTED'")

if [[ "$MOUNT_TEST" == "MOUNTED" ]]; then
    print_success "✓ SSHFS monté correctement"
else
    print_warning "✗ SSHFS non monté"
fi

# Test 2: Vérifier environnement Python
print_step "Test 2: Environnement Python"
PYTHON_TEST=$(ssh $VM_HOSTNAME "source ~/rag_env/bin/activate && python3 -c 'import langchain; import faiss; print(\"OK\")' 2>/dev/null")

if [[ "$PYTHON_TEST" == "OK" ]]; then
    print_success "✓ Environnement Python fonctionnel"
else
    print_warning "✗ Problème avec l'environnement Python"
fi

# Test 3: Vérifier script RAG
print_step "Test 3: Script RAG"
RAG_TEST=$(ssh $VM_HOSTNAME "[[ -f ~/rag.py ]] && echo 'EXISTS' || echo 'MISSING'")

if [[ "$RAG_TEST" == "EXISTS" ]]; then
    print_success "✓ Script RAG présent"
else
    print_error "✗ Script RAG manquant"
fi

# Test 4: Connectivité Ollama depuis VM
print_step "Test 4: Connectivité Ollama depuis VM"
OLLAMA_TEST=$(ssh $VM_HOSTNAME "curl -s --connect-timeout 5 $OLLAMA_URL/api/tags > /dev/null && echo 'OK' || echo 'FAILED'")

if [[ "$OLLAMA_TEST" == "OK" ]]; then
    print_success "✓ Ollama accessible depuis la VM"
else
    print_warning "✗ Ollama non accessible depuis la VM"
    echo "Vérifier le pare-feu et la configuration réseau"
fi

# ============================================
# CRÉATION FICHIER TEST
# ============================================

echo ""
read -p "Créer un document de test et indexer ? (y/n): " CREATE_TEST

if [[ $CREATE_TEST =~ ^[Yy]$ ]]; then
    print_step "Création d'un document de test"
    
    cat > "$RAG_SOURCE_DIR/test_rag.txt" << EOF
RAG Familial - Document de test

Ce document a été créé automatiquement pour tester le système RAG.

Date de création: $(date)
Utilisateur: $MAC_USER
Machine: $(hostname)

Le système RAG (Retrieval Augmented Generation) permet d'interroger
une bibliothèque de documents en langage naturel.

Fonctionnalités:
- Indexation automatique de 8 formats de documents
- Recherche sémantique par embeddings
- Réponses contextualisées par LLM
- Architecture hybride Mac/VM

Technologies utilisées:
- Ollama ($EMBED_MODEL et $LLM_MODEL)
- Langchain
- FAISS (vectorstore)
- Python 3.14+
EOF
    
    print_success "Document de test créé: $RAG_SOURCE_DIR/test_rag.txt"
    
    # Indexation
    print_step "Indexation des documents..."
    ssh $VM_HOSTNAME "source ~/rag_env/bin/activate && python ~/rag.py index"
    
    # Test query
    echo ""
    print_step "Test d'une requête..."
    ssh $VM_HOSTNAME "source ~/rag_env/bin/activate && python ~/rag.py query 'Quelles technologies sont utilisées dans le RAG ?'"
fi

# ============================================
# SAUVEGARDE CONFIGURATION FINALE
# ============================================

print_step "Sauvegarde de la configuration finale"

RAG_CONFIG_FILE="$HOME/.rag_deployment_config"

cat > "$RAG_CONFIG_FILE" << EOF
# Configuration Déploiement RAG Familial
# Générée le $(date)

# Mac (Hôte)
MAC_USER=$MAC_USER
HOST_IP=$HOST_IP
RAG_SOURCE_DIR=$RAG_SOURCE_DIR

# VM (Fedora)
VM_HOSTNAME=$VM_HOSTNAME
VM_USER=$VM_USER

# Ollama
OLLAMA_URL=$OLLAMA_URL
EMBED_MODEL=$EMBED_MODEL
LLM_MODEL=$LLM_MODEL

# Tests status
SSHFS_STATUS=$MOUNT_TEST
PYTHON_STATUS=$PYTHON_TEST
RAG_SCRIPT_STATUS=$RAG_TEST
OLLAMA_STATUS=$OLLAMA_TEST

# Commandes utiles depuis le Mac
# SSH vers VM        : ssh $VM_HOSTNAME
# Copier vers VM     : scp file.txt $VM_HOSTNAME:~/RAG/
# Indexer depuis Mac : ssh $VM_HOSTNAME 'source ~/rag_env/bin/activate && python ~/rag.py index'
# Query depuis Mac   : ssh $VM_HOSTNAME 'source ~/rag_env/bin/activate && python ~/rag.py query "Question"'
EOF

chmod 600 "$RAG_CONFIG_FILE"
print_success "Configuration finale: $RAG_CONFIG_FILE"

# ============================================
# RÉSUMÉ FINAL
# ============================================

echo ""
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════╗
║                                               ║
║       RAG FAMILIAL DÉPLOYÉ AVEC SUCCÈS       ║
║                                               ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo "📍 Architecture déployée:"
echo ""
echo "Mac (Hôte):"
echo "  - Ollama       : $OLLAMA_URL"
echo "  - Documents    : $RAG_SOURCE_DIR"
echo ""
echo "VM (Fedora):"
echo "  - Hostname     : $VM_HOSTNAME"
echo "  - RAG monté    : ~/RAG → $RAG_SOURCE_DIR"
echo "  - Script       : ~/rag.py"
echo "  - Base FAISS   : ~/rag_system/faiss_db"
echo ""
echo "📝 Statut des tests:"
echo "  - SSHFS        : $MOUNT_TEST"
echo "  - Python       : $PYTHON_TEST"
echo "  - Script RAG   : $RAG_TEST"
echo "  - Ollama       : $OLLAMA_TEST"
echo ""
echo -e "${YELLOW}Utilisation:${NC}"
echo ""
echo "Sur la VM:"
echo "  ssh $VM_HOSTNAME"
echo "  rag index                      # Indexer les documents"
echo "  rag query \"Votre question\"     # Interroger"
echo ""
echo "Depuis le Mac:"
echo "  # Ajouter documents"
echo "  cp documents/*.pdf $RAG_SOURCE_DIR/"
echo ""
echo "  # Indexer à distance"
echo "  ssh $VM_HOSTNAME 'rag index'"
echo ""
echo "  # Interroger à distance"
echo "  ssh $VM_HOSTNAME 'rag query \"Question\"'"
echo ""
echo -e "${YELLOW}Prochaines étapes suggérées:${NC}"
echo "  1. Ajouter vos documents dans: $RAG_SOURCE_DIR"
echo "  2. Sur la VM: rag index"
echo "  3. Tester: rag query \"Votre première question\""
echo "  4. Optionnel: Installer interface web (Flask)"
echo ""
print_success "Déploiement complet terminé!"
