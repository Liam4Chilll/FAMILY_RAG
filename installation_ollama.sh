#!/bin/bash
#
# Script d'installation et configuration Ollama pour RAG Familial
# Configure Ollama avec écoute réseau et téléchargement des modèles
#

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'a
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
║      INSTALLATION OLLAMA - RAG FAMILIAL      ║
║              Configuration Mac                ║
║                                               ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# ============================================
# VÉRIFICATION SYSTÈME
# ============================================

print_step "Vérification du système"

if [[ "$(uname)" != "Darwin" ]]; then
    print_error "Ce script est conçu pour macOS uniquement"
    exit 1
fi

if [[ $EUID -eq 0 ]]; then
    print_error "Ne pas exécuter ce script avec sudo"
    exit 1
fi

print_success "Système macOS détecté"

# Détection architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    print_success "Architecture: Apple Silicon (M1/M2/M3)"
elif [[ "$ARCH" == "x86_64" ]]; then
    print_success "Architecture: Intel x86_64"
else
    print_warning "Architecture non reconnue: $ARCH"
fi

# ============================================
# CHARGEMENT CONFIGURATION RÉSEAU
# ============================================

NETWORK_CONFIG="$HOME/.rag_network_config"

if [[ -f "$NETWORK_CONFIG" ]]; then
    print_step "Chargement de la configuration réseau"
    source "$NETWORK_CONFIG"
    print_success "Configuration réseau chargée"
    echo "  - IP Mac privée: $HOST_IP"
    echo ""
else
    print_warning "Configuration réseau non trouvée"
    echo "Exécuter d'abord: ./setup_network_mac.sh"
    echo ""
fi

# ============================================
# DÉTECTION IP RÉSEAU PRIVÉ
# ============================================

if [[ -z "$HOST_IP" ]]; then
    print_step "Détection de l'IP réseau privé du Mac"
    
    PRIVATE_IPS=$(ifconfig | grep -Eo 'inet (172|192\.168|10\.)\S+' | awk '{print $2}' | sort -u)
    
    if [[ -n "$PRIVATE_IPS" ]]; then
        echo "IPs privées détectées :"
        echo "$PRIVATE_IPS" | nl
        echo ""
        read -p "Sélectionner l'IP pour Ollama [numéro]: " IP_CHOICE
        
        if [[ $IP_CHOICE =~ ^[0-9]+$ ]]; then
            HOST_IP=$(echo "$PRIVATE_IPS" | sed -n "${IP_CHOICE}p")
        else
            HOST_IP="$IP_CHOICE"
        fi
    else
        read -p "IP Mac sur le réseau privé (ex: 172.16.74.1): " HOST_IP
    fi
    
    while [[ ! $HOST_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; do
        print_error "IP invalide"
        read -p "IP Mac: " HOST_IP
    done
fi

print_success "IP réseau privé: $HOST_IP"

# ============================================
# CONFIGURATION DES MODÈLES
# ============================================

echo ""
print_step "Configuration des modèles LLM"
echo ""
echo "Modèles recommandés pour RAG :"
echo "  Embeddings:"
echo "    - nomic-embed-text:latest (recommandé, 274MB)"
echo "    - mxbai-embed-large:latest (alternative, 669MB)"
echo ""
echo "  LLM:"
echo "    - mistral:latest (léger, 4.1GB)"
echo "    - llama3.2:latest (performant, 2GB)"
echo "    - qwen2.5:latest (multilingue, 4.7GB)"
echo ""

read -p "Modèle d'embeddings (défaut: nomic-embed-text:latest): " EMBED_MODEL
EMBED_MODEL=${EMBED_MODEL:-nomic-embed-text:latest}

read -p "Modèle LLM (défaut: mistral:latest): " LLM_MODEL
LLM_MODEL=${LLM_MODEL:-mistral:latest}

# Modèles additionnels
echo ""
read -p "Télécharger des modèles additionnels ? (y/n): " ADDITIONAL_MODELS
EXTRA_MODELS=()

if [[ $ADDITIONAL_MODELS =~ ^[Yy]$ ]]; then
    echo "Entrer les modèles additionnels (un par ligne, ligne vide pour terminer):"
    while true; do
        read -p "Modèle: " extra_model
        [[ -z "$extra_model" ]] && break
        EXTRA_MODELS+=("$extra_model")
    done
fi

# Port d'écoute
echo ""
read -p "Port d'écoute Ollama (défaut: 11434): " OLLAMA_PORT
OLLAMA_PORT=${OLLAMA_PORT:-11434}

# ============================================
# RÉCAPITULATIF
# ============================================

echo ""
print_step "Récapitulatif de la configuration"
echo "════════════════════════════════════════════"
echo "Réseau:"
echo "  - IP privée    : $HOST_IP"
echo "  - Port         : $OLLAMA_PORT"
echo "  - Écoute       : 0.0.0.0:$OLLAMA_PORT (toutes interfaces)"
echo ""
echo "Modèles à télécharger:"
echo "  - Embeddings   : $EMBED_MODEL"
echo "  - LLM          : $LLM_MODEL"

if [[ ${#EXTRA_MODELS[@]} -gt 0 ]]; then
    echo "  - Additionnels : ${EXTRA_MODELS[*]}"
fi

echo "════════════════════════════════════════════"
echo ""
read -p "Confirmer et continuer ? (y/n): " CONFIRM
[[ ! $CONFIRM =~ ^[Yy]$ ]] && { print_error "Installation annulée"; exit 1; }

# ============================================
# INSTALLATION OLLAMA
# ============================================

echo ""
print_step "Vérification de l'installation Ollama"

OLLAMA_INSTALLED=false
OLLAMA_VERSION=""

if command -v ollama &> /dev/null; then
    OLLAMA_VERSION=$(ollama --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "inconnue")
    print_success "Ollama déjà installé (version: $OLLAMA_VERSION)"
    OLLAMA_INSTALLED=true
    
    read -p "Réinstaller Ollama ? (y/n): " REINSTALL
    if [[ $REINSTALL =~ ^[Yy]$ ]]; then
        print_step "Arrêt d'Ollama..."
        pkill -9 ollama 2>/dev/null || true
        launchctl unload ~/Library/LaunchAgents/com.ollama.server.plist 2>/dev/null || true
        sleep 2
        OLLAMA_INSTALLED=false
    fi
fi

if [[ "$OLLAMA_INSTALLED" == false ]]; then
    print_step "Installation d'Ollama..."
    echo ""
    
    # Vérifier Homebrew
    if command -v brew &> /dev/null; then
        print_step "Installation via Homebrew..."
        brew install ollama
        print_success "Ollama installé via Homebrew"
    else
        print_step "Téléchargement manuel d'Ollama..."
        
        DOWNLOAD_URL="https://ollama.com/download/Ollama-darwin.zip"
        TEMP_DIR=$(mktemp -d)
        
        curl -L --progress-bar -o "$TEMP_DIR/ollama.zip" "$DOWNLOAD_URL"
        
        print_step "Extraction..."
        unzip -q "$TEMP_DIR/ollama.zip" -d "$TEMP_DIR"
        
        # Copier vers Applications
        if [[ -d "$TEMP_DIR/Ollama.app" ]]; then
            sudo cp -R "$TEMP_DIR/Ollama.app" /Applications/
            print_success "Ollama copié dans /Applications"
        else
            print_warning "Installation manuelle requise"
            open "$TEMP_DIR"
            echo "Glisser Ollama.app vers /Applications"
            read -p "Appuyer sur Entrée après installation..."
        fi
        
        # Créer lien symbolique
        if [[ ! -f "/usr/local/bin/ollama" ]]; then
            sudo mkdir -p /usr/local/bin
            sudo ln -sf "/Applications/Ollama.app/Contents/Resources/ollama" /usr/local/bin/ollama
        fi
        
        rm -rf "$TEMP_DIR"
    fi
    
    # Vérifier installation
    if command -v ollama &> /dev/null; then
        OLLAMA_VERSION=$(ollama --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "inconnue")
        print_success "Ollama installé (version: $OLLAMA_VERSION)"
    else
        print_error "Installation d'Ollama échouée"
        exit 1
    fi
fi

# ============================================
# CONFIGURATION LAUNCHAGENT
# ============================================

echo ""
print_step "Configuration du service Ollama (LaunchAgent)"

# Arrêt des processus existants
print_step "Arrêt des instances Ollama existantes..."
pkill -9 ollama 2>/dev/null || true
launchctl unload ~/Library/LaunchAgents/com.ollama.server.plist 2>/dev/null || true
sleep 2

PLIST_PATH="$HOME/Library/LaunchAgents/com.ollama.server.plist"
LOG_DIR="$HOME/Library/Logs"

mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$LOG_DIR"

# Créer le LaunchAgent
print_step "Création du LaunchAgent..."

cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ollama.server</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/ollama</string>
        <string>serve</string>
    </array>
    
    <key>EnvironmentVariables</key>
    <dict>
        <key>OLLAMA_HOST</key>
        <string>0.0.0.0:$OLLAMA_PORT</string>
        <key>OLLAMA_ORIGINS</key>
        <string>*</string>
    </dict>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <true/>
    
    <key>StandardOutPath</key>
    <string>$LOG_DIR/ollama.log</string>
    
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/ollama_error.log</string>
    
    <key>ProcessType</key>
    <string>Background</string>
    
    <key>ThrottleInterval</key>
    <integer>5</integer>
</dict>
</plist>
EOF

print_success "LaunchAgent créé: $PLIST_PATH"

# Charger le LaunchAgent
print_step "Démarrage du service Ollama..."
launchctl load "$PLIST_PATH"

# Attendre démarrage
echo "Attente du démarrage d'Ollama (10 secondes)..."
sleep 10

# ============================================
# VÉRIFICATION SERVICE
# ============================================

print_step "Vérification du service Ollama"

# Test local
if curl -s http://localhost:$OLLAMA_PORT/api/tags > /dev/null; then
    print_success "✓ Ollama accessible localement (localhost:$OLLAMA_PORT)"
else
    print_error "✗ Ollama non accessible localement"
    echo "Logs: tail -f $LOG_DIR/ollama_error.log"
    exit 1
fi

# Test réseau privé
if curl -s http://$HOST_IP:$OLLAMA_PORT/api/tags > /dev/null; then
    print_success "✓ Ollama accessible sur le réseau privé ($HOST_IP:$OLLAMA_PORT)"
else
    print_warning "✗ Ollama non accessible via $HOST_IP:$OLLAMA_PORT"
    echo ""
    echo "Vérifications à effectuer :"
    echo "  1. Pare-feu macOS (Préférences Système > Réseau > Pare-feu)"
    echo "  2. Autoriser 'ollama' dans les connexions entrantes"
    echo ""
fi

# ============================================
# TÉLÉCHARGEMENT DES MODÈLES
# ============================================

echo ""
print_step "Téléchargement des modèles LLM"
echo "Cette étape peut prendre plusieurs minutes selon la taille des modèles..."
echo ""

# Fonction pull avec barre de progression
pull_model() {
    local model=$1
    print_step "Pull du modèle: $model"
    
    # Vérifier si déjà présent
    if ollama list 2>/dev/null | grep -q "^${model%%:*}"; then
        print_success "Modèle $model déjà présent"
        return 0
    fi
    
    # Télécharger
    if ollama pull "$model"; then
        print_success "Modèle $model téléchargé"
        return 0
    else
        print_error "Échec du téléchargement de $model"
        return 1
    fi
}

# Télécharger modèle embeddings
pull_model "$EMBED_MODEL"

# Télécharger modèle LLM
pull_model "$LLM_MODEL"

# Télécharger modèles additionnels
if [[ ${#EXTRA_MODELS[@]} -gt 0 ]]; then
    echo ""
    for model in "${EXTRA_MODELS[@]}"; do
        pull_model "$model"
    done
fi

# ============================================
# VÉRIFICATION MODÈLES
# ============================================

echo ""
print_step "Modèles installés"
echo ""
ollama list
echo ""

# ============================================
# TEST FONCTIONNEL
# ============================================

print_step "Test fonctionnel du LLM"
echo ""

TEST_PROMPT="Réponds juste 'OK' si tu fonctionnes correctement"

print_step "Envoi d'une requête test au modèle $LLM_MODEL..."

TEST_RESPONSE=$(curl -s http://localhost:$OLLAMA_PORT/api/generate -d "{
  \"model\": \"$LLM_MODEL\",
  \"prompt\": \"$TEST_PROMPT\",
  \"stream\": false
}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('response', ''))" 2>/dev/null)

if [[ -n "$TEST_RESPONSE" ]]; then
    print_success "Test LLM réussi"
    echo "Réponse: $TEST_RESPONSE"
else
    print_warning "Test LLM n'a pas retourné de réponse claire"
    echo "Le modèle est installé mais peut nécessiter quelques secondes de warm-up"
fi

# ============================================
# CONFIGURATION PARE-FEU
# ============================================

echo ""
print_step "Configuration du pare-feu macOS"

FIREWALL_STATUS=$(sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q "enabled" && echo "enabled" || echo "disabled")

if [[ "$FIREWALL_STATUS" == "enabled" ]]; then
    print_warning "Pare-feu macOS activé"
    echo ""
    echo "Pour autoriser Ollama depuis la VM :"
    echo "  1. Préférences Système > Réseau > Pare-feu"
    echo "  2. Options du pare-feu"
    echo "  3. Ajouter 'ollama' et autoriser connexions entrantes"
    echo ""
    read -p "Autoriser automatiquement ollama dans le pare-feu ? (y/n): " ALLOW_FIREWALL
    
    if [[ $ALLOW_FIREWALL =~ ^[Yy]$ ]]; then
        sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /usr/local/bin/ollama
        sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /usr/local/bin/ollama
        print_success "Ollama autorisé dans le pare-feu"
    fi
else
    print_success "Pare-feu macOS désactivé (Ollama accessible)"
fi

# ============================================
# SAUVEGARDE CONFIGURATION
# ============================================

print_step "Sauvegarde de la configuration"

OLLAMA_CONFIG_FILE="$HOME/.rag_ollama_config"

cat > "$OLLAMA_CONFIG_FILE" << EOF
# Configuration Ollama pour RAG Familial
# Générée le $(date)

OLLAMA_VERSION=$OLLAMA_VERSION
OLLAMA_HOST=0.0.0.0:$OLLAMA_PORT
OLLAMA_URL=http://$HOST_IP:$OLLAMA_PORT
HOST_IP=$HOST_IP
OLLAMA_PORT=$OLLAMA_PORT

EMBED_MODEL=$EMBED_MODEL
LLM_MODEL=$LLM_MODEL

# Fichiers
PLIST_PATH=$PLIST_PATH
LOG_FILE=$LOG_DIR/ollama.log
ERROR_LOG=$LOG_DIR/ollama_error.log

# Commandes utiles
# Lister modèles     : ollama list
# Pull modèle        : ollama pull <modèle>
# Remove modèle      : ollama rm <modèle>
# Test interactif    : ollama run $LLM_MODEL
# Redémarrer service : launchctl unload $PLIST_PATH && launchctl load $PLIST_PATH
# Voir logs          : tail -f $LOG_DIR/ollama.log

# Test API
# curl http://$HOST_IP:$OLLAMA_PORT/api/tags
# curl http://$HOST_IP:$OLLAMA_PORT/api/generate -d '{"model":"$LLM_MODEL","prompt":"Hello","stream":false}'
EOF

chmod 600 "$OLLAMA_CONFIG_FILE"
print_success "Configuration sauvegardée: $OLLAMA_CONFIG_FILE"

# ============================================
# CRÉATION SCRIPT D'EXPORT POUR LA VM
# ============================================

print_step "Création du fichier d'export pour la VM"

EXPORT_FILE="$HOME/.rag_ollama_export"

cat > "$EXPORT_FILE" << EOF
# Variables d'environnement Ollama pour la VM
# À sourcer sur la VM: source ~/.rag_ollama_config

export OLLAMA_HOST=http://$HOST_IP:$OLLAMA_PORT
export EMBED_MODEL=$EMBED_MODEL
export LLM_MODEL=$LLM_MODEL
EOF

chmod 644 "$EXPORT_FILE"
print_success "Fichier d'export créé: $EXPORT_FILE"

echo ""
echo "Pour copier sur la VM:"
echo "  scp $EXPORT_FILE <vm_user>@<vm_ip>:~/.rag_ollama_config"

# ============================================
# RÉSUMÉ FINAL
# ============================================

echo ""
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════╗
║                                               ║
║       OLLAMA INSTALLÉ AVEC SUCCÈS            ║
║                                               ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo "📍 Configuration:"
echo "   - Version      : $OLLAMA_VERSION"
echo "   - Écoute       : 0.0.0.0:$OLLAMA_PORT (toutes interfaces)"
echo "   - URL privée   : http://$HOST_IP:$OLLAMA_PORT"
echo "   - LaunchAgent  : Démarrage automatique activé"
echo ""
echo "🤖 Modèles installés:"
echo "   - Embeddings   : $EMBED_MODEL"
echo "   - LLM          : $LLM_MODEL"

if [[ ${#EXTRA_MODELS[@]} -gt 0 ]]; then
    echo "   - Additionnels : ${EXTRA_MODELS[*]}"
fi

echo ""
echo "📁 Fichiers:"
echo "   - Config       : $OLLAMA_CONFIG_FILE"
echo "   - LaunchAgent  : $PLIST_PATH"
echo "   - Logs         : $LOG_DIR/ollama.log"
echo "   - Export VM    : $EXPORT_FILE"
echo ""
echo -e "${YELLOW}Commandes utiles:${NC}"
echo "  ollama list                              # Lister les modèles"
echo "  ollama pull <modèle>                     # Télécharger un modèle"
echo "  ollama rm <modèle>                       # Supprimer un modèle"
echo "  ollama run $LLM_MODEL                    # Tester interactivement"
echo ""
echo -e "${YELLOW}Gestion du service:${NC}"
echo "  launchctl unload $PLIST_PATH             # Arrêter"
echo "  launchctl load $PLIST_PATH               # Démarrer"
echo "  tail -f $LOG_DIR/ollama.log              # Voir les logs"
echo ""
echo -e "${YELLOW}Test depuis la VM:${NC}"
echo "  curl http://$HOST_IP:$OLLAMA_PORT/api/tags"
echo ""
echo -e "${YELLOW}Prochaines étapes:${NC}"
echo "  1. Tester depuis la VM: curl http://$HOST_IP:$OLLAMA_PORT/api/tags"
echo "  2. Déployer le RAG: ./setup_rag.sh"
echo ""
print_success "Installation terminée!"
