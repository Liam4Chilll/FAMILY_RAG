#!/bin/bash
#
# RAG Monitor - Supervision complète infrastructure RAG Fedora
# Usage: ./rag-monitor.sh [start|stop|status]
#

set -e

# ============================================
# COULEURS & STYLES
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ============================================
# CONFIGURATION
# ============================================

CONFIG_FILE="$HOME/.rag_fedora_config"
RAG_ENV="$HOME/rag_env"
WEBUI_SCRIPT="$HOME/rag_webui.py"
WEBUI_PID="/tmp/rag_webui.pid"

# Chargement config
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE" 2>/dev/null || true
else
    MOUNT_POINT="$HOME/RAG"
    FAISS_DB="$HOME/faiss_index"
    FEDORA_IP=$(hostname -I | awk '{print $1}')
    OLLAMA_HOST="http://172.16.220.1:11434"
fi

# ============================================
# FONCTIONS UTILITAIRES
# ============================================

print_header() {
    echo -e "${MAGENTA}${BOLD}"
    echo "╔════════════════════════════════════════════════════╗"
    echo "║                                                    ║"
    echo "║           RAG MONITOR - Fedora Client             ║"
    echo "║                                                    ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_section() {
    echo -e "\n${BLUE}${BOLD}▓▓▓ $1 ▓▓▓${NC}"
    echo -e "${DIM}────────────────────────────────────────────────────${NC}"
}

print_metric() {
    local label=$1
    local value=$2
    local status=$3
    
    case $status in
        ok)    icon="${GREEN}●${NC}" ;;
        warn)  icon="${YELLOW}●${NC}" ;;
        error) icon="${RED}●${NC}" ;;
        *)     icon="${CYAN}●${NC}" ;;
    esac
    
    printf "  ${icon} %-35s ${BOLD}%s${NC}\n" "$label" "$value"
}

get_webui_status() {
    if [[ -f "$WEBUI_PID" ]] && kill -0 "$(cat "$WEBUI_PID")" 2>/dev/null; then
        echo "running"
    elif pgrep -f "rag_webui.py" >/dev/null 2>&1; then
        echo "running"
    else
        echo "stopped"
    fi
}

# ============================================
# FONCTION START
# ============================================

start_rag() {
    print_section "DÉMARRAGE RAG WEBUI"
    
    if [[ "$(get_webui_status)" == "running" ]]; then
        print_metric "État" "Déjà actif" "warn"
        return 0
    fi
    
    # Vérification environnement
    if [[ ! -d "$RAG_ENV" ]]; then
        echo -e "${RED}✗ Environnement Python introuvable: $RAG_ENV${NC}"
        return 1
    fi
    
    if [[ ! -f "$WEBUI_SCRIPT" ]]; then
        echo -e "${RED}✗ Script WebUI introuvable: $WEBUI_SCRIPT${NC}"
        return 1
    fi
    
    print_metric "Démarrage WebUI" "En cours..." "info"
    
    # Activation environnement et démarrage
    source "$RAG_ENV/bin/activate"
    nohup python "$WEBUI_SCRIPT" > /tmp/rag_webui.log 2>&1 &
    echo $! > "$WEBUI_PID"
    
    # Attente démarrage
    for i in {1..15}; do
        if curl -s --connect-timeout 1 "http://127.0.0.1:5000" >/dev/null 2>&1; then
            echo -e "\n${GREEN}✓ WebUI démarrée avec succès${NC}"
            echo -e "${CYAN}  → Accès: http://${FEDORA_IP}:5000${NC}\n"
            return 0
        fi
        echo -ne "\r  Tentative $i/15..."
        sleep 1
    done
    
    echo -e "\n${RED}✗ Échec du démarrage${NC}"
    echo -e "${DIM}Consultez les logs: tail -f /tmp/rag_webui.log${NC}\n"
    return 1
}

# ============================================
# FONCTION STOP
# ============================================

stop_rag() {
    print_section "ARRÊT RAG WEBUI"
    
    if [[ "$(get_webui_status)" == "stopped" ]]; then
        print_metric "État" "Déjà arrêté" "warn"
        return 0
    fi
    
    print_metric "Arrêt WebUI" "En cours..." "info"
    
    # Kill via PID file
    if [[ -f "$WEBUI_PID" ]]; then
        PID=$(cat "$WEBUI_PID")
        kill -TERM "$PID" 2>/dev/null || true
        rm -f "$WEBUI_PID"
    fi
    
    # Kill via processus
    pkill -f "rag_webui.py" 2>/dev/null || true
    sleep 2
    
    if [[ "$(get_webui_status)" == "stopped" ]]; then
        echo -e "\n${GREEN}✓ WebUI arrêtée avec succès${NC}\n"
        return 0
    else
        echo -e "\n${RED}✗ Échec de l'arrêt${NC}\n"
        return 1
    fi
}

# ============================================
# FONCTION STATUS
# ============================================

show_status() {
    clear
    print_header
    
    # ========== ÉTAT DU SERVICE ==========
    print_section "SERVICE RAG WEBUI"
    
    STATUS=$(get_webui_status)
    if [[ "$STATUS" == "running" ]]; then
        PID=$(pgrep -f "rag_webui.py" | head -n1)
        UPTIME=$(ps -p "$PID" -o etime= 2>/dev/null | tr -d ' ' || echo "N/A")
        print_metric "État" "🟢 ACTIF (PID: $PID)" "ok"
        print_metric "Uptime" "$UPTIME" "ok"
    else
        print_metric "État" "🔴 ARRÊTÉ" "error"
    fi
    
    # Environnement Python
    if [[ -d "$RAG_ENV" ]]; then
        PY_VERSION=$("$RAG_ENV/bin/python" --version 2>&1 | cut -d' ' -f2)
        print_metric "Environnement Python" "✓ $PY_VERSION" "ok"
    else
        print_metric "Environnement Python" "✗ Introuvable" "error"
    fi
    
    # ========== CONNECTIVITÉ ==========
    print_section "CONNECTIVITÉ"
    
    # WebUI locale
    if curl -s --connect-timeout 2 "http://127.0.0.1:5000" >/dev/null 2>&1; then
        print_metric "WebUI Locale (127.0.0.1:5000)" "✓ Accessible" "ok"
    else
        print_metric "WebUI Locale" "✗ Inaccessible" "error"
    fi
    
    # WebUI réseau
    if [[ -n "$FEDORA_IP" ]]; then
        if curl -s --connect-timeout 2 "http://${FEDORA_IP}:5000" >/dev/null 2>&1; then
            print_metric "WebUI Réseau ($FEDORA_IP:5000)" "✓ Accessible" "ok"
        else
            print_metric "WebUI Réseau" "✗ Inaccessible" "warn"
        fi
    fi
    
    # Ollama distant
    if [[ -n "$OLLAMA_HOST" ]]; then
        if curl -s --connect-timeout 2 "$OLLAMA_HOST/api/tags" >/dev/null 2>&1; then
            print_metric "Ollama Distant ($OLLAMA_HOST)" "✓ Accessible" "ok"
            
            # Latence Ollama
            LATENCY=$(curl -o /dev/null -s -w '%{time_total}' "$OLLAMA_HOST/api/tags")
            LATENCY_MS=$(echo "$LATENCY * 1000" | bc | cut -d'.' -f1)
            
            if [[ $LATENCY_MS -lt 50 ]]; then
                print_metric "Latence Ollama" "${LATENCY_MS}ms" "ok"
            elif [[ $LATENCY_MS -lt 200 ]]; then
                print_metric "Latence Ollama" "${LATENCY_MS}ms" "warn"
            else
                print_metric "Latence Ollama" "${LATENCY_MS}ms" "error"
            fi
        else
            print_metric "Ollama Distant" "✗ Inaccessible" "error"
        fi
    fi
    
    # Port listening
    if ss -tulpn 2>/dev/null | grep -q ":5000"; then
        print_metric "Port 5000" "✓ En écoute" "ok"
    else
        print_metric "Port 5000" "✗ Non utilisé" "error"
    fi
    
    # ========== MONTAGE SMB ==========
    print_section "MONTAGE DOCUMENTS"
    
    if [[ -d "$MOUNT_POINT" ]]; then
        print_metric "Point de montage" "$MOUNT_POINT" "ok"
        
        if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
            print_metric "État montage" "✓ Monté" "ok"
            
            DOC_COUNT=$(find "$MOUNT_POINT" -type f 2>/dev/null | wc -l | tr -d ' ')
            print_metric "Fichiers accessibles" "$DOC_COUNT" "ok"
            
            MOUNT_SIZE=$(du -sh "$MOUNT_POINT" 2>/dev/null | cut -f1)
            print_metric "Taille" "$MOUNT_SIZE" "ok"
        else
            print_metric "État montage" "✗ Non monté" "error"
        fi
    else
        print_metric "Point de montage" "✗ Introuvable" "error"
    fi
    
    # ========== INDEX FAISS ==========
    print_section "BASE VECTORIELLE FAISS"
    
    if [[ -d "$FAISS_DB" ]]; then
        print_metric "Chemin index" "$FAISS_DB" "ok"
        
        INDEX_SIZE=$(du -sh "$FAISS_DB" 2>/dev/null | cut -f1)
        print_metric "Taille index" "$INDEX_SIZE" "ok"
        
        # Compte fichiers index
        INDEX_FILES=$(find "$FAISS_DB" -type f 2>/dev/null | wc -l | tr -d ' ')
        print_metric "Fichiers index" "$INDEX_FILES" "ok"
        
        # Date dernière modification
        LAST_MOD=$(stat -c %y "$FAISS_DB" 2>/dev/null | cut -d' ' -f1)
        print_metric "Dernière indexation" "$LAST_MOD" "ok"
    else
        print_metric "Index FAISS" "✗ Non créé" "warn"
        echo -e "    ${DIM}Créez l'index: ~/rag_env/bin/rag index${NC}"
    fi
    
    # ========== PACKAGES PYTHON ==========
    print_section "DÉPENDANCES PYTHON"
    
    if [[ -d "$RAG_ENV" ]]; then
        source "$RAG_ENV/bin/activate" 2>/dev/null
        
        # Packages critiques
        CRITICAL_PACKAGES=(
            "langchain"
            "langchain-community"
            "faiss-cpu"
            "flask"
            "pypdf"
        )
        
        for pkg in "${CRITICAL_PACKAGES[@]}"; do
            if pip show "$pkg" >/dev/null 2>&1; then
                VERSION=$(pip show "$pkg" 2>/dev/null | grep "Version:" | cut -d' ' -f2)
                print_metric "$pkg" "✓ $VERSION" "ok"
            else
                print_metric "$pkg" "✗ Non installé" "error"
            fi
        done
    fi
    
    # ========== RESSOURCES SYSTÈME ==========
    print_section "RESSOURCES SYSTÈME"
    
    # CPU WebUI
    if [[ "$STATUS" == "running" ]]; then
        PID=$(pgrep -f "rag_webui.py" | head -n1)
        CPU_USAGE=$(ps -p "$PID" -o %cpu= 2>/dev/null | tr -d ' ' || echo "0")
        CPU_INT=$(echo "$CPU_USAGE" | cut -d'.' -f1)
        
        if [[ $CPU_INT -lt 20 ]]; then
            print_metric "CPU WebUI" "${CPU_USAGE}%" "ok"
        elif [[ $CPU_INT -lt 50 ]]; then
            print_metric "CPU WebUI" "${CPU_USAGE}%" "warn"
        else
            print_metric "CPU WebUI" "${CPU_USAGE}%" "error"
        fi
        
        # RAM WebUI
        MEM_KB=$(ps -p "$PID" -o rss= 2>/dev/null | tr -d ' ' || echo "0")
        MEM_MB=$((MEM_KB / 1024))
        
        if [[ $MEM_MB -lt 512 ]]; then
            print_metric "RAM WebUI" "${MEM_MB}MB" "ok"
        elif [[ $MEM_MB -lt 1024 ]]; then
            print_metric "RAM WebUI" "${MEM_MB}MB" "warn"
        else
            print_metric "RAM WebUI" "${MEM_MB}MB" "error"
        fi
    fi
    
    # RAM système
    MEM_TOTAL=$(free -m | awk 'NR==2{print $2}')
    MEM_USED=$(free -m | awk 'NR==2{print $3}')
    MEM_PERCENT=$(( (MEM_USED * 100) / MEM_TOTAL ))
    
    if [[ $MEM_PERCENT -lt 70 ]]; then
        print_metric "RAM Système" "${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PERCENT}%)" "ok"
    elif [[ $MEM_PERCENT -lt 90 ]]; then
        print_metric "RAM Système" "${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PERCENT}%)" "warn"
    else
        print_metric "RAM Système" "${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PERCENT}%)" "error"
    fi
    
    # Espace disque
    DISK_USAGE=$(df -h "$HOME" | awk 'NR==2{print $5}' | tr -d '%')
    DISK_AVAIL=$(df -h "$HOME" | awk 'NR==2{print $4}')
    
    if [[ $DISK_USAGE -lt 80 ]]; then
        print_metric "Espace disque disponible" "$DISK_AVAIL" "ok"
    elif [[ $DISK_USAGE -lt 90 ]]; then
        print_metric "Espace disque disponible" "$DISK_AVAIL" "warn"
    else
        print_metric "Espace disque disponible" "$DISK_AVAIL" "error"
    fi
    
    # ========== LOGS & MONITORING ==========
    print_section "LOGS"
    
    if [[ -f "/tmp/rag_webui.log" ]]; then
        LOG_SIZE=$(du -h /tmp/rag_webui.log 2>/dev/null | cut -f1)
        LOG_LINES=$(wc -l < /tmp/rag_webui.log 2>/dev/null | tr -d ' ')
        print_metric "Log WebUI" "$LOG_SIZE ($LOG_LINES lignes)" "ok"
        
        # Erreurs récentes
        ERROR_COUNT=$(tail -100 /tmp/rag_webui.log 2>/dev/null | grep -ci "error\|exception\|failed" || echo "0")
        if [[ $ERROR_COUNT -eq 0 ]]; then
            print_metric "Erreurs récentes (100 lignes)" "Aucune" "ok"
        elif [[ $ERROR_COUNT -lt 5 ]]; then
            print_metric "Erreurs récentes (100 lignes)" "$ERROR_COUNT" "warn"
        else
            print_metric "Erreurs récentes (100 lignes)" "$ERROR_COUNT" "error"
        fi
    fi
    
    # ========== PERFORMANCES RAG ==========
    print_section "PERFORMANCES RAG"
    
    if [[ -d "$FAISS_DB" ]] && [[ "$STATUS" == "running" ]]; then
        # Estimation nombre de chunks
        if [[ -f "$FAISS_DB/index.faiss" ]]; then
            FAISS_SIZE=$(stat -c %s "$FAISS_DB/index.faiss" 2>/dev/null || echo "0")
            CHUNKS_EST=$((FAISS_SIZE / 4096))  # Estimation approximative
            print_metric "Chunks indexés (estimation)" "$CHUNKS_EST" "ok"
        fi
        
        # Test requête simple
        if curl -s --connect-timeout 2 "http://127.0.0.1:5000" >/dev/null 2>&1; then
            echo -e "  ${DIM}Test requête en cours...${NC}"
            
            START=$(date +%s%N)
            curl -s -X POST "http://127.0.0.1:5000/query" \
                -H "Content-Type: application/json" \
                -d '{"question":"test"}' \
                --max-time 30 >/dev/null 2>&1
            END=$(date +%s%N)
            
            DURATION_MS=$(( (END - START) / 1000000 ))
            
            if [[ $DURATION_MS -lt 2000 ]]; then
                print_metric "Temps réponse (test)" "${DURATION_MS}ms" "ok"
            elif [[ $DURATION_MS -lt 5000 ]]; then
                print_metric "Temps réponse (test)" "${DURATION_MS}ms" "warn"
            else
                print_metric "Temps réponse (test)" "${DURATION_MS}ms" "error"
            fi
        fi
    fi
    
    # ========== PARE-FEU ==========
    print_section "SÉCURITÉ & RÉSEAU"
    
    if systemctl is-active --quiet firewalld; then
        print_metric "Firewalld" "✓ Actif" "ok"
        
        if firewall-cmd --list-ports 2>/dev/null | grep -q "5000/tcp"; then
            print_metric "Port 5000 ouvert" "✓ Oui" "ok"
        else
            print_metric "Port 5000 ouvert" "✗ Non" "warn"
        fi
    else
        print_metric "Firewalld" "Inactif" "info"
    fi
    
    # ========== RECOMMANDATIONS ==========
    print_section "RECOMMANDATIONS"
    
    WARNINGS=()
    
    if [[ "$STATUS" == "stopped" ]]; then
        WARNINGS+=("WebUI arrêtée - Exécutez: $0 start")
    fi
    
    if [[ ! -d "$FAISS_DB" ]]; then
        WARNINGS+=("Index FAISS absent - Créez-le: ~/rag_env/bin/rag index")
    fi
    
    if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        WARNINGS+=("Documents non montés - Vérifiez le montage SMB")
    fi
    
    if ! curl -s --connect-timeout 2 "$OLLAMA_HOST/api/tags" >/dev/null 2>&1; then
        WARNINGS+=("Ollama distant inaccessible - Vérifiez la connectivité réseau")
    fi
    
    if [[ ${#WARNINGS[@]} -eq 0 ]]; then
        echo -e "  ${GREEN}✓ Tout fonctionne correctement${NC}"
    else
        for warning in "${WARNINGS[@]}"; do
            echo -e "  ${YELLOW}⚠${NC} $warning"
        done
    fi
    
    # ========== FOOTER ==========
    echo -e "\n${DIM}────────────────────────────────────────────────────${NC}"
    echo -e "${DIM}Généré le: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${DIM}Commandes: $0 [start|stop|status]${NC}"
    if [[ -n "$FEDORA_IP" ]] && [[ "$STATUS" == "running" ]]; then
        echo -e "${DIM}WebUI: ${CYAN}http://${FEDORA_IP}:5000${NC}"
    fi
    echo ""
}

# ============================================
# MAIN
# ============================================

case "${1:-status}" in
    start)
        start_rag
        ;;
    stop)
        stop_rag
        ;;
    status)
        show_status
        ;;
    restart)
        stop_rag
        sleep 2
        start_rag
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
