#!/bin/bash
#
# Nettoyage complet de l'installation Ollama sur macOS
# Supprime tous les éléments créés par setup_ollama_mac.sh
#

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_info() { echo -e "${CYAN}[i]${NC} $1"; }

# Banner
clear
echo -e "${RED}"
cat << "EOF"
╔═══════════════════════════════════════════════╗
║                                               ║
║        NETTOYAGE OLLAMA - macOS              ║
║          ⚠️  SUPPRESSION COMPLÈTE            ║
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
    exit 1
fi

print_success "macOS détecté"

# ============================================
# AVERTISSEMENT
# ============================================

echo ""
print_warning "Ce script va supprimer:"
echo "  - Service Ollama (LaunchAgent)"
echo "  - Application Ollama"
echo "  - Modèles téléchargés (~/.ollama)"
echo "  - Dossier partagé RAG"
echo "  - Configuration (~/.rag_ollama_config)"
echo "  - Logs Ollama"
echo ""
read -p "Confirmer la suppression ? [y/N]: " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    print_info "Nettoyage annulé"
    exit 0
fi

# ============================================
# CHARGEMENT CONFIG
# ============================================

CONFIG_FILE="$HOME/.rag_ollama_config"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    print_info "Configuration chargée"
else
    print_warning "Aucune configuration trouvée, nettoyage standard"
    SHARED_DIR="$HOME/RAG_Data"
fi

# ============================================
# ARRÊT SERVICE OLLAMA
# ============================================

echo ""
print_step "Arrêt du service Ollama"

LAUNCHD_PLIST="$HOME/Library/LaunchAgents/com.ollama.ollama.plist"

# Arrêt via launchctl
if launchctl list | grep -q "com.ollama.ollama"; then
    print_info "Arrêt du LaunchAgent..."
    launchctl unload "$LAUNCHD_PLIST" 2>/dev/null || true
    print_success "LaunchAgent arrêté"
else
    print_info "LaunchAgent non actif"
fi

# Kill processus Ollama
if pgrep -x "ollama" >/dev/null; then
    print_info "Arrêt des processus Ollama..."
    killall ollama 2>/dev/null || true
    sleep 2
    print_success "Processus Ollama arrêtés"
else
    print_info "Aucun processus Ollama actif"
fi

# ============================================
# SUPPRESSION LAUNCHAGENT
# ============================================

echo ""
print_step "Suppression du LaunchAgent"

if [[ -f "$LAUNCHD_PLIST" ]]; then
    rm -f "$LAUNCHD_PLIST"
    print_success "LaunchAgent supprimé"
else
    print_info "LaunchAgent inexistant"
fi

# ============================================
# DÉSINSTALLATION OLLAMA
# ============================================

echo ""
print_step "Désinstallation d'Ollama"

if command -v ollama &>/dev/null; then
    OLLAMA_LOCATION=$(which ollama)
    print_info "Ollama détecté: $OLLAMA_LOCATION"
    
    # Si installé via Homebrew
    if brew list ollama &>/dev/null 2>&1; then
        print_info "Désinstallation via Homebrew..."
        brew uninstall ollama
        print_success "Ollama désinstallé (Homebrew)"
    else
        # Installation manuelle
        print_info "Suppression manuelle d'Ollama..."
        sudo rm -f "$OLLAMA_LOCATION"
        sudo rm -rf /usr/local/bin/ollama
        print_success "Ollama supprimé manuellement"
    fi
else
    print_info "Ollama non installé"
fi

# ============================================
# SUPPRESSION MODÈLES ET DONNÉES
# ============================================

echo ""
print_step "Suppression des modèles et données Ollama"

OLLAMA_DIR="$HOME/.ollama"

if [[ -d "$OLLAMA_DIR" ]]; then
    # Calcul taille
    SIZE=$(du -sh "$OLLAMA_DIR" 2>/dev/null | cut -f1)
    print_info "Taille des données Ollama: $SIZE"
    
    read -p "Supprimer tous les modèles et données ? [y/N]: " DELETE_MODELS
    
    if [[ "$DELETE_MODELS" =~ ^[Yy]$ ]]; then
        rm -rf "$OLLAMA_DIR"
        print_success "Données Ollama supprimées ($SIZE libérés)"
    else
        print_info "Données Ollama conservées"
    fi
else
    print_info "Aucune donnée Ollama à supprimer"
fi

# ============================================
# SUPPRESSION LOGS
# ============================================

echo ""
print_step "Suppression des logs"

LOGS=(
    "$HOME/Library/Logs/ollama.log"
    "$HOME/Library/Logs/ollama.error.log"
)

for log in "${LOGS[@]}"; do
    if [[ -f "$log" ]]; then
        rm -f "$log"
        print_success "Log supprimé: $(basename "$log")"
    fi
done

# ============================================
# NETTOYAGE DOSSIER PARTAGÉ (OPTIONNEL)
# ============================================

echo ""
print_step "Nettoyage du dossier partagé (optionnel)"

if [[ -n "$SHARED_DIR" ]] && [[ -d "$SHARED_DIR" ]]; then
    SIZE=$(du -sh "$SHARED_DIR" 2>/dev/null | cut -f1)
    print_info "Dossier partagé: $SHARED_DIR ($SIZE)"
    
    read -p "Supprimer le dossier partagé RAG ? [y/N]: " DELETE_SHARED
    
    if [[ "$DELETE_SHARED" =~ ^[Yy]$ ]]; then
        rm -rf "$SHARED_DIR"
        print_success "Dossier partagé supprimé"
    else
        print_info "Dossier partagé conservé"
    fi
else
    print_info "Aucun dossier partagé configuré"
fi

# ============================================
# SUPPRESSION CONFIGURATION
# ============================================

echo ""
print_step "Suppression de la configuration"

if [[ -f "$CONFIG_FILE" ]]; then
    rm -f "$CONFIG_FILE"
    print_success "Configuration supprimée"
else
    print_info "Aucune configuration à supprimer"
fi

# ============================================
# NETTOYAGE PARE-FEU (OPTIONNEL)
# ============================================

echo ""
print_step "Nettoyage du pare-feu (optionnel)"

if /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate | grep -q "enabled"; then
    print_info "Pare-feu macOS actif"
    
    read -p "Retirer Ollama du pare-feu ? [y/N]: " FIREWALL_CLEANUP
    
    if [[ "$FIREWALL_CLEANUP" =~ ^[Yy]$ ]]; then
        # Recherche Ollama dans le pare-feu
        if /usr/libexec/ApplicationFirewall/socketfilterfw --listapps 2>/dev/null | grep -q "ollama"; then
            sudo /usr/libexec/ApplicationFirewall/socketfilterfw --remove /usr/local/bin/ollama 2>/dev/null || true
            sudo /usr/libexec/ApplicationFirewall/socketfilterfw --remove /opt/homebrew/bin/ollama 2>/dev/null || true
            print_success "Ollama retiré du pare-feu"
        else
            print_info "Ollama absent du pare-feu"
        fi
    fi
else
    print_info "Pare-feu désactivé, rien à nettoyer"
fi

# ============================================
# NETTOYAGE SSHFS (OPTIONNEL)
# ============================================

echo ""
print_step "Nettoyage SSHFS (optionnel)"

if command -v sshfs &>/dev/null; then
    print_info "SSHFS installé"
    
    read -p "Désinstaller SSHFS et macFUSE ? [y/N]: " REMOVE_SSHFS
    
    if [[ "$REMOVE_SSHFS" =~ ^[Yy]$ ]]; then
        if command -v brew &>/dev/null; then
            brew uninstall sshfs-mac 2>/dev/null || true
            print_info "Pour désinstaller macFUSE complètement:"
            echo "  1. Ouvrir Préférences Système → Extensions"
            echo "  2. Désactiver macFUSE"
            echo "  3. Exécuter: brew uninstall --cask macfuse"
            print_success "SSHFS désinstallé"
        fi
    else
        print_info "SSHFS conservé"
    fi
else
    print_info "SSHFS non installé"
fi

# ============================================
# VÉRIFICATION NETTOYAGE
# ============================================

echo ""
print_step "Vérification du nettoyage"

REMAINING=0

# Check Ollama
if command -v ollama &>/dev/null; then
    print_warning "Ollama encore installé"
    REMAINING=$((REMAINING+1))
fi

# Check LaunchAgent
if [[ -f "$LAUNCHD_PLIST" ]]; then
    print_warning "LaunchAgent existe encore"
    REMAINING=$((REMAINING+1))
fi

# Check processus
if pgrep -x "ollama" >/dev/null; then
    print_warning "Processus Ollama encore actif"
    REMAINING=$((REMAINING+1))
fi

# Check données
if [[ -d "$HOME/.ollama" ]]; then
    print_warning "Données Ollama existent encore"
    REMAINING=$((REMAINING+1))
fi

# Check config
if [[ -f "$CONFIG_FILE" ]]; then
    print_warning "Configuration existe encore"
    REMAINING=$((REMAINING+1))
fi

if [[ $REMAINING -eq 0 ]]; then
    print_success "Nettoyage complet vérifié ✓"
else
    print_warning "$REMAINING élément(s) restant(s)"
fi

# ============================================
# RÉSUMÉ
# ============================================

echo ""
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════╗
║                                               ║
║          NETTOYAGE TERMINÉ                   ║
║                                               ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo ""
echo "✅ Éléments supprimés:"
echo ""
echo "  ✓ Service Ollama (LaunchAgent)"
echo "  ✓ Application Ollama"

if [[ "$DELETE_MODELS" =~ ^[Yy]$ ]]; then
    echo "  ✓ Modèles et données (~/.ollama)"
fi

echo "  ✓ Logs Ollama"
echo "  ✓ Configuration (~/.rag_ollama_config)"

if [[ "$DELETE_SHARED" =~ ^[Yy]$ ]]; then
    echo "  ✓ Dossier partagé RAG"
fi

echo ""

if [[ $REMAINING -gt 0 ]]; then
    echo "⚠️  Nettoyage manuel requis pour $REMAINING élément(s)"
    echo ""
fi

echo "🔄 Pour réinstaller:"
echo "   ./setup_ollama_mac.sh"
echo ""

print_success "Nettoyage terminé!"
```

---

## 📦 **Package complet des 4 scripts**

Voici l'organisation finale :
```
RAG-Familial/
├── setup_ollama_mac.sh      # Installation Mac
├── cleanup_ollama_mac.sh    # Nettoyage Mac (nouveau)
├── setup_rag_vm.sh          # Installation VM
└── cleanup_rag_vm.sh        # Nettoyage VM
