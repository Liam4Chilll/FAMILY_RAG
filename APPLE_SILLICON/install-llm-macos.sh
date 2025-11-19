#!/bin/bash
#
# Setup Ollama sur macOS pour RAG Familial
# Prérequis: SSH déjà configuré vers la VM Fedora
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
║       SETUP OLLAMA - RAG FAMILIAL            ║
║            macOS Configuration                ║
║                                               ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# ============================================
# VÉRIFICATION SYSTÈME
# ============================================

print_step "Vérification du système"

if [[ "$(uname -s)" != "Darwin" ]]; then
    print_error "Ce script est conçu pour macOS uniquement"
fi

print_success "macOS détecté"

# Détection architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    print_success "Architecture: Apple Silicon (M-series)"
    OLLAMA_ARCH="arm64"
elif [[ "$ARCH" == "x86_64" ]]; then
    print_success "Architecture: Intel x86_64"
    OLLAMA_ARCH="amd64"
else
    print_error "Architecture non supportée: $ARCH"
fi

# ============================================
# CHARGEMENT CONFIG EXISTANTE
# ============================================

CONFIG_FILE="$HOME/.rag_ollama_config"

if [[ -f "$CONFIG_FILE" ]]; then
    echo ""
    print_info "Configuration existante trouvée"
    echo ""
    source "$CONFIG_FILE"
    echo "Configuration actuelle:"
    echo "  - Interface réseau : $NETWORK_INTERFACE"
    echo "  - IP Mac           : $MAC_IP"
    echo "  - IP VM            : $VM_IP"
    echo "  - User VM          : $VM_USER"
    echo "  - Dossier partagé  : $SHARED_DIR"
    echo "  - Modèle embedding : $EMBED_MODEL"
    echo "  - Modèle LLM       : $LLM_MODEL"
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
        IP=$(ifconfig "$iface" 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}')
        if [[ -n "$IP" ]]; then
            # Filter IPs privées: 10.x, 172.16-31.x, 192.168.x
            if echo "$IP" | grep -qE '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)'; then
                NETWORK_LIST+=("$iface")
                IP_LIST+=("$IP")
            fi
        fi
    done < <(ifconfig | grep -E '^[a-z]' | cut -d: -f1)

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
        read -p "Sélectionnez l'interface pour communiquer avec la VM [1-${#NETWORK_LIST[@]}]: " IFACE_CHOICE
        
        if [[ "$IFACE_CHOICE" =~ ^[0-9]+$ ]] && \
           [[ "$IFACE_CHOICE" -ge 1 ]] && \
           [[ "$IFACE_CHOICE" -le ${#NETWORK_LIST[@]} ]]; then
            break
        else
            print_warning "Choix invalide, réessayez"
        fi
    done

    NETWORK_INTERFACE="${NETWORK_LIST[$((IFACE_CHOICE-1))]}"
    MAC_IP="${IP_LIST[$((IFACE_CHOICE-1))]}"

    echo ""
    print_success "Interface sélectionnée: ${MAGENTA}$NETWORK_INTERFACE${NC} (${CYAN}$MAC_IP${NC})"
fi

# ============================================
# CONFIGURATION VM FEDORA
# ============================================

if [[ "$SKIP_CONFIG" != true ]]; then
    echo ""
    print_step "Configuration de la VM Fedora"
    echo ""
    
    # IP VM
    while true; do
        read -p "IP de la VM Fedora: " VM_IP
        if [[ "$VM_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            break
        else
            print_warning "Format IP invalide, réessayez"
        fi
    done
    
    # User VM
    read -p "Utilisateur sur la VM (défaut: $(whoami)): " VM_USER
    VM_USER=${VM_USER:-$(whoami)}
    
    # Test SSH
    echo ""
    print_info "Test de connexion SSH vers ${CYAN}$VM_USER@$VM_IP${NC}..."
    
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "$VM_USER@$VM_IP" "exit" 2>/dev/null; then
        print_success "Connexion SSH validée ✓"
    else
        echo ""
        print_error "Échec connexion SSH. Vérifiez:\n  - SSH configuré avec clés (ssh-copy-id)\n  - IP correcte\n  - VM accessible"
    fi
fi

# ============================================
# CONFIGURATION DOSSIER PARTAGÉ
# ============================================

if [[ "$SKIP_CONFIG" != true ]]; then
    echo ""
    print_step "Configuration du dossier partagé"
    echo ""
    
    read -p "Dossier Mac à partager avec la VM (défaut: ~/RAG_Data): " SHARED_DIR
    SHARED_DIR=${SHARED_DIR:-"$HOME/RAG_Data"}
    
    # Expansion tilde
    SHARED_DIR="${SHARED_DIR/#\~/$HOME}"
    
    # Création si inexistant
    if [[ ! -d "$SHARED_DIR" ]]; then
        mkdir -p "$SHARED_DIR"
        print_success "Dossier créé: ${CYAN}$SHARED_DIR${NC}"
    else
        print_info "Dossier existe déjà: ${CYAN}$SHARED_DIR${NC}"
    fi
    
    # Création sous-dossiers
    mkdir -p "$SHARED_DIR"/{documents,raw,processed}
    print_success "Structure créée: documents/, raw/, processed/"
fi

# ============================================
# CONFIGURATION MODÈLES
# ============================================

if [[ "$SKIP_CONFIG" != true ]]; then
    echo ""
    print_step "Configuration des modèles Ollama"
    echo ""
    
    read -p "Modèle embedding (défaut: nomic-embed-text): " EMBED_MODEL
    EMBED_MODEL=${EMBED_MODEL:-"nomic-embed-text"}
    
    read -p "Modèle LLM (défaut: mistral:latest): " LLM_MODEL
    LLM_MODEL=${LLM_MODEL:-"mistral:latest"}
    
    print_info "Modèles sélectionnés:"
    echo "  - Embedding: ${CYAN}$EMBED_MODEL${NC}"
    echo "  - LLM      : ${CYAN}$LLM_MODEL${NC}"
fi

# ============================================
# RÉSUMÉ CONFIGURATION
# ============================================

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          RÉSUMÉ DE LA CONFIGURATION          ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo "🖥️  Architecture     : $ARCH"
echo "🌐 Interface Mac    : $NETWORK_INTERFACE"
echo "📍 IP Mac           : $MAC_IP"
echo "🔗 VM Fedora        : $VM_USER@$VM_IP"
echo "📁 Dossier partagé  : $SHARED_DIR"
echo "🧠 Modèle embedding : $EMBED_MODEL"
echo "💬 Modèle LLM       : $LLM_MODEL"
echo "🌍 Ollama écoute    : http://$MAC_IP:11434"
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
# Configuration Ollama RAG Familial - Générée le $(date)

# Système
ARCH=$ARCH
OLLAMA_ARCH=$OLLAMA_ARCH

# Réseau
NETWORK_INTERFACE=$NETWORK_INTERFACE
MAC_IP=$MAC_IP
VM_IP=$VM_IP
VM_USER=$VM_USER

# Dossiers
SHARED_DIR=$SHARED_DIR

# Modèles
EMBED_MODEL=$EMBED_MODEL
LLM_MODEL=$LLM_MODEL
EOF

chmod 600 "$CONFIG_FILE"
print_success "Configuration sauvegardée: $CONFIG_FILE"

# ============================================
# INSTALLATION OLLAMA
# ============================================

echo ""
print_step "Installation d'Ollama"

if command -v ollama &>/dev/null; then
    OLLAMA_VERSION=$(ollama --version 2>/dev/null | head -n1)
    print_warning "Ollama déjà installé: $OLLAMA_VERSION"
    read -p "Réinstaller Ollama ? [y/N]: " REINSTALL
    
    if [[ "$REINSTALL" =~ ^[Yy]$ ]]; then
        print_info "Arrêt des services Ollama..."
        launchctl unload ~/Library/LaunchAgents/com.ollama.ollama.plist 2>/dev/null || true
        brew services stop ollama 2>/dev/null || true
        killall ollama 2>/dev/null || true
        sleep 2
        
        print_info "Désinstallation via Homebrew..."
        brew uninstall ollama 2>/dev/null || true
        SKIP_OLLAMA_INSTALL=false
    else
        print_info "Installation Ollama ignorée"
        SKIP_OLLAMA_INSTALL=true
    fi
fi

if [[ "$SKIP_OLLAMA_INSTALL" != true ]]; then
    # Vérification Homebrew
    if ! command -v brew &>/dev/null; then
        print_error "Homebrew n'est pas installé. Installation requise:\n  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    fi
    
    print_success "Homebrew détecté ✓"
    
    print_info "Installation d'Ollama via Homebrew..."
    
    if brew install ollama; then
        print_success "Ollama installé avec succès"
    else
        print_error "Échec de l'installation d'Ollama via Homebrew"
    fi
    
    # Vérification installation
    if command -v ollama &>/dev/null; then
        OLLAMA_VERSION=$(ollama --version 2>/dev/null | head -n1)
        print_success "Version installée: $OLLAMA_VERSION"
    else
        print_error "Ollama n'est pas accessible après installation"
    fi
fi

# ============================================
# CONFIGURATION ÉCOUTE RÉSEAU
# ============================================

echo ""
print_step "Configuration de l'écoute réseau Ollama"

LAUNCHD_PLIST="$HOME/Library/LaunchAgents/com.ollama.ollama.plist"

# Arrêt de tous les services Ollama existants
print_info "Arrêt des services existants..."
launchctl unload "$LAUNCHD_PLIST" 2>/dev/null || true
brew services stop ollama 2>/dev/null || true
killall ollama 2>/dev/null || true
sleep 3

# Détection du chemin Ollama
if [[ -f "/opt/homebrew/bin/ollama" ]]; then
    OLLAMA_BIN="/opt/homebrew/bin/ollama"
elif [[ -f "/usr/local/bin/ollama" ]]; then
    OLLAMA_BIN="/usr/local/bin/ollama"
else
    OLLAMA_BIN=$(which ollama)
fi

print_info "Ollama détecté: $OLLAMA_BIN"

# Création du répertoire LaunchAgents si nécessaire
mkdir -p "$HOME/Library/LaunchAgents"

# Création du LaunchAgent avec chemin absolu
cat > "$LAUNCHD_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ollama.ollama</string>
    <key>ProgramArguments</key>
    <array>
        <string>$OLLAMA_BIN</string>
        <string>serve</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>OLLAMA_HOST</key>
        <string>0.0.0.0:11434</string>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>HOME</key>
        <string>$HOME</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/ollama.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/ollama.error.log</string>
    <key>WorkingDirectory</key>
    <string>$HOME</string>
</dict>
</plist>
EOF

chmod 644 "$LAUNCHD_PLIST"
print_success "LaunchAgent créé: $LAUNCHD_PLIST"

# Démarrage du service
print_info "Démarrage du service Ollama..."
launchctl load "$LAUNCHD_PLIST"

# Attente démarrage avec retry
MAX_RETRIES=15
RETRY=0
print_info "Attente du démarrage du service..."

while [ $RETRY -lt $MAX_RETRIES ]; do
    if curl -s --connect-timeout 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
        echo ""
        print_success "Service Ollama démarré ✓"
        break
    else
        RETRY=$((RETRY+1))
        echo -ne "\r${BLUE}[→]${NC} Tentative $RETRY/$MAX_RETRIES..."
        sleep 2
    fi
done

if [ $RETRY -eq $MAX_RETRIES ]; then
    echo ""
    print_warning "Le service tarde à démarrer"
    echo ""
    echo "Vérification des logs:"
    if [[ -f "$HOME/Library/Logs/ollama.error.log" ]]; then
        tail -5 "$HOME/Library/Logs/ollama.error.log"
    fi
    echo ""
    print_warning "Tentative de démarrage manuel..."
    
    # Tentative démarrage manuel en arrière-plan
    OLLAMA_HOST=0.0.0.0:11434 nohup "$OLLAMA_BIN" serve > "$HOME/Library/Logs/ollama.log" 2>&1 &
    sleep 5
    
    if curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
        print_success "Démarrage manuel réussi ✓"
    else
        print_error "Impossible de démarrer Ollama. Vérifiez:\n  tail -f ~/Library/Logs/ollama.error.log"
    fi
fi

# Vérification liste services
if launchctl list | grep -q "com.ollama.ollama"; then
    print_success "LaunchAgent actif ✓"
else
    print_warning "LaunchAgent non listé dans launchctl"
fi

# Test accessibilité
echo ""
print_info "Test d'accessibilité Ollama..."

if curl -s --connect-timeout 5 "http://127.0.0.1:11434/api/tags" >/dev/null; then
    print_success "Ollama répond sur localhost ✓"
else
    print_warning "Ollama ne répond pas sur localhost"
fi

if curl -s --connect-timeout 5 "http://$MAC_IP:11434/api/tags" >/dev/null; then
    print_success "Ollama répond sur $MAC_IP ✓"
else
    print_warning "Ollama n'est pas accessible depuis $MAC_IP"
fi

# ============================================
# TÉLÉCHARGEMENT MODÈLES
# ============================================

echo ""
print_step "Téléchargement des modèles"

# Fonction de téléchargement avec barre de progression
download_model() {
    local MODEL=$1
    print_info "Téléchargement du modèle: ${CYAN}$MODEL${NC}"
    
    if "$OLLAMA_BIN" pull "$MODEL" 2>&1 | while IFS= read -r line; do
        if [[ "$line" =~ pulling|success|digest ]]; then
            echo -ne "\r${BLUE}[→]${NC} $line"
        fi
    done; then
        echo ""
        print_success "Modèle ${CYAN}$MODEL${NC} téléchargé ✓"
        return 0
    else
        echo ""
        print_warning "Échec téléchargement ${CYAN}$MODEL${NC}"
        return 1
    fi
}

# Téléchargement embedding
print_info "Vérification du modèle embedding..."
if ! "$OLLAMA_BIN" list | grep -q "$EMBED_MODEL"; then
    download_model "$EMBED_MODEL"
else
    print_success "Modèle ${CYAN}$EMBED_MODEL${NC} déjà présent ✓"
fi

# Téléchargement LLM
print_info "Vérification du modèle LLM..."
LLM_BASE=$(echo "$LLM_MODEL" | cut -d: -f1)
if ! "$OLLAMA_BIN" list | grep -q "$LLM_BASE"; then
    download_model "$LLM_MODEL"
else
    print_success "Modèle ${CYAN}$LLM_MODEL${NC} déjà présent ✓"
fi

# Vérification modèles installés
echo ""
print_info "Modèles disponibles:"
"$OLLAMA_BIN" list | tail -n +2 | while read -r line; do
    echo "  ${GREEN}✓${NC} $line"
done

# ============================================
# CONFIGURATION PARE-FEU macOS
# ============================================

echo ""
print_step "Configuration du pare-feu macOS"

if /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q "enabled"; then
    print_warning "Pare-feu macOS actif"
    echo ""
    echo "Pour permettre les connexions depuis la VM:"
    echo "  1. Préférences Système → Sécurité → Pare-feu"
    echo "  2. Options du pare-feu"
    echo "  3. Ajouter Ollama ($OLLAMA_BIN)"
    echo "  4. Autoriser connexions entrantes"
    echo ""
    read -p "Voulez-vous ajouter Ollama au pare-feu maintenant ? [y/N]: " FIREWALL
    
    if [[ "$FIREWALL" =~ ^[Yy]$ ]]; then
        sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "$OLLAMA_BIN" 2>/dev/null || true
        sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$OLLAMA_BIN" 2>/dev/null || true
        print_success "Ollama ajouté au pare-feu"
    fi
else
    print_success "Pare-feu macOS désactivé, pas de configuration nécessaire"
fi

# ============================================
# TEST DEPUIS LA VM
# ============================================

echo ""
print_step "Test de connectivité depuis la VM"

print_info "Test depuis la VM: curl http://$MAC_IP:11434/api/tags"

if ssh -o ConnectTimeout=5 "$VM_USER@$VM_IP" "curl -s --connect-timeout 5 http://$MAC_IP:11434/api/tags" >/dev/null 2>&1; then
    print_success "La VM peut accéder à Ollama sur le Mac ✓"
else
    print_warning "La VM ne peut pas encore accéder à Ollama"
    echo ""
    echo "Vérifiez:"
    echo "  1. Pare-feu macOS (voir ci-dessus)"
    echo "  2. Test manuel depuis VM: curl http://$MAC_IP:11434/api/tags"
    echo "  3. Ollama écoute bien sur 0.0.0.0: lsof -i :11434"
fi

# ============================================
# CONFIGURATION SSHFS (OPTIONNEL)
# ============================================

echo ""
print_step "Configuration SSHFS (optionnel)"

if ! command -v sshfs &>/dev/null; then
    print_info "SSHFS n'est pas installé"
    read -p "Installer macFUSE + SSHFS pour partage bidirectionnel ? [y/N]: " INSTALL_SSHFS
    
    if [[ "$INSTALL_SSHFS" =~ ^[Yy]$ ]]; then
        if command -v brew &>/dev/null; then
            print_info "Installation via Homebrew..."
            brew install --cask macfuse
            brew install gromgit/fuse/sshfs-mac
            print_success "SSHFS installé"
        else
            print_warning "Homebrew non détecté. Installez macFUSE manuellement:"
            echo "  https://osxfuse.github.io/"
        fi
    fi
else
    print_success "SSHFS déjà installé"
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
echo "🤖 Ollama:"
echo "   - Service actif via LaunchAgent"
echo "   - Accessible localement : http://127.0.0.1:11434"
echo "   - Accessible réseau     : http://$MAC_IP:11434"
echo "   - Logs: ~/Library/Logs/ollama.log"
echo ""
echo "🧠 Modèles installés:"
echo "   - Embedding : $EMBED_MODEL"
echo "   - LLM       : $LLM_MODEL"
echo ""
echo "📁 Dossier partagé:"
echo "   - Chemin: $SHARED_DIR"
echo "   - Structure: documents/, raw/, processed/"
echo ""
echo "🔗 Connectivité VM:"
echo "   - VM Fedora : $VM_USER@$VM_IP"
echo "   - SSH       : Validé ✓"
echo ""
echo "📝 Commandes utiles:"
echo ""
echo "   # Tester Ollama localement"
echo "   curl http://127.0.0.1:11434/api/tags"
echo ""
echo "   # Tester depuis la VM"
echo "   ssh $VM_USER@$VM_IP \"curl http://$MAC_IP:11434/api/tags\""
echo ""
echo "   # Lister les modèles"
echo "   ollama list"
echo ""
echo "   # Test interactif"
echo "   ollama run $LLM_MODEL"
echo ""
echo "   # Voir les logs"
echo "   tail -f ~/Library/Logs/ollama.log"
echo ""
echo "   # Redémarrer le service"
echo "   launchctl unload ~/Library/LaunchAgents/com.ollama.ollama.plist"
echo "   launchctl load ~/Library/LaunchAgents/com.ollama.ollama.plist"
echo ""
echo "   # Vérifier si Ollama écoute sur le réseau"
echo "   lsof -i :11434"
echo ""
echo -e "${YELLOW}⚡ Prochaine étape:${NC}"
echo "   Exécuter sur la VM Fedora: ./setup_rag_vm.sh"
echo ""
echo -e "${CYAN}📄 Configuration sauvegardée:${NC} $CONFIG_FILE"
echo ""
print_success "Setup Mac terminé!"
