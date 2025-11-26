#!/bin/bash
#
# Ollama Monitor - Supervision complète infrastructure LLM macOS
# Usage: ./ollama-monitor.sh [start|stop|status]
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

CONFIG_FILE="$HOME/.rag_ollama_config"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/com.ollama.ollama.plist"
LOG_FILE="$HOME/Library/Logs/ollama.log"
ERROR_LOG="$HOME/Library/Logs/ollama.error.log"

# Chargement config
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE" 2>/dev/null || true
else
    MAC_IP=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -n1)
    SHARED_DIR="$HOME/RAG_Data"
fi

# ============================================
# FONCTIONS UTILITAIRES
# ============================================

print_header() {
    echo -e "${CYAN}${BOLD}"
    echo "╔════════════════════════════════════════════════════╗"
    echo "║                                                    ║"
    echo "║          OLLAMA MONITOR - macOS LLM               ║"
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
    
    printf "  ${icon} %-30s ${BOLD}%s${NC}\n" "$label" "$value"
}

get_ollama_status() {
    if pgrep -x "ollama" >/dev/null 2>&1; then
        echo "running"
    else
        echo "stopped"
    fi
}

human_readable_size() {
    local bytes=$1
    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes}B"
    elif [[ $bytes -lt 1048576 ]]; then
        echo "$(bc <<< "scale=1; $bytes/1024")K"
    elif [[ $bytes -lt 1073741824 ]]; then
        echo "$(bc <<< "scale=1; $bytes/1048576")M"
    else
        echo "$(bc <<< "scale=2; $bytes/1073741824")G"
    fi
}

# ============================================
# FONCTION START
# ============================================

start_ollama() {
    print_section "DÉMARRAGE OLLAMA"
    
    if [[ "$(get_ollama_status)" == "running" ]]; then
        print_metric "État" "Déjà actif" "warn"
        return 0
    fi
    
    print_metric "Démarrage service" "En cours..." "info"
    
    if [[ -f "$LAUNCHD_PLIST" ]]; then
        launchctl load "$LAUNCHD_PLIST" 2>/dev/null
    else
        echo -e "${YELLOW}⚠ LaunchAgent introuvable, démarrage manuel...${NC}"
        OLLAMA_HOST=0.0.0.0:11434 nohup ollama serve > "$LOG_FILE" 2>&1 &
    fi
    
    # Attente démarrage
    for i in {1..15}; do
        if curl -s --connect-timeout 1 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
            echo -e "\n${GREEN}✓ Ollama démarré avec succès${NC}\n"
            return 0
        fi
        echo -ne "\r  Tentative $i/15..."
        sleep 1
    done
    
    echo -e "\n${RED}✗ Échec du démarrage${NC}"
    echo -e "${DIM}Consultez les logs: tail -f $ERROR_LOG${NC}\n"
    return 1
}

# ============================================
# FONCTION STOP
# ============================================

stop_ollama() {
    print_section "ARRÊT OLLAMA"
    
    if [[ "$(get_ollama_status)" == "stopped" ]]; then
        print_metric "État" "Déjà arrêté" "warn"
        return 0
    fi
    
    print_metric "Arrêt service" "En cours..." "info"
    
    # Arrêt LaunchAgent
    if [[ -f "$LAUNCHD_PLIST" ]]; then
        launchctl unload "$LAUNCHD_PLIST" 2>/dev/null || true
    fi
    
    # Kill processus
    pkill -TERM ollama 2>/dev/null || true
    sleep 2
    
    # Force kill si nécessaire
    if pgrep -x "ollama" >/dev/null; then
        pkill -KILL ollama 2>/dev/null || true
    fi
    
    if [[ "$(get_ollama_status)" == "stopped" ]]; then
        echo -e "\n${GREEN}✓ Ollama arrêté avec succès${NC}\n"
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
    print_section "SERVICE OLLAMA"
    
    STATUS=$(get_ollama_status)
    if [[ "$STATUS" == "running" ]]; then
        PID=$(pgrep -x ollama)
        UPTIME=$(ps -p "$PID" -o etime= | tr -d ' ')
        print_metric "État" "🟢 ACTIF (PID: $PID)" "ok"
        print_metric "Uptime" "$UPTIME" "ok"
    else
        print_metric "État" "🔴 ARRÊTÉ" "error"
    fi
    
    # LaunchAgent
    if launchctl list | grep -q "com.ollama.ollama"; then
        print_metric "LaunchAgent" "✓ Chargé" "ok"
    else
        print_metric "LaunchAgent" "✗ Non chargé" "warn"
    fi
    
    # ========== API & RÉSEAU ==========
    print_section "CONNECTIVITÉ"
    
    # Test API locale
    if curl -s --connect-timeout 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
        print_metric "API Locale (127.0.0.1:11434)" "✓ Accessible" "ok"
        
        # Latence API
        LATENCY=$(curl -o /dev/null -s -w '%{time_total}' http://127.0.0.1:11434/api/tags)
        LATENCY_MS=$(echo "$LATENCY * 1000" | bc | cut -d'.' -f1)
        
        if [[ $LATENCY_MS -lt 100 ]]; then
            print_metric "Latence API" "${LATENCY_MS}ms" "ok"
        elif [[ $LATENCY_MS -lt 500 ]]; then
            print_metric "Latence API" "${LATENCY_MS}ms" "warn"
        else
            print_metric "Latence API" "${LATENCY_MS}ms" "error"
        fi
    else
        print_metric "API Locale" "✗ Inaccessible" "error"
    fi
    
    # Test API réseau
    if [[ -n "$MAC_IP" ]]; then
        if curl -s --connect-timeout 2 "http://$MAC_IP:11434/api/tags" >/dev/null 2>&1; then
            print_metric "API Réseau ($MAC_IP:11434)" "✓ Accessible" "ok"
        else
            print_metric "API Réseau ($MAC_IP:11434)" "✗ Inaccessible" "warn"
        fi
    fi
    
    # Port listening
    if lsof -i :11434 >/dev/null 2>&1; then
        LISTEN_ADDR=$(lsof -i :11434 | grep LISTEN | awk '{print $9}' | head -n1)
        print_metric "Port 11434" "✓ Écoute sur $LISTEN_ADDR" "ok"
    else
        print_metric "Port 11434" "✗ Non utilisé" "error"
    fi
    
    # ========== MODÈLES ==========
    print_section "MODÈLES INSTALLÉS"
    
    if command -v ollama &>/dev/null && [[ "$STATUS" == "running" ]]; then
        MODEL_COUNT=$(ollama list 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
        print_metric "Nombre de modèles" "$MODEL_COUNT" "ok"
        
        echo ""
        ollama list 2>/dev/null | tail -n +2 | while read -r line; do
            MODEL=$(echo "$line" | awk '{print $1}')
            SIZE=$(echo "$line" | awk '{print $2}')
            echo -e "    ${CYAN}▸${NC} ${BOLD}$MODEL${NC} ${DIM}($SIZE)${NC}"
        done
    else
        print_metric "Modèles" "Service arrêté" "warn"
    fi
    
    # ========== RESSOURCES SYSTÈME ==========
    print_section "RESSOURCES SYSTÈME"
    
    # CPU
    CPU_USAGE=$(ps aux | grep "[o]llama serve" | awk '{print $3}')
    if [[ -n "$CPU_USAGE" ]]; then
        CPU_INT=$(echo "$CPU_USAGE" | cut -d'.' -f1)
        if [[ $CPU_INT -lt 50 ]]; then
            print_metric "CPU Ollama" "${CPU_USAGE}%" "ok"
        elif [[ $CPU_INT -lt 80 ]]; then
            print_metric "CPU Ollama" "${CPU_USAGE}%" "warn"
        else
            print_metric "CPU Ollama" "${CPU_USAGE}%" "error"
        fi
    else
        print_metric "CPU Ollama" "0%" "ok"
    fi
    
    # Mémoire
    if [[ "$STATUS" == "running" ]]; then
        PID=$(pgrep -x ollama)
        MEM_KB=$(ps -p "$PID" -o rss= | tr -d ' ')
        MEM_MB=$((MEM_KB / 1024))
        
        if [[ $MEM_MB -lt 1024 ]]; then
            print_metric "RAM Ollama" "${MEM_MB}MB" "ok"
        elif [[ $MEM_MB -lt 4096 ]]; then
            print_metric "RAM Ollama" "${MEM_MB}MB" "warn"
        else
            print_metric "RAM Ollama" "${MEM_MB}MB" "error"
        fi
    fi
    
    # Espace disque modèles
    if [[ -d "$HOME/.ollama" ]]; then
        OLLAMA_SIZE=$(du -sh "$HOME/.ollama" 2>/dev/null | cut -f1)
        print_metric "Espace modèles (~/.ollama)" "$OLLAMA_SIZE" "ok"
    fi
    
    # ========== DOSSIER PARTAGÉ ==========
    print_section "DOSSIER PARTAGÉ RAG"
    
    if [[ -d "$SHARED_DIR" ]]; then
        print_metric "Chemin" "$SHARED_DIR" "ok"
        
        DOC_COUNT=$(find "$SHARED_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
        print_metric "Fichiers totaux" "$DOC_COUNT" "ok"
        
        SHARED_SIZE=$(du -sh "$SHARED_DIR" 2>/dev/null | cut -f1)
        print_metric "Taille" "$SHARED_SIZE" "ok"
    else
        print_metric "Dossier partagé" "✗ Introuvable" "warn"
    fi
    
    # ========== LOGS ==========
    print_section "LOGS & MONITORING"
    
    if [[ -f "$LOG_FILE" ]]; then
        LOG_SIZE=$(du -h "$LOG_FILE" 2>/dev/null | cut -f1)
        LOG_LINES=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ')
        print_metric "Log principal" "$LOG_SIZE ($LOG_LINES lignes)" "ok"
    fi
    
    if [[ -f "$ERROR_LOG" ]]; then
        ERROR_SIZE=$(du -h "$ERROR_LOG" 2>/dev/null | cut -f1)
        ERROR_LINES=$(wc -l < "$ERROR_LOG" 2>/dev/null | tr -d ' ')
        
        if [[ $ERROR_LINES -eq 0 ]]; then
            print_metric "Erreurs" "Aucune" "ok"
        elif [[ $ERROR_LINES -lt 10 ]]; then
            print_metric "Erreurs" "$ERROR_LINES lignes" "warn"
        else
            print_metric "Erreurs" "$ERROR_LINES lignes" "error"
        fi
    fi
    
    # ========== PERFORMANCES ==========
    print_section "MÉTRIQUES DE PERFORMANCE"
    
    if [[ "$STATUS" == "running" ]] && curl -s --connect-timeout 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
        # Test génération simple
        echo -e "  ${DIM}Test génération en cours...${NC}"
        
        START=$(date +%s%N)
        curl -s -X POST http://127.0.0.1:11434/api/generate -d '{
            "model": "'"${LLM_MODEL:-mistral:latest}"'",
            "prompt": "Hi",
            "stream": false
        }' >/dev/null 2>&1
        END=$(date +%s%N)
        
        DURATION_MS=$(( (END - START) / 1000000 ))
        
        if [[ $DURATION_MS -lt 1000 ]]; then
            print_metric "Temps de réponse (test)" "${DURATION_MS}ms" "ok"
        elif [[ $DURATION_MS -lt 3000 ]]; then
            print_metric "Temps de réponse (test)" "${DURATION_MS}ms" "warn"
        else
            print_metric "Temps de réponse (test)" "${DURATION_MS}ms" "error"
        fi
    fi
    
    # ========== RECOMMANDATIONS ==========
    print_section "RECOMMANDATIONS"
    
    WARNINGS=()
    
    if [[ "$STATUS" == "stopped" ]]; then
        WARNINGS+=("Service arrêté - Exécutez: $0 start")
    fi
    
    if ! launchctl list | grep -q "com.ollama.ollama"; then
        WARNINGS+=("LaunchAgent non chargé - Service ne redémarrera pas au boot")
    fi
    
    if [[ -n "$MAC_IP" ]] && ! curl -s --connect-timeout 2 "http://$MAC_IP:11434/api/tags" >/dev/null 2>&1; then
        WARNINGS+=("API inaccessible depuis le réseau - Vérifiez le pare-feu")
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
    echo -e "${DIM}Commandes: $0 [start|stop|status]${NC}\n"
}

# ============================================
# MAIN
# ============================================

case "${1:-status}" in
    start)
        start_ollama
        ;;
    stop)
        stop_ollama
        ;;
    status)
        show_status
        ;;
    restart)
        stop_ollama
        sleep 2
        start_ollama
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
