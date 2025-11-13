#!/bin/bash
#
# Script de configuration SSH bidirectionnelle pour RAG Familial
# Configure l'authentification par clé entre Mac et VM Fedora
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
║      CONFIGURATION SSH BIDIRECTIONNELLE      ║
║         RAG Familial - Setup                  ║
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

print_success "Système macOS détecté"

# ============================================
# CHARGEMENT CONFIGURATIONS EXISTANTES
# ============================================

NETWORK_CONFIG="$HOME/.rag_network_config"
VM_CONFIG="$HOME/.rag_vm_config"

print_step "Chargement des configurations existantes"

FOUND_CONFIGS=0

if [[ -f "$NETWORK_CONFIG" ]]; then
    source "$NETWORK_CONFIG"
    print_success "Configuration réseau chargée"
    echo "  - IP Mac       : $HOST_IP"
    FOUND_CONFIGS=$((FOUND_CONFIGS + 1))
fi

if [[ -f "$VM_CONFIG" ]]; then
    source "$VM_CONFIG"
    print_success "Configuration VM chargée"
    echo "  - VM           : $VM_NAME"
    echo "  - Hostname     : $VM_HOSTNAME"
    echo "  - Utilisateur  : $VM_USER"
    FOUND_CONFIGS=$((FOUND_CONFIGS + 1))
fi

if [[ $FOUND_CONFIGS -eq 0 ]]; then
    print_warning "Aucune configuration trouvée"
    echo "Exécuter d'abord :"
    echo "  1. ./setup_network_mac.sh"
    echo "  2. ./setup_vm_fedora.sh"
    echo ""
fi

# ============================================
# COLLECTE INFORMATIONS MAC
# ============================================

echo ""
print_step "Configuration Mac (machine hôte)"
echo ""

# Utilisateur Mac
MAC_USER=$(whoami)
print_success "Utilisateur Mac détecté: $MAC_USER"

# IP Mac
if [[ -z "$HOST_IP" ]]; then
    print_step "Détection de l'IP Mac sur le réseau privé..."
    DETECTED_IPS=$(ifconfig | grep -Eo 'inet (172|192\.168|10\.)\S+' | awk '{print $2}' | sort -u)
    
    if [[ -n "$DETECTED_IPS" ]]; then
        echo "IPs privées détectées :"
        echo "$DETECTED_IPS" | nl
        echo ""
        read -p "Sélectionner l'IP [numéro] ou entrer manuellement: " IP_CHOICE
        
        if [[ $IP_CHOICE =~ ^[0-9]+$ ]]; then
            HOST_IP=$(echo "$DETECTED_IPS" | sed -n "${IP_CHOICE}p")
        else
            HOST_IP="$IP_CHOICE"
        fi
    else
        read -p "IP Mac sur le réseau privé: " HOST_IP
    fi
    
    while [[ ! $HOST_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; do
        print_error "IP invalide"
        read -p "IP Mac: " HOST_IP
    done
fi

print_success "IP Mac: $HOST_IP"

# Vérifier Remote Login
echo ""
print_step "Vérification de Remote Login (SSH) sur Mac"

if sudo systemsetup -getremotelogin 2>/dev/null | grep -q "On"; then
    print_success "Remote Login activé"
else
    print_warning "Remote Login désactivé"
    read -p "Activer Remote Login maintenant ? (y/n): " ENABLE_SSH
    
    if [[ $ENABLE_SSH =~ ^[Yy]$ ]]; then
        sudo systemsetup -setremotelogin on
        print_success "Remote Login activé"
    else
        print_error "SSH doit être activé sur le Mac pour continuer"
        echo "Activer manuellement : Préférences Système > Partage > Remote Login"
        exit 1
    fi
fi

# ============================================
# COLLECTE INFORMATIONS VM
# ============================================

echo ""
print_step "Configuration VM Fedora"
echo ""

# Hostname/IP VM
if [[ -z "$VM_HOSTNAME" ]]; then
    read -p "Hostname de la VM (ex: playground): " VM_HOSTNAME
fi

if [[ -z "$VM_IP" ]] || [[ "$VM_IP" == "DHCP" ]]; then
    echo ""
    echo "Méthodes de connexion à la VM :"
    echo "  1) Par IP (si connue)"
    echo "  2) Par hostname (si résolution DNS fonctionne)"
    echo "  3) Scan automatique du réseau"
    echo ""
    read -p "Méthode [1-3]: " CONNECTION_METHOD
    
    case $CONNECTION_METHOD in
        1)
            read -p "IP de la VM: " VM_IP
            while [[ ! $VM_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; do
                print_error "IP invalide"
                read -p "IP de la VM: " VM_IP
            done
            VM_TARGET="$VM_IP"
            ;;
        2)
            VM_TARGET="$VM_HOSTNAME"
            echo "Tentative de connexion via hostname: $VM_HOSTNAME"
            ;;
        3)
            print_step "Scan du réseau en cours..."
            NETWORK_BASE=$(echo $HOST_IP | cut -d'.' -f1-3)
            
            echo "Scan de ${NETWORK_BASE}.0/24 (peut prendre 1-2 minutes)..."
            ACTIVE_IPS=$(nmap -sn ${NETWORK_BASE}.0/24 2>/dev/null | grep "Nmap scan report" | awk '{print $5}' || true)
            
            if [[ -z "$ACTIVE_IPS" ]]; then
                print_warning "nmap non installé, scan manuel..."
                echo "Installation de nmap: brew install nmap"
                print_warning "Utiliser méthode 1 ou 2"
                exit 1
            fi
            
            echo "Machines actives détectées :"
            echo "$ACTIVE_IPS" | nl
            echo ""
            read -p "Sélectionner l'IP de la VM [numéro]: " VM_CHOICE
            VM_IP=$(echo "$ACTIVE_IPS" | sed -n "${VM_CHOICE}p")
            VM_TARGET="$VM_IP"
            ;;
        *)
            print_error "Choix invalide"
            exit 1
            ;;
    esac
else
    VM_TARGET="$VM_IP"
fi

# Utilisateur VM
if [[ -z "$VM_USER" ]]; then
    read -p "Nom d'utilisateur dans la VM (ex: user): " VM_USER
fi

print_success "Cible VM: $VM_USER@$VM_TARGET"

# ============================================
# TEST CONNEXION INITIALE
# ============================================

echo ""
print_step "Test de connexion SSH vers la VM"
echo "Tentative: ssh $VM_USER@$VM_TARGET"
echo ""

if ssh -o ConnectTimeout=5 -o BatchMode=yes $VM_USER@$VM_TARGET exit 2>/dev/null; then
    print_success "Connexion SSH déjà configurée"
    SKIP_VM_SSH_SETUP="yes"
else
    print_warning "Connexion SSH nécessite un mot de passe"
    echo ""
    echo "Vérifier que :"
    echo "  1. La VM est démarrée"
    echo "  2. SSH est installé sur la VM (dnf install openssh-server)"
    echo "  3. Le service SSH est actif (systemctl start sshd)"
    echo "  4. Le mot de passe de '$VM_USER' est connu"
    echo ""
    read -p "Continuer la configuration SSH ? (y/n): " CONTINUE
    [[ ! $CONTINUE =~ ^[Yy]$ ]] && exit 1
    
    SKIP_VM_SSH_SETUP="no"
fi

# ============================================
# GÉNÉRATION CLÉS SSH MAC
# ============================================

echo ""
print_step "Configuration des clés SSH sur le Mac"

MAC_SSH_DIR="$HOME/.ssh"
MAC_SSH_KEY="$MAC_SSH_DIR/id_ed25519"

mkdir -p "$MAC_SSH_DIR"
chmod 700 "$MAC_SSH_DIR"

# Vérifier si clé existe
if [[ -f "$MAC_SSH_KEY" ]]; then
    print_success "Clé SSH Mac existe déjà"
    echo "Fingerprint: $(ssh-keygen -lf $MAC_SSH_KEY.pub 2>/dev/null | awk '{print $2}')"
    echo ""
    read -p "Générer une nouvelle clé ? (y/n): " REGENERATE
    
    if [[ $REGENERATE =~ ^[Yy]$ ]]; then
        mv "$MAC_SSH_KEY" "${MAC_SSH_KEY}.backup.$(date +%Y%m%d_%H%M%S)"
        mv "$MAC_SSH_KEY.pub" "${MAC_SSH_KEY}.pub.backup.$(date +%Y%m%d_%H%M%S)"
        print_success "Ancienne clé sauvegardée"
    else
        SKIP_MAC_KEYGEN="yes"
    fi
fi

if [[ "$SKIP_MAC_KEYGEN" != "yes" ]]; then
    print_step "Génération de la clé SSH ed25519..."
    ssh-keygen -t ed25519 -C "mac-rag-$MAC_USER" -f "$MAC_SSH_KEY" -N ""
    print_success "Clé SSH générée"
    echo "Clé publique: $MAC_SSH_KEY.pub"
fi

# ============================================
# COPIE CLÉ MAC → VM
# ============================================

if [[ "$SKIP_VM_SSH_SETUP" != "yes" ]]; then
    echo ""
    print_step "Copie de la clé SSH Mac vers la VM"
    echo "Mot de passe de '$VM_USER@$VM_TARGET' requis"
    echo ""
    
    if ssh-copy-id -i "$MAC_SSH_KEY.pub" $VM_USER@$VM_TARGET; then
        print_success "Clé copiée vers la VM"
    else
        print_error "Échec de la copie de clé"
        echo ""
        echo "Copier manuellement :"
        echo "  1. Sur la VM: mkdir -p ~/.ssh && chmod 700 ~/.ssh"
        echo "  2. Copier le contenu de $MAC_SSH_KEY.pub"
        echo "  3. Sur la VM: echo '<contenu_clé>' >> ~/.ssh/authorized_keys"
        echo "  4. Sur la VM: chmod 600 ~/.ssh/authorized_keys"
        exit 1
    fi
    
    # Test connexion sans mot de passe
    print_step "Vérification de l'authentification par clé..."
    if ssh -o BatchMode=yes $VM_USER@$VM_TARGET exit 2>/dev/null; then
        print_success "Authentification par clé fonctionnelle Mac → VM"
    else
        print_error "Authentification par clé échouée"
        exit 1
    fi
fi

# ============================================
# CONFIGURATION SSH MAC → VM (ALIAS)
# ============================================

echo ""
print_step "Configuration de l'alias SSH sur le Mac"

SSH_CONFIG="$MAC_SSH_DIR/config"
ALIAS_NAME="${VM_HOSTNAME}"

# Backup config SSH si existe
if [[ -f "$SSH_CONFIG" ]]; then
    cp "$SSH_CONFIG" "${SSH_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Vérifier si alias existe déjà
if grep -q "Host $ALIAS_NAME" "$SSH_CONFIG" 2>/dev/null; then
    print_warning "Alias '$ALIAS_NAME' existe déjà dans $SSH_CONFIG"
    read -p "Écraser ? (y/n): " OVERWRITE_ALIAS
    
    if [[ $OVERWRITE_ALIAS =~ ^[Yy]$ ]]; then
        # Supprimer ancien bloc
        sed -i.bak "/^Host $ALIAS_NAME$/,/^$/d" "$SSH_CONFIG"
        print_success "Ancien alias supprimé"
    else
        print_step "Conservation de l'alias existant"
        SKIP_ALIAS="yes"
    fi
fi

if [[ "$SKIP_ALIAS" != "yes" ]]; then
    cat >> "$SSH_CONFIG" << EOF

# RAG Familial - Configuration générée le $(date)
Host $ALIAS_NAME
    HostName $VM_TARGET
    User $VM_USER
    IdentityFile $MAC_SSH_KEY
    ServerAliveInterval 60
    ServerAliveCountMax 3

EOF
    
    chmod 600 "$SSH_CONFIG"
    print_success "Alias SSH créé: ssh $ALIAS_NAME"
fi

# Test avec alias
print_step "Test de connexion avec l'alias..."
if ssh -o BatchMode=yes $ALIAS_NAME exit 2>/dev/null; then
    print_success "Connexion via alias fonctionnelle: ssh $ALIAS_NAME"
else
    print_warning "Connexion via alias échouée, utiliser: ssh $VM_USER@$VM_TARGET"
fi

# ============================================
# GÉNÉRATION CLÉS SSH VM
# ============================================

echo ""
print_step "Configuration des clés SSH sur la VM (VM → Mac)"
echo "Connexion à la VM pour générer la clé..."
echo ""

VM_SSH_SCRIPT=$(cat << 'EOFVM'
#!/bin/bash
set -e

VM_SSH_DIR="$HOME/.ssh"
VM_SSH_KEY="$VM_SSH_DIR/id_ed25519"

mkdir -p "$VM_SSH_DIR"
chmod 700 "$VM_SSH_DIR"

if [[ -f "$VM_SSH_KEY" ]]; then
    echo "INFO: Clé SSH VM existe déjà"
    SKIP_KEYGEN="yes"
else
    echo "INFO: Génération de la clé SSH sur la VM..."
    ssh-keygen -t ed25519 -C "vm-rag" -f "$VM_SSH_KEY" -N "" >/dev/null 2>&1
    echo "INFO: Clé SSH générée"
fi

# Afficher la clé publique
cat "$VM_SSH_KEY.pub"
EOFVM
)

VM_PUBKEY=$(ssh $VM_USER@$VM_TARGET "bash -s" <<< "$VM_SSH_SCRIPT" 2>/dev/null)

if [[ -z "$VM_PUBKEY" ]]; then
    print_error "Impossible de récupérer la clé publique de la VM"
    exit 1
fi

# Extraire seulement la clé (dernière ligne du output)
VM_PUBKEY=$(echo "$VM_PUBKEY" | tail -1)

print_success "Clé publique VM récupérée"
echo "$VM_PUBKEY" | cut -c1-60
echo ""

# ============================================
# COPIE CLÉ VM → MAC
# ============================================

print_step "Ajout de la clé VM dans authorized_keys du Mac"

MAC_AUTHORIZED_KEYS="$MAC_SSH_DIR/authorized_keys"

# Vérifier si la clé existe déjà
if grep -Fq "$VM_PUBKEY" "$MAC_AUTHORIZED_KEYS" 2>/dev/null; then
    print_success "Clé VM déjà présente dans authorized_keys"
else
    echo "$VM_PUBKEY" >> "$MAC_AUTHORIZED_KEYS"
    chmod 600 "$MAC_AUTHORIZED_KEYS"
    print_success "Clé VM ajoutée à authorized_keys"
fi

# ============================================
# TEST CONNEXION VM → MAC
# ============================================

echo ""
print_step "Test de connexion SSH VM → Mac"

TEST_VM_TO_MAC=$(cat << EOFTEST
#!/bin/bash
if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no $MAC_USER@$HOST_IP exit 2>/dev/null; then
    echo "SUCCESS"
else
    echo "FAILED"
fi
EOFTEST
)

RESULT=$(ssh $VM_USER@$VM_TARGET "bash -s" <<< "$TEST_VM_TO_MAC" 2>/dev/null | tail -1)

if [[ "$RESULT" == "SUCCESS" ]]; then
    print_success "Authentification par clé fonctionnelle VM → Mac"
else
    print_warning "Authentification VM → Mac échouée"
    echo ""
    echo "Actions manuelles possibles :"
    echo "  1. Sur la VM, tester: ssh $MAC_USER@$HOST_IP"
    echo "  2. Vérifier le pare-feu Mac (Remote Login doit autoriser la VM)"
    echo "  3. Vérifier les permissions: chmod 600 ~/.ssh/authorized_keys"
fi

# ============================================
# CONFIGURATION KNOWN_HOSTS
# ============================================

echo ""
print_step "Configuration des known_hosts"

# Ajouter VM dans known_hosts du Mac
ssh-keyscan -H $VM_TARGET >> "$MAC_SSH_DIR/known_hosts" 2>/dev/null
print_success "Fingerprint VM ajouté aux known_hosts du Mac"

# Ajouter Mac dans known_hosts de la VM
ssh $VM_USER@$VM_TARGET "ssh-keyscan -H $HOST_IP >> ~/.ssh/known_hosts 2>/dev/null"
print_success "Fingerprint Mac ajouté aux known_hosts de la VM"

# ============================================
# SAUVEGARDE CONFIGURATION
# ============================================

print_step "Sauvegarde de la configuration SSH"

SSH_CONFIG_FILE="$HOME/.rag_ssh_config"

cat > "$SSH_CONFIG_FILE" << EOF
# Configuration SSH pour RAG Familial
# Générée le $(date)

# Mac (Hôte)
MAC_USER=$MAC_USER
HOST_IP=$HOST_IP
MAC_SSH_KEY=$MAC_SSH_KEY

# VM Fedora
VM_USER=$VM_USER
VM_TARGET=$VM_TARGET
VM_HOSTNAME=$ALIAS_NAME

# Commandes SSH
# Mac → VM : ssh $ALIAS_NAME
# VM → Mac : ssh $MAC_USER@$HOST_IP

# Test connexion
# Mac → VM : ssh -o BatchMode=yes $ALIAS_NAME exit && echo "OK"
# VM → Mac : ssh -o BatchMode=yes $MAC_USER@$HOST_IP exit && echo "OK"
EOF

chmod 600 "$SSH_CONFIG_FILE"
print_success "Configuration sauvegardée: $SSH_CONFIG_FILE"

# ============================================
# RÉSUMÉ FINAL
# ============================================

echo ""
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════╗
║                                               ║
║       SSH CONFIGURÉ AVEC SUCCÈS              ║
║                                               ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo "🔐 Authentification par clé configurée"
echo ""
echo "Mac → VM :"
echo "  ssh $ALIAS_NAME"
echo "  ssh $VM_USER@$VM_TARGET"
echo ""
echo "VM → Mac :"
echo "  ssh $MAC_USER@$HOST_IP"
echo ""
echo "📁 Fichiers:"
echo "   - Config Mac   : $SSH_CONFIG"
echo "   - Clés Mac     : $MAC_SSH_KEY"
echo "   - Config SSH   : $SSH_CONFIG_FILE"
echo ""
echo -e "${YELLOW}Tests de validation:${NC}"
echo ""
echo "Sur le Mac:"
echo "  ssh $ALIAS_NAME 'echo \"Connexion Mac → VM: OK\"'"
echo ""
echo "Sur la VM:"
echo "  ssh $MAC_USER@$HOST_IP 'echo \"Connexion VM → Mac: OK\"'"
echo ""
echo -e "${YELLOW}Prochaines étapes:${NC}"
echo "  1. Tester SSHFS: sshfs $VM_USER@$VM_TARGET:/home/$VM_USER ~/test_mount"
echo "  2. Installer Ollama: ./setup_ollama.sh"
echo "  3. Déployer le RAG: ./setup_rag.sh"
echo ""
print_success "Configuration SSH terminée!"
