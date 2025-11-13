#!/bin/bash
#
# Nettoyage complet de l'installation RAG sur VM Fedora
# Supprime tous les éléments créés par setup_rag_vm.sh
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
║         NETTOYAGE RAG - VM FEDORA            ║
║          ⚠️  SUPPRESSION COMPLÈTE            ║
║                                               ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo ""
print_warning "Ce script va supprimer:"
echo "  - Environnement Python (~/rag_env)"
echo "  - Scripts RAG (~/rag.py, ~/rag_webui.py)"
echo "  - Index FAISS (~/faiss_index)"
echo "  - Point de montage SSHFS (~/rag_shared)"
echo "  - Configuration (~/.rag_vm_config)"
echo "  - Packages Python installés"
echo ""
read -p "Confirmer la suppression ? [y/N]: " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    print_info "Nettoyage annulé"
    exit 0
fi

# ============================================
# CHARGEMENT CONFIG
# ============================================

CONFIG_FILE="$HOME/.rag_vm_config"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    print_info "Configuration chargée"
else
    print_warning "Aucune configuration trouvée, nettoyage standard"
    MOUNT_POINT="$HOME/rag_shared"
fi

# ============================================
# DÉMONTAGE SSHFS
# ============================================

echo ""
print_step "Démontage SSHFS"

if [[ -n "$MOUNT_POINT" ]] && [[ -d "$MOUNT_POINT" ]]; then
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        print_info "Démontage: $MOUNT_POINT"
        fusermount -u "$MOUNT_POINT" 2>/dev/null || sudo umount "$MOUNT_POINT" 2>/dev/null || true
        sleep 1
        
        if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
            print_warning "Échec démontage normal, force..."
            fusermount -uz "$MOUNT_POINT" 2>/dev/null || sudo umount -l "$MOUNT_POINT" 2>/dev/null || true
        fi
        
        print_success "SSHFS démonté"
    else
        print_info "SSHFS non monté"
    fi
    
    # Suppression dossier
    if [[ -d "$MOUNT_POINT" ]]; then
        rm -rf "$MOUNT_POINT"
        print_success "Dossier supprimé: $MOUNT_POINT"
    fi
else
    print_info "Pas de point de montage à nettoyer"
fi

# ============================================
# ARRÊT PROCESSUS
# ============================================

echo ""
print_step "Arrêt des processus RAG"

# Arrêt Flask
if pgrep -f "rag_webui.py" >/dev/null; then
    print_info "Arrêt WebUI Flask..."
    pkill -f "rag_webui.py" || true
    print_success "WebUI arrêtée"
else
    print_info "Aucun processus WebUI actif"
fi

# Arrêt autres processus Python RAG
if pgrep -f "rag.py" >/dev/null; then
    print_info "Arrêt processus RAG..."
    pkill -f "rag.py" || true
    print_success "Processus RAG arrêtés"
fi

sleep 1

# ============================================
# SUPPRESSION ENVIRONNEMENT PYTHON
# ============================================

echo ""
print_step "Suppression de l'environnement Python"

RAG_ENV="$HOME/rag_env"

if [[ -d "$RAG_ENV" ]]; then
    print_info "Suppression: $RAG_ENV"
    rm -rf "$RAG_ENV"
    print_success "Environnement Python supprimé"
else
    print_info "Environnement Python inexistant"
fi

# ============================================
# SUPPRESSION SCRIPTS
# ============================================

echo ""
print_step "Suppression des scripts"

SCRIPTS=(
    "$HOME/rag.py"
    "$HOME/rag_webui.py"
)

for script in "${SCRIPTS[@]}"; do
    if [[ -f "$script" ]]; then
        rm -f "$script"
        print_success "Supprimé: $(basename "$script")"
    fi
done

# ============================================
# SUPPRESSION INDEX FAISS
# ============================================

echo ""
print_step "Suppression de l'index FAISS"

FAISS_DB="$HOME/faiss_index"

if [[ -d "$FAISS_DB" ]]; then
    print_info "Suppression: $FAISS_DB"
    rm -rf "$FAISS_DB"
    print_success "Index FAISS supprimé"
else
    print_info "Index FAISS inexistant"
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
# NETTOYAGE FIREWALL
# ============================================

echo ""
print_step "Nettoyage du pare-feu"

if systemctl is-active --quiet firewalld; then
    print_info "Fermeture du port 5000..."
    sudo firewall-cmd --permanent --remove-port=5000/tcp 2>/dev/null || true
    sudo firewall-cmd --reload
    print_success "Port 5000 fermé"
else
    print_info "Firewalld inactif, rien à nettoyer"
fi

# ============================================
# NETTOYAGE PACKAGES (OPTIONNEL)
# ============================================

echo ""
print_step "Nettoyage des packages Python (optionnel)"

read -p "Désinstaller Python 3.14 et dépendances ? [y/N]: " REMOVE_PACKAGES

if [[ "$REMOVE_PACKAGES" =~ ^[Yy]$ ]]; then
    PACKAGES=(
        python3.14
        python3.14-devel
        fuse-sshfs
    )
    
    print_info "Désinstallation: ${PACKAGES[*]}"
    sudo dnf remove -y "${PACKAGES[@]}" 2>/dev/null || true
    
    print_info "Nettoyage cache DNF..."
    sudo dnf autoremove -y
    sudo dnf clean all
    
    print_success "Packages désinstallés"
else
    print_info "Packages conservés"
fi

# ============================================
# VÉRIFICATION NETTOYAGE
# ============================================

echo ""
print_step "Vérification du nettoyage"

REMAINING=0

# Check environnement
if [[ -d "$HOME/rag_env" ]]; then
    print_warning "~/rag_env existe encore"
    REMAINING=$((REMAINING+1))
fi

# Check scripts
if [[ -f "$HOME/rag.py" ]] || [[ -f "$HOME/rag_webui.py" ]]; then
    print_warning "Scripts RAG existent encore"
    REMAINING=$((REMAINING+1))
fi

# Check index
if [[ -d "$HOME/faiss_index" ]]; then
    print_warning "Index FAISS existe encore"
    REMAINING=$((REMAINING+1))
fi

# Check montage
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    print_warning "SSHFS encore monté"
    REMAINING=$((REMAINING+1))
fi

# Check processus
if pgrep -f "rag" >/dev/null; then
    print_warning "Processus RAG encore actifs"
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
echo "  ✓ Environnement Python (~/rag_env)"
echo "  ✓ Scripts RAG (~/rag.py, ~/rag_webui.py)"
echo "  ✓ Index FAISS (~/faiss_index)"
echo "  ✓ Point de montage SSHFS"
echo "  ✓ Configuration (~/.rag_vm_config)"
echo "  ✓ Règles pare-feu (port 5000)"
echo ""

if [[ "$REMOVE_PACKAGES" =~ ^[Yy]$ ]]; then
    echo "  ✓ Packages système désinstallés"
    echo ""
fi

echo "🔄 Pour réinstaller:"
echo "   ./setup_rag_vm.sh"
echo ""

print_success "Nettoyage terminé!"
