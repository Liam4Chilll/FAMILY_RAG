#!/bin/bash
#
# Script de management RAG Familial
# Gestion complète du système : start, stop, restart, status, backup
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

print_step() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_error() { echo -e "${RED}[ERREUR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[ATTENTION]${NC} $1"; }
print_metric() { echo -e "${CYAN}[MÉTRIQUE]${NC} $1"; }

# Banner
show_banner() {
    echo -e "${GREEN}"
    cat << "EOF"
╔═══════════════════════════════════════════════╗
║                                               ║
║      RAG FAMILIAL - GESTIONNAIRE             ║
║          Management & Monitoring              ║
║                                               ║
╚═══════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# ============================================
# DÉTECTION ENVIRONNEMENT
# ============================================

detect_environment() {
    if [[ "$(uname)" == "Darwin" ]]; then
        ENV="mac"
        ENV_NAME="Mac (Hôte)"
    elif [[ "$(uname)" == "Linux" ]]; then
        ENV="linux"
        ENV_NAME="VM Linux"
    else
        ENV="unknown"
        ENV_NAME="Inconnu"
    fi
}

# ============================================
# CHARGEMENT CONFIGURATION
# ============================================

load_config() {
    local config_loaded=0
    
    # Tentative de chargement des configs
    if [[ -f "$HOME/.rag_network_config" ]]; then
        source "$HOME/.rag_network_config"
        config_loaded=$((config_loaded + 1))
    fi
    
    if [[ -f "$HOME/.rag_ssh_config" ]]; then
        source "$HOME/.rag_ssh_config"
        config_loaded=$((config_loaded + 1))
    fi
    
    if [[ -f "$HOME/.rag_ollama_config" ]]; then
        source "$HOME/.rag_ollama_config"
        config_loaded=$((config_loaded + 1))
    fi
    
    if [[ -f "$HOME/.rag_config" ]]; then
        source "$HOME/.rag_config"
        config_loaded=$((config_loaded + 1))
    fi
    
    if [[ -f "$HOME/.rag_deployment_config" ]]; then
        source "$HOME/.rag_deployment_config"
        config_loaded=$((config_loaded + 1))
    fi
    
    if [[ $config_loaded -eq 0 ]]; then
        print_error "Aucune configuration trouvée"
        echo "Exécuter les scripts de setup avant d'utiliser le gestionnaire"
        exit 1
    fi
}

# ============================================
# FONCTIONS UTILITAIRES
# ============================================

# Traduire messages d'erreur techniques
translate_error() {
    local error_msg="$1"
    
    case "$error_msg" in
        *"Connection refused"*)
            echo "Connexion refusée - Le service n'est pas démarré ou le port est bloqué"
            ;;
        *"No route to host"*)
            echo "Hôte injoignable - Vérifier la configuration réseau"
            ;;
        *"Connection timed out"*)
            echo "Délai de connexion dépassé - Le service ne répond pas ou pare-feu actif"
            ;;
        *"Name or service not known"*)
            echo "Nom d'hôte inconnu - Vérifier la configuration DNS ou /etc/hosts"
            ;;
        *"Permission denied"*)
            echo "Permission refusée - Vérifier les droits d'accès ou authentification SSH"
            ;;
        *"Transport endpoint is not connected"*)
            echo "Point de montage SSHFS déconnecté - Remonter le système de fichiers"
            ;;
        *"cannot access"*)
            echo "Impossible d'accéder au fichier ou répertoire"
            ;;
        *"Module not found"*|*"ModuleNotFoundError"*)
            echo "Module Python manquant - Réinstaller l'environnement virtuel"
            ;;
        *)
            echo "$error_msg"
            ;;
    esac
}

# Formater taille en octets
format_size() {
    local size=$1
    if [[ $size -lt 1024 ]]; then
        echo "${size}B"
    elif [[ $size -lt 1048576 ]]; then
        echo "$((size / 1024))KB"
    elif [[ $size -lt 1073741824 ]]; then
        echo "$((size / 1048576))MB"
    else
        echo "$((size / 1073741824))GB"
    fi
}

# Calculer uptime formaté
format_uptime() {
    local seconds=$1
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))
    
    if [[ $days -gt 0 ]]; then
        echo "${days}j ${hours}h ${minutes}m"
    elif [[ $hours -gt 0 ]]; then
        echo "${hours}h ${minutes}m"
    else
        echo "${minutes}m"
    fi
}

# ============================================
# FONCTIONS OLLAMA (MAC)
# ============================================

ollama_status() {
    if [[ "$ENV" != "mac" ]]; then
        echo "N/A (pas sur Mac)"
        return 1
    fi
    
    if pgrep -x ollama > /dev/null 2>&1; then
        echo "running"
        return 0
    else
        echo "stopped"
        return 1
    fi
}

ollama_start() {
    if [[ "$ENV" != "mac" ]]; then
        print_error "Ollama ne peut être démarré que depuis le Mac"
        return 1
    fi
    
    print_step "Démarrage d'Ollama..."
    
    if [[ "$(ollama_status)" == "running" ]]; then
        print_warning "Ollama est déjà démarré"
        return 0
    fi
    
    # Charger le LaunchAgent
    if [[ -f "$HOME/Library/LaunchAgents/com.ollama.server.plist" ]]; then
        launchctl load "$HOME/Library/LaunchAgents/com.ollama.server.plist" 2>/dev/null || true
        sleep 3
    else
        print_error "LaunchAgent Ollama non trouvé"
        print_step "Lancement manuel d'Ollama..."
        nohup ollama serve > /tmp/ollama.log 2>&1 &
        sleep 3
    fi
    
    # Vérifier démarrage
    if curl -s --connect-timeout 5 http://localhost:${OLLAMA_PORT:-11434}/api/tags > /dev/null 2>&1; then
        print_success "Ollama démarré avec succès"
        return 0
    else
        print_error "Échec du démarrage d'Ollama"
        return 1
    fi
}

ollama_stop() {
    if [[ "$ENV" != "mac" ]]; then
        print_error "Ollama ne peut être arrêté que depuis le Mac"
        return 1
    fi
    
    print_step "Arrêt d'Ollama..."
    
    if [[ "$(ollama_status)" == "stopped" ]]; then
        print_warning "Ollama est déjà arrêté"
        return 0
    fi
    
    # Décharger le LaunchAgent
    if [[ -f "$HOME/Library/LaunchAgents/com.ollama.server.plist" ]]; then
        launchctl unload "$HOME/Library/LaunchAgents/com.ollama.server.plist" 2>/dev/null || true
    fi
    
    # Forcer l'arrêt si nécessaire
    pkill -9 ollama 2>/dev/null || true
    sleep 2
    
    if [[ "$(ollama_status)" == "stopped" ]]; then
        print_success "Ollama arrêté avec succès"
        return 0
    else
        print_error "Échec de l'arrêt d'Ollama"
        return 1
    fi
}

ollama_metrics() {
    if [[ "$ENV" != "mac" ]]; then
        echo "  Statut: N/A (pas sur Mac)"
        return
    fi
    
    local status=$(ollama_status)
    local url="http://${HOST_IP:-localhost}:${OLLAMA_PORT:-11434}"
    
    echo -e "${CYAN}━━━ OLLAMA (Mac) ━━━${NC}"
    
    if [[ "$status" == "running" ]]; then
        print_metric "Statut: ${GREEN}✓ Actif${NC}"
        print_metric "URL: $url"
        
        # Uptime du processus
        local pid=$(pgrep -x ollama)
        if [[ -n "$pid" ]]; then
            local start_time=$(ps -p $pid -o lstart= 2>/dev/null || echo "Inconnu")
            print_metric "Démarré: $start_time"
            
            # Utilisation mémoire
            local mem=$(ps -p $pid -o rss= 2>/dev/null || echo "0")
            print_metric "Mémoire: $(format_size $((mem * 1024)))"
        fi
        
        # Test connectivité
        if curl -s --connect-timeout 2 $url/api/tags > /dev/null 2>&1; then
            print_metric "Connectivité: ${GREEN}✓ OK${NC}"
            
            # Lister modèles
            local models=$(curl -s $url/api/tags 2>/dev/null | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | wc -l)
            print_metric "Modèles chargés: $models"
        else
            print_metric "Connectivité: ${RED}✗ Échec${NC}"
        fi
        
    else
        print_metric "Statut: ${RED}✗ Arrêté${NC}"
    fi
    echo ""
}

# ============================================
# FONCTIONS SSHFS (VM)
# ============================================

sshfs_status() {
    if [[ "$ENV" != "linux" ]]; then
        echo "N/A (pas sur VM)"
        return 1
    fi
    
    if mountpoint -q "$HOME/RAG" 2>/dev/null; then
        echo "mounted"
        return 0
    else
        echo "unmounted"
        return 1
    fi
}

sshfs_mount() {
    if [[ "$ENV" != "linux" ]]; then
        print_error "SSHFS ne peut être monté que depuis la VM"
        return 1
    fi
    
    print_step "Montage SSHFS..."
    
    if [[ "$(sshfs_status)" == "mounted" ]]; then
        print_warning "SSHFS est déjà monté"
        return 0
    fi
    
    # Vérifier configuration
    if [[ -z "$MAC_USER" ]] || [[ -z "$HOST_IP" ]] || [[ -z "$RAG_SOURCE_DIR" ]]; then
        print_error "Configuration manquante (MAC_USER, HOST_IP, RAG_SOURCE_DIR)"
        return 1
    fi
    
    # Créer point de montage
    mkdir -p "$HOME/RAG"
    
    # Test connexion SSH
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 $MAC_USER@$HOST_IP exit 2>/dev/null; then
        print_error "Connexion SSH vers le Mac impossible"
        echo "Vérifier: ssh $MAC_USER@$HOST_IP"
        return 1
    fi
    
    # Montage
    if sshfs $MAC_USER@$HOST_IP:$RAG_SOURCE_DIR $HOME/RAG -o follow_symlinks,reconnect 2>/dev/null; then
        print_success "SSHFS monté avec succès"
        return 0
    else
        print_error "Échec du montage SSHFS"
        local error=$(sshfs $MAC_USER@$HOST_IP:$RAG_SOURCE_DIR $HOME/RAG 2>&1 || true)
        echo "Erreur: $(translate_error "$error")"
        return 1
    fi
}

sshfs_unmount() {
    if [[ "$ENV" != "linux" ]]; then
        print_error "SSHFS ne peut être démonté que depuis la VM"
        return 1
    fi
    
    print_step "Démontage SSHFS..."
    
    if [[ "$(sshfs_status)" == "unmounted" ]]; then
        print_warning "SSHFS est déjà démonté"
        return 0
    fi
    
    if fusermount -u "$HOME/RAG" 2>/dev/null; then
        print_success "SSHFS démonté avec succès"
        return 0
    else
        print_warning "Tentative de démontage forcé..."
        fusermount -uz "$HOME/RAG" 2>/dev/null || true
        umount -l "$HOME/RAG" 2>/dev/null || true
        
        if [[ "$(sshfs_status)" == "unmounted" ]]; then
            print_success "SSHFS démonté (forcé)"
            return 0
        else
            print_error "Échec du démontage SSHFS"
            return 1
        fi
    fi
}

sshfs_metrics() {
    if [[ "$ENV" != "linux" ]]; then
        echo "  Statut: N/A (pas sur VM)"
        return
    fi
    
    echo -e "${CYAN}━━━ SSHFS (VM) ━━━${NC}"
    
    local status=$(sshfs_status)
    
    if [[ "$status" == "mounted" ]]; then
        print_metric "Statut: ${GREEN}✓ Monté${NC}"
        print_metric "Point de montage: $HOME/RAG"
        
        # Vérifier accessibilité
        if [[ -r "$HOME/RAG" ]]; then
            print_metric "Accessibilité: ${GREEN}✓ OK${NC}"
            
            # Compter fichiers
            local file_count=$(find "$HOME/RAG" -type f 2>/dev/null | wc -l || echo "0")
            print_metric "Fichiers: $file_count"
            
            # Espace utilisé
            local used=$(du -sh "$HOME/RAG" 2>/dev/null | awk '{print $1}' || echo "Inconnu")
            print_metric "Espace: $used"
        else
            print_metric "Accessibilité: ${RED}✗ Échec${NC}"
            print_warning "Le montage est présent mais inaccessible (connexion perdue?)"
        fi
        
    else
        print_metric "Statut: ${RED}✗ Non monté${NC}"
    fi
    echo ""
}

# ============================================
# FONCTIONS RAG PYTHON (VM)
# ============================================

rag_env_status() {
    if [[ "$ENV" != "linux" ]]; then
        echo "N/A (pas sur VM)"
        return 1
    fi
    
    if [[ -d "$HOME/rag_env" ]] && [[ -f "$HOME/rag_env/bin/activate" ]]; then
        echo "present"
        return 0
    else
        echo "missing"
        return 1
    fi
}

rag_env_metrics() {
    if [[ "$ENV" != "linux" ]]; then
        echo "  Statut: N/A (pas sur VM)"
        return
    fi
    
    echo -e "${CYAN}━━━ ENVIRONNEMENT PYTHON (VM) ━━━${NC}"
    
    if [[ "$(rag_env_status)" == "present" ]]; then
        print_metric "Statut: ${GREEN}✓ Présent${NC}"
        print_metric "Emplacement: $HOME/rag_env"
        
        # Version Python
        source "$HOME/rag_env/bin/activate" 2>/dev/null || true
        local py_version=$(python3 --version 2>/dev/null | awk '{print $2}' || echo "Inconnu")
        print_metric "Version Python: $py_version"
        
        # Packages installés
        local pkg_count=$(pip list 2>/dev/null | wc -l || echo "0")
        print_metric "Packages: $pkg_count"
        
        # Test imports critiques
        local import_test=$(python3 << 'EOFPY' 2>/dev/null
try:
    import langchain
    import faiss
    import ollama
    from langchain_ollama import OllamaEmbeddings, OllamaLLM
    print("OK")
except Exception as e:
    print(f"FAILED:{e}")
EOFPY
)
        
        if [[ "$import_test" == "OK" ]]; then
            print_metric "Imports: ${GREEN}✓ OK${NC}"
        else
            print_metric "Imports: ${RED}✗ Échec${NC}"
            echo "         Erreur: $(translate_error "$import_test")"
        fi
        
        deactivate 2>/dev/null || true
        
    else
        print_metric "Statut: ${RED}✗ Manquant${NC}"
        print_warning "Réinstaller avec: ./setup_rag.sh"
    fi
    echo ""
}

# ============================================
# FONCTIONS BASE VECTORIELLE (VM)
# ============================================

vector_db_metrics() {
    if [[ "$ENV" != "linux" ]]; then
        echo "  Statut: N/A (pas sur VM)"
        return
    fi
    
    echo -e "${CYAN}━━━ BASE VECTORIELLE FAISS (VM) ━━━${NC}"
    
    local db_path="$HOME/rag_system/faiss_db"
    
    if [[ -d "$db_path" ]]; then
        print_metric "Statut: ${GREEN}✓ Initialisée${NC}"
        print_metric "Emplacement: $db_path"
        
        # Taille base
        local size=$(du -sh "$db_path" 2>/dev/null | awk '{print $1}' || echo "Inconnu")
        print_metric "Taille: $size"
        
        # Date dernière indexation
        local index_file="$db_path/index.faiss"
        if [[ -f "$index_file" ]]; then
            local mod_date=$(stat -c %y "$index_file" 2>/dev/null || stat -f "%Sm" "$index_file" 2>/dev/null || echo "Inconnu")
            print_metric "Dernière indexation: $mod_date"
        fi
        
        # Compter chunks (approximatif via taille)
        if [[ -f "$index_file" ]]; then
            local file_size=$(stat -c %s "$index_file" 2>/dev/null || stat -f %z "$index_file" 2>/dev/null || echo "0")
            local approx_chunks=$((file_size / 4096))  # Approximation
            print_metric "Chunks (approx): ~$approx_chunks"
        fi
        
    else
        print_metric "Statut: ${RED}✗ Non initialisée${NC}"
        print_warning "Lancer: rag index"
    fi
    echo ""
}

# ============================================
# FONCTIONS CONNECTIVITÉ
# ============================================

connectivity_metrics() {
    echo -e "${CYAN}━━━ CONNECTIVITÉ ━━━${NC}"
    
    if [[ "$ENV" == "mac" ]]; then
        # Test depuis Mac vers VM
        if [[ -n "$VM_HOSTNAME" ]]; then
            if ssh -o BatchMode=yes -o ConnectTimeout=3 $VM_HOSTNAME exit 2>/dev/null; then
                print_metric "Mac → VM: ${GREEN}✓ OK${NC}"
            else
                print_metric "Mac → VM: ${RED}✗ Échec${NC}"
                local error=$(ssh -o BatchMode=yes -o ConnectTimeout=3 $VM_HOSTNAME exit 2>&1 || true)
                echo "         $(translate_error "$error")"
            fi
        fi
        
        # Test Ollama local
        local ollama_url="http://localhost:${OLLAMA_PORT:-11434}"
        if curl -s --connect-timeout 2 $ollama_url/api/tags > /dev/null 2>&1; then
            print_metric "Ollama local: ${GREEN}✓ OK${NC}"
        else
            print_metric "Ollama local: ${RED}✗ Échec${NC}"
        fi
        
    elif [[ "$ENV" == "linux" ]]; then
        # Test depuis VM vers Mac
        if [[ -n "$HOST_IP" ]] && [[ -n "$MAC_USER" ]]; then
            if ssh -o BatchMode=yes -o ConnectTimeout=3 $MAC_USER@$HOST_IP exit 2>/dev/null; then
                print_metric "VM → Mac SSH: ${GREEN}✓ OK${NC}"
            else
                print_metric "VM → Mac SSH: ${RED}✗ Échec${NC}"
            fi
        fi
        
        # Test Ollama distant
        if [[ -n "$OLLAMA_URL" ]]; then
            if curl -s --connect-timeout 3 $OLLAMA_URL/api/tags > /dev/null 2>&1; then
                print_metric "Ollama distant: ${GREEN}✓ OK${NC}"
            else
                print_metric "Ollama distant: ${RED}✗ Échec${NC}"
                print_warning "Vérifier: curl $OLLAMA_URL/api/tags"
            fi
        fi
    fi
    echo ""
}

# ============================================
# COMMANDE: START
# ============================================

cmd_start() {
    show_banner
    echo "Démarrage du système RAG..."
    echo ""
    
    if [[ "$ENV" == "mac" ]]; then
        print_step "Environnement: Mac (Hôte)"
        ollama_start
        
        echo ""
        print_step "Pour démarrer la VM, utiliser l'hyperviseur"
        
    elif [[ "$ENV" == "linux" ]]; then
        print_step "Environnement: VM Linux"
        
        # Monter SSHFS
        sshfs_mount
        
        echo ""
        print_success "Système RAG démarré sur la VM"
        print_step "Ollama doit être actif sur le Mac"
        
    fi
    
    echo ""
    print_step "Vérifier le statut complet avec: $0 status"
}

# ============================================
# COMMANDE: STOP
# ============================================

cmd_stop() {
    show_banner
    echo "Arrêt du système RAG..."
    echo ""
    
    if [[ "$ENV" == "mac" ]]; then
        print_step "Environnement: Mac (Hôte)"
        ollama_stop
        
        echo ""
        print_success "Ollama arrêté sur le Mac"
        print_step "Pour arrêter la VM, utiliser l'hyperviseur"
        
    elif [[ "$ENV" == "linux" ]]; then
        print_step "Environnement: VM Linux"
        
        # Démonter SSHFS
        sshfs_unmount
        
        echo ""
        print_success "SSHFS démonté - VM prête pour autre utilisation"
        
    fi
}

# ============================================
# COMMANDE: RESTART
# ============================================

cmd_restart() {
    show_banner
    echo "Redémarrage du système RAG..."
    echo ""
    
    cmd_stop
    echo ""
    sleep 2
    cmd_start
}

# ============================================
# COMMANDE: STATUS
# ============================================

cmd_status() {
    show_banner
    echo -e "${MAGENTA}═══════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}           STATUT GLOBAL DU SYSTÈME            ${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════${NC}"
    echo ""
    
    print_step "Environnement détecté: $ENV_NAME"
    echo ""
    
    # Métriques selon environnement
    if [[ "$ENV" == "mac" ]]; then
        ollama_metrics
        
        # Info VM si config disponible
        if [[ -n "$VM_HOSTNAME" ]]; then
            echo -e "${CYAN}━━━ VM DISTANTE ━━━${NC}"
            if ssh -o BatchMode=yes -o ConnectTimeout=3 $VM_HOSTNAME "echo 'ok'" > /dev/null 2>&1; then
                print_metric "Statut: ${GREEN}✓ Accessible${NC}"
                
                # Récupérer statut SSHFS depuis VM
                local vm_sshfs=$(ssh -o BatchMode=yes $VM_HOSTNAME "mountpoint -q ~/RAG && echo 'mounted' || echo 'unmounted'" 2>/dev/null || echo "unknown")
                if [[ "$vm_sshfs" == "mounted" ]]; then
                    print_metric "SSHFS VM: ${GREEN}✓ Monté${NC}"
                else
                    print_metric "SSHFS VM: ${RED}✗ Non monté${NC}"
                fi
            else
                print_metric "Statut: ${RED}✗ Inaccessible${NC}"
                print_warning "La VM est éteinte ou SSH non configuré"
            fi
            echo ""
        fi
        
    elif [[ "$ENV" == "linux" ]]; then
        sshfs_metrics
        rag_env_metrics
        vector_db_metrics
        
        # Info Mac si config disponible
        if [[ -n "$HOST_IP" ]]; then
            echo -e "${CYAN}━━━ MAC DISTANT ━━━${NC}"
            if ping -c 1 -W 2 $HOST_IP > /dev/null 2>&1; then
                print_metric "Statut réseau: ${GREEN}✓ Joignable${NC}"
                
                # Test Ollama
                if [[ -n "$OLLAMA_URL" ]]; then
                    if curl -s --connect-timeout 2 $OLLAMA_URL/api/tags > /dev/null 2>&1; then
                        print_metric "Ollama: ${GREEN}✓ Actif${NC}"
                    else
                        print_metric "Ollama: ${RED}✗ Inactif${NC}"
                    fi
                fi
            else
                print_metric "Statut réseau: ${RED}✗ Injoignable${NC}"
            fi
            echo ""
        fi
    fi
    
    # Connectivité globale
    connectivity_metrics
    
    # Résumé final avec score santé
    echo -e "${MAGENTA}═══════════════════════════════════════════════${NC}"
    calculate_health_score
    echo -e "${MAGENTA}═══════════════════════════════════════════════${NC}"
}

# ============================================
# CALCUL SCORE SANTÉ
# ============================================

calculate_health_score() {
    local score=0
    local max_score=0
    local issues=()
    
    if [[ "$ENV" == "mac" ]]; then
        max_score=20
        
        # Ollama (10 points)
        if [[ "$(ollama_status)" == "running" ]]; then
            score=$((score + 10))
        else
            issues+=("Ollama arrêté")
        fi
        
        # Connectivité VM (10 points)
        if [[ -n "$VM_HOSTNAME" ]]; then
            if ssh -o BatchMode=yes -o ConnectTimeout=3 $VM_HOSTNAME exit 2>/dev/null; then
                score=$((score + 10))
            else
                issues+=("VM inaccessible")
            fi
        else
            score=$((score + 10))  # Pas de VM configurée = OK
        fi
        
    elif [[ "$ENV" == "linux" ]]; then
        max_score=40
        
        # SSHFS (10 points)
        if [[ "$(sshfs_status)" == "mounted" ]]; then
            score=$((score + 10))
        else
            issues+=("SSHFS non monté")
        fi
        
        # Environnement Python (10 points)
        if [[ "$(rag_env_status)" == "present" ]]; then
            score=$((score + 10))
        else
            issues+=("Environnement Python manquant")
        fi
        
        # Connectivité Ollama (10 points)
        if [[ -n "$OLLAMA_URL" ]] && curl -s --connect-timeout 2 $OLLAMA_URL/api/tags > /dev/null 2>&1; then
            score=$((score + 10))
        else
            issues+=("Ollama inaccessible")
        fi
        
        # Base vectorielle (10 points)
        if [[ -d "$HOME/rag_system/faiss_db" ]]; then
            score=$((score + 10))
        else
            issues+=("Base vectorielle non initialisée")
        fi
    fi
    
    # Calculer pourcentage
    local percentage=$((score * 100 / max_score))
    
    # Affichage score avec couleur
    echo ""
    echo -e "${CYAN}SCORE DE SANTÉ: ${NC}"
    
    if [[ $percentage -ge 80 ]]; then
        echo -e "  ${GREEN}█████████${NC}░ $percentage% - Système opérationnel"
    elif [[ $percentage -ge 60 ]]; then
        echo -e "  ${YELLOW}███████${NC}░░░ $percentage% - Fonctionnel avec alertes"
    elif [[ $percentage -ge 40 ]]; then
        echo -e "  ${YELLOW}█████${NC}░░░░░ $percentage% - Dégradé"
    else
        echo -e "  ${RED}███${NC}░░░░░░░ $percentage% - Critique"
    fi
    
    # Afficher problèmes
    if [[ ${#issues[@]} -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}Problèmes détectés:${NC}"
        for issue in "${issues[@]}"; do
            echo "  • $issue"
        done
    fi
    
    echo ""
}

# ============================================
# COMMANDE: LOGS
# ============================================

cmd_logs() {
    show_banner
    
    if [[ "$ENV" == "mac" ]]; then
        echo "=== LOGS OLLAMA (Mac) ==="
        echo ""
        
        local log_file="$HOME/Library/Logs/ollama.log"
        local error_log="$HOME/Library/Logs/ollama_error.log"
        
        if [[ -f "$log_file" ]]; then
            echo "--- Dernières 20 lignes (stdout) ---"
            tail -20 "$log_file"
        else
            print_warning "Fichier log non trouvé: $log_file"
        fi
        
        echo ""
        
        if [[ -f "$error_log" ]] && [[ -s "$error_log" ]]; then
            echo "--- Erreurs récentes ---"
            tail -20 "$error_log"
        fi
        
    elif [[ "$ENV" == "linux" ]]; then
        echo "=== LOGS SYSTÈME (VM) ==="
        echo ""
        
        # Logs SSHFS
        echo "--- SSHFS ---"
        dmesg | grep -i fuse | tail -10 || echo "Aucun log FUSE récent"
        
        echo ""
        
        # Logs système
        echo "--- Système (journalctl) ---"
        journalctl -n 20 --no-pager 2>/dev/null || echo "journalctl non disponible"
    fi
}

# ============================================
# COMMANDE: BACKUP
# ============================================

cmd_backup() {
    show_banner
    
    if [[ "$ENV" != "linux" ]]; then
        print_error "La sauvegarde doit être lancée depuis la VM"
        exit 1
    fi
    
    print_step "Création d'une sauvegarde de la base vectorielle..."
    
    local backup_dir="$HOME/rag_backups"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="faiss_backup_$timestamp"
    
    mkdir -p "$backup_dir"
    
    if [[ -d "$HOME/rag_system/faiss_db" ]]; then
        if cp -r "$HOME/rag_system/faiss_db" "$backup_dir/$backup_name"; then
            local size=$(du -sh "$backup_dir/$backup_name" | awk '{print $1}')
            print_success "Sauvegarde créée: $backup_dir/$backup_name ($size)"
            
            # Garder seulement les 5 dernières sauvegardes
            local backup_count=$(ls -1 "$backup_dir" | wc -l)
            if [[ $backup_count -gt 5 ]]; then
                print_step "Nettoyage anciennes sauvegardes..."
                ls -1t "$backup_dir" | tail -n +6 | xargs -I {} rm -rf "$backup_dir/{}"
                print_success "Anciennes sauvegardes supprimées"
            fi
        else
            print_error "Échec de la sauvegarde"
            exit 1
        fi
    else
        print_error "Base vectorielle non trouvée"
        exit 1
    fi
}

# ============================================
# COMMANDE: HELP
# ============================================

cmd_help() {
    show_banner
    
    cat << EOF
UTILISATION:
  $0 <commande>

COMMANDES:
  start       Démarre le système RAG (Ollama sur Mac, SSHFS sur VM)
  stop        Arrête le système RAG (libère ressources)
  restart     Redémarre tous les composants
  status      Affiche le statut complet avec métriques et diagnostics
  logs        Affiche les logs système et erreurs
  backup      Sauvegarde la base vectorielle (VM uniquement)
  help        Affiche cette aide

EXEMPLES:
  # Démarrer le système
  $0 start

  # Vérifier le statut
  $0 status

  # Voir les logs en cas de problème
  $0 logs

  # Sauvegarder avant indexation majeure
  $0 backup

NOTES:
  - Sur Mac: Gère Ollama
  - Sur VM: Gère SSHFS, Python, base vectorielle
  - Le script détecte automatiquement l'environnement

EOF
}

# ============================================
# MAIN
# ============================================

main() {
    # Détecter environnement
    detect_environment
    
    # Charger configuration
    load_config
    
    # Parser commande
    local command="${1:-help}"
    
    case "$command" in
        start)
            cmd_start
            ;;
        stop)
            cmd_stop
            ;;
        restart)
            cmd_restart
            ;;
        status)
            cmd_status
            ;;
        logs)
            cmd_logs
            ;;
        backup)
            cmd_backup
            ;;
        help|--help|-h)
            cmd_help
            ;;
        *)
            print_error "Commande inconnue: $command"
            echo ""
            cmd_help
            exit 1
            ;;
    esac
}

# Exécution
main "$@"
