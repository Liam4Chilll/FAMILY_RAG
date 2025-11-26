#!/bin/bash
#
# Nettoyage complet de l'installation RAG sur VM Fedora
# Supprime tous les éléments créés par setup-fedora.sh
# Version FINALE - Sans erreurs d'affichage
#

set -e

# ============================================
# COULEURS
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_info() { echo -e "${CYAN}[→]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

# ============================================
# BANNER
# ============================================

clear
echo -e "${RED}"
cat << "EOF"
╔═══════════════════════════════════════════════╗
║                                               ║
║        NETTOYAGE RAG - VM FEDORA             ║
║          ⚠️  SUPPRESSION COMPLÈTE            ║
║                                               ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# ============================================
# CHARGEMENT CONFIG
# ============================================

CONFIG_FILE="$HOME/.rag_fedora_config"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE" 2>/dev/null || true
    print_info "Configuration chargée"
else
    print_warning "Aucune configuration trouvée, valeurs par défaut"
    MOUNT_POINT="$HOME/RAG"
    RAG_ENV="$HOME/rag_env"
    FAISS_DB="$HOME/faiss_index"
fi

# ============================================
# AVERTISSEMENT
# ============================================

echo ""
print_warning "Ce script va supprimer:"
echo ""
echo "  📁 Environnement Python    : ${RAG_ENV:-~/rag_env}"
echo "  📄 Scripts RAG             : ~/rag.py, ~/rag_webui.py"
echo "  💾 Index FAISS             : ${FAISS_DB:-~/faiss_index}"
echo "  🔗 Point de montage SMB    : ${MOUNT_POINT:-~/RAG}"
echo "  ⚙️  Configuration           : ~/.rag_fedora_config"
echo "  🔥 Règles pare-feu         : Port 5000"
echo ""
read -p "Confirmer la suppression ? [y/N]: " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    print_info "Nettoyage annulé"
    exit 0
fi

# ============================================
# ARRÊT PROCESSUS
# ============================================

echo ""
print_step "Arrêt des processus RAG"

# Arrêt Flask
if pgrep -f "rag_webui.py" >/dev/null 2>&1; then
    print_info "Arrêt WebUI Flask..."
    pkill -f "rag_webui.py" 2>/dev/null || true
    sleep 1
    print_success "WebUI arrêtée"
else
    print_info "Aucun processus WebUI actif"
fi

# Arrêt autres processus Python RAG
if pgrep -f "rag.py" >/dev/null 2>&1; then
    print_info "Arrêt processus RAG..."
    pkill -f "rag.py" 2>/dev/null || true
    sleep 1
    print_success "Processus RAG arrêtés"
else
    print_info "Aucun processus RAG actif"
fi

# ============================================
# DÉMONTAGE SMB
# ============================================

echo ""
print_step "Démontage SMB"

if [[ -n "$MOUNT_POINT" ]] && [[ -d "$MOUNT_POINT" ]]; then
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        print_info "Démontage: $MOUNT_POINT"
        
        # Tentative démontage normal
        if sudo umount "$MOUNT_POINT" 2>/dev/null; then
            print_success "SMB démonté (umount)"
        else
            print_warning "Démontage normal échoué, tentative force..."
            
            # Force avec lazy unmount
            if sudo umount -l "$MOUNT_POINT" 2>/dev/null; then
                print_success "SMB démonté (umount -l)"
            else
                print_warning "Démontage impossible, le point sera supprimé quand même"
            fi
        fi
        
        sleep 2
    else
        print_info "SMB non monté"
    fi
    
    # Suppression dossier (seulement s'il est vide ou si force)
    if [[ -d "$MOUNT_POINT" ]]; then
        # Vérifier s'il reste des fichiers
        if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
            print_warning "Point de montage toujours actif, conservation du dossier"
        else
            # Supprimer uniquement si vide ou forcer
            if [[ -z "$(ls -A "$MOUNT_POINT" 2>/dev/null)" ]]; then
                rm -rf "$MOUNT_POINT" 2>/dev/null || true
                print_success "Dossier supprimé: $MOUNT_POINT"
            else
                read -p "Le dossier $MOUNT_POINT contient des fichiers. Supprimer quand même ? [y/N]: " FORCE_RM
                if [[ "$FORCE_RM" =~ ^[Yy]$ ]]; then
                    rm -rf "$MOUNT_POINT" 2>/dev/null || true
                    print_success "Dossier supprimé (forcé): $MOUNT_POINT"
                else
                    print_info "Dossier conservé: $MOUNT_POINT"
                fi
            fi
        fi
    fi
else
    print_info "Pas de point de montage à nettoyer"
fi

# ============================================
# NETTOYAGE FSTAB
# ============================================

echo ""
print_step "Nettoyage /etc/fstab"

if [[ -f /etc/fstab ]] && grep -q "$MOUNT_POINT" /etc/fstab 2>/dev/null; then
    print_info "Entrée fstab détectée pour $MOUNT_POINT"
    
    # Backup
    sudo cp /etc/fstab /etc/fstab.backup.cleanup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    
    # Suppression de la ligne
    sudo sed -i "\|$MOUNT_POINT|d" /etc/fstab 2>/dev/null || true
    
    print_success "Entrée fstab supprimée"
else
    print_info "Aucune entrée fstab à nettoyer"
fi

# ============================================
# SUPPRESSION ENVIRONNEMENT PYTHON
# ============================================

echo ""
print_step "Suppression de l'environnement Python"

if [[ -n "$RAG_ENV" ]] && [[ -d "$RAG_ENV" ]]; then
    print_info "Suppression: $RAG_ENV"
    
    # Désactiver si actif
    if [[ "$VIRTUAL_ENV" == "$RAG_ENV" ]]; then
        deactivate 2>/dev/null || true
    fi
    
    rm -rf "$RAG_ENV" 2>/dev/null || true
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
    "$HOME/simple_index.py"
    "$HOME/fix-langchain.sh"
    "$HOME/create-rag-env.sh"
)

REMOVED_COUNT=0

for script in "${SCRIPTS[@]}"; do
    if [[ -f "$script" ]]; then
        rm -f "$script" 2>/dev/null || true
        print_success "Supprimé: $(basename "$script")"
        REMOVED_COUNT=$((REMOVED_COUNT + 1))
    fi
done

if [[ $REMOVED_COUNT -eq 0 ]]; then
    print_info "Aucun script à supprimer"
else
    print_success "$REMOVED_COUNT script(s) supprimé(s)"
fi

# ============================================
# SUPPRESSION INDEX FAISS
# ============================================

echo ""
print_step "Suppression de l'index FAISS"

if [[ -n "$FAISS_DB" ]] && [[ -d "$FAISS_DB" ]]; then
    # Afficher taille avant suppression
    SIZE=$(du -sh "$FAISS_DB" 2>/dev/null | cut -f1) || SIZE="?"
    print_info "Suppression: $FAISS_DB (Taille: $SIZE)"
    
    rm -rf "$FAISS_DB" 2>/dev/null || true
    print_success "Index FAISS supprimé"
else
    print_info "Index FAISS inexistant"
fi

# ============================================
# SUPPRESSION CREDENTIALS SMB
# ============================================

echo ""
print_step "Suppression des credentials SMB"

SMB_CREDS="$HOME/.smbcredentials"

if [[ -f "$SMB_CREDS" ]]; then
    read -p "Supprimer les credentials SMB (~/.smbcredentials) ? [y/N]: " REMOVE_CREDS
    
    if [[ "$REMOVE_CREDS" =~ ^[Yy]$ ]]; then
        rm -f "$SMB_CREDS" 2>/dev/null || true
        print_success "Credentials SMB supprimés"
    else
        print_info "Credentials SMB conservés"
    fi
else
    print_info "Aucun fichier credentials à supprimer"
fi

# ============================================
# SUPPRESSION CONFIGURATION
# ============================================

echo ""
print_step "Suppression de la configuration"

if [[ -f "$CONFIG_FILE" ]]; then
    rm -f "$CONFIG_FILE" 2>/dev/null || true
    print_success "Configuration supprimée"
else
    print_info "Aucune configuration à supprimer"
fi

# ============================================
# NETTOYAGE FIREWALL
# ============================================

echo ""
print_step "Nettoyage du pare-feu"

if systemctl is-active --quiet firewalld 2>/dev/null; then
    print_info "Fermeture du port 5000..."
    
    sudo firewall-cmd --permanent --remove-port=5000/tcp 2>/dev/null || true
    sudo firewall-cmd --reload 2>/dev/null || true
    
    print_success "Port 5000 fermé"
else
    print_info "Firewalld inactif, rien à nettoyer"
fi

# ============================================
# NETTOYAGE PACKAGES (OPTIONNEL)
# ============================================

echo ""
print_step "Nettoyage des packages Python (optionnel)"

read -p "Désinstaller les packages système Python/CIFS ? [y/N]: " REMOVE_PACKAGES

if [[ "$REMOVE_PACKAGES" =~ ^[Yy]$ ]]; then
    PACKAGES=(
        python3.13
        python3.13-devel
        cifs-utils
        samba-client
    )
    
    print_info "Désinstallation: ${PACKAGES[*]}"
    sudo dnf remove -y "${PACKAGES[@]}" 2>/dev/null || true
    
    print_info "Nettoyage cache DNF..."
    sudo dnf autoremove -y 2>/dev/null || true
    sudo dnf clean all 2>/dev/null || true
    
    print_success "Packages désinstallés"
else
    print_info "Packages système conservés"
fi

# ============================================
# VÉRIFICATION NETTOYAGE
# ============================================

echo ""
print_step "Vérification du nettoyage"

REMAINING=0

# Check environnement
if [[ -d "${RAG_ENV:-$HOME/rag_env}" ]]; then
    print_warning "~/rag_env existe encore"
    REMAINING=$((REMAINING + 1))
fi

# Check scripts
if [[ -f "$HOME/rag.py" ]] || [[ -f "$HOME/rag_webui.py" ]]; then
    print_warning "Scripts RAG existent encore"
    REMAINING=$((REMAINING + 1))
fi

# Check index
if [[ -d "${FAISS_DB:-$HOME/faiss_index}" ]]; then
    print_warning "Index FAISS existe encore"
    REMAINING=$((REMAINING + 1))
fi

# Check montage
if mountpoint -q "${MOUNT_POINT:-$HOME/RAG}" 2>/dev/null; then
    print_warning "SMB encore monté"
    REMAINING=$((REMAINING + 1))
fi

# Check processus
if pgrep -f "rag" >/dev/null 2>&1; then
    print_warning "Processus RAG encore actifs"
    REMAINING=$((REMAINING + 1))
fi

echo ""

if [[ $REMAINING -eq 0 ]]; then
    print_success "Nettoyage complet vérifié ✓"
else
    print_warning "$REMAINING élément(s) restant(s) - Peut nécessiter intervention manuelle"
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
echo "  ✓ Environnement Python    (~/rag_env)"
echo "  ✓ Scripts RAG             (~/rag.py, ~/rag_webui.py)"
echo "  ✓ Index FAISS             (~/faiss_index)"
echo "  ✓ Point de montage SMB"
echo "  ✓ Configuration           (~/.rag_fedora_config)"
echo "  ✓ Règles pare-feu         (port 5000)"

if [[ "$REMOVE_CREDS" =~ ^[Yy]$ ]]; then
    echo "  ✓ Credentials SMB         (~/.smbcredentials)"
fi

if [[ "$REMOVE_PACKAGES" =~ ^[Yy]$ ]]; then
    echo "  ✓ Packages système désinstallés"
fi

echo ""

if [[ $REMAINING -gt 0 ]]; then
    echo "⚠️  Nettoyage manuel requis pour $REMAINING élément(s)"
    echo ""
    echo "Commandes de nettoyage manuel:"
    echo ""
    
    if [[ -d "${RAG_ENV:-$HOME/rag_env}" ]]; then
        echo "  rm -rf ~/rag_env"
    fi
    
    if mountpoint -q "${MOUNT_POINT:-$HOME/RAG}" 2>/dev/null; then
        echo "  sudo umount -l ${MOUNT_POINT:-~/RAG}"
        echo "  rmdir ${MOUNT_POINT:-~/RAG}"
    fi
    
    if pgrep -f "rag" >/dev/null 2>&1; then
        echo "  pkill -9 -f rag"
    fi
    
    echo ""
fi

echo "🔄 Pour réinstaller:"
echo "   ./setup-fedora.sh"
echo ""

print_success "Nettoyage terminé!"

# ============================================
# STATISTIQUES FINALES
# ============================================

echo ""
print_info "Statistiques:"

# Espace disque libéré (approximatif)
echo -n "  Espace disque libéré : "
FREED_SPACE=0

if [[ ! -d "${RAG_ENV:-$HOME/rag_env}" ]]; then
    FREED_SPACE=$((FREED_SPACE + 200))  # ~200MB pour Python env
fi

if [[ ! -d "${FAISS_DB:-$HOME/faiss_index}" ]]; then
    FREED_SPACE=$((FREED_SPACE + 50))   # Variable selon index
fi

echo "${FREED_SPACE}+ MB"

# Temps d'exécution
echo "  Script cleanup     : $(date)"

echo ""
