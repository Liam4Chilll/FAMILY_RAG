#!/bin/bash
#
# Script de configuration réseau Mac pour RAG Familial
# Configure l'interface réseau virtuelle pour communication Mac ↔ VM
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
║      CONFIGURATION RÉSEAU MAC                ║
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

if [[ $EUID -eq 0 ]]; then
    print_error "Ne pas exécuter ce script avec sudo"
    exit 1
fi

print_success "Système macOS détecté"

# ============================================
# DÉTECTION HYPERVISEUR
# ============================================

print_step "Détection de l'hyperviseur installé"
echo ""

HYPERVISOR=""

if [[ -d "/Applications/VMware Fusion.app" ]]; then
    VMWARE_VERSION=$(/Applications/VMware\ Fusion.app/Contents/Library/vmware-vmx --version 2>/dev/null | head -1 || echo "Version inconnue")
    echo "  ✓ VMware Fusion détecté ($VMWARE_VERSION)"
    HYPERVISOR="vmware"
elif [[ -f "/usr/local/bin/VBoxManage" ]]; then
    VBOX_VERSION=$(VBoxManage --version 2>/dev/null || echo "Version inconnue")
    echo "  ✓ VirtualBox détecté ($VBOX_VERSION)"
    HYPERVISOR="virtualbox"
else
    print_warning "Aucun hyperviseur détecté (VMware Fusion ou VirtualBox)"
    echo ""
    echo "Hyperviseurs supportés :"
    echo "  1) VMware Fusion (recommandé pour Mac Apple Silicon)"
    echo "  2) VirtualBox"
    echo "  3) Autre/Manuel (configuration manuelle requise)"
    echo ""
    read -p "Sélectionner l'hyperviseur [1-3]: " HYPER_CHOICE
    
    case $HYPER_CHOICE in
        1) HYPERVISOR="vmware" ;;
        2) HYPERVISOR="virtualbox" ;;
        3) HYPERVISOR="manual" ;;
        *) print_error "Choix invalide"; exit 1 ;;
    esac
fi

print_success "Hyperviseur sélectionné: $HYPERVISOR"

# ============================================
# COLLECTE DES INFORMATIONS RÉSEAU
# ============================================

print_step "Configuration du réseau privé"
echo ""
echo "Le réseau privé permet la communication entre le Mac (hôte) et la VM"
echo "sans dépendre d'Internet. Format recommandé : 172.x.x.x ou 192.168.x.x"
echo ""

# Détection réseaux privés existants
print_step "Détection des réseaux privés existants..."
EXISTING_NETWORKS=$(ifconfig | grep -Eo 'inet (172|192\.168|10\.)\S+' | awk '{print $2}' | sort -u)

if [[ -n "$EXISTING_NETWORKS" ]]; then
    echo "Réseaux privés détectés sur le Mac :"
    echo "$EXISTING_NETWORKS" | nl
    echo ""
fi

# Demander le réseau souhaité
while true; do
    read -p "Réseau privé souhaité (ex: 172.16.74.0/24): " NETWORK_INPUT
    
    # Validation format CIDR
    if [[ $NETWORK_INPUT =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        NETWORK_ADDR=$(echo $NETWORK_INPUT | cut -d'/' -f1)
        NETWORK_MASK=$(echo $NETWORK_INPUT | cut -d'/' -f2)
        
        # Validation plage privée
        if [[ $NETWORK_ADDR =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.) ]]; then
            break
        else
            print_error "Doit être un réseau privé (10.x.x.x, 172.16-31.x.x, ou 192.168.x.x)"
        fi
    else
        print_error "Format invalide. Utiliser la notation CIDR (ex: 172.16.74.0/24)"
    fi
done

# Calculer l'IP de l'hôte (Mac) - typiquement .1
NETWORK_BASE=$(echo $NETWORK_ADDR | cut -d'.' -f1-3)
DEFAULT_HOST_IP="${NETWORK_BASE}.1"

echo ""
read -p "IP du Mac sur ce réseau (défaut: $DEFAULT_HOST_IP): " HOST_IP
HOST_IP=${HOST_IP:-$DEFAULT_HOST_IP}

# Validation IP hôte
while [[ ! $HOST_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; do
    print_error "IP invalide"
    read -p "IP du Mac: " HOST_IP
done

# Suggestion plage DHCP pour VMs
NETWORK_START="${NETWORK_BASE}.100"
NETWORK_END="${NETWORK_BASE}.200"

echo ""
print_step "Configuration suggérée pour les VMs"
echo "────────────────────────────────────────────"
echo "Réseau      : $NETWORK_INPUT"
echo "IP Mac      : $HOST_IP"
echo "Plage VMs   : $NETWORK_START - $NETWORK_END"
echo "────────────────────────────────────────────"

# Nom de l'interface réseau virtuelle
echo ""
read -p "Nom du réseau virtuel (défaut: ragnet): " NETWORK_NAME
NETWORK_NAME=${NETWORK_NAME:-ragnet}

# ============================================
# CONFIRMATION
# ============================================

echo ""
print_step "Récapitulatif de la configuration"
echo "════════════════════════════════════════════"
echo "Hyperviseur        : $HYPERVISOR"
echo "Réseau privé       : $NETWORK_INPUT"
echo "IP Mac             : $HOST_IP"
echo "Nom réseau         : $NETWORK_NAME"
echo "Plage DHCP VMs     : $NETWORK_START - $NETWORK_END"
echo "════════════════════════════════════════════"
echo ""
read -p "Confirmer la configuration ? (y/n): " CONFIRM
[[ ! $CONFIRM =~ ^[Yy]$ ]] && { print_error "Configuration annulée"; exit 1; }

# ============================================
# CONFIGURATION VMWARE FUSION
# ============================================

if [[ "$HYPERVISOR" == "vmware" ]]; then
    print_step "Configuration VMware Fusion"
    
    VMWARE_NET_DIR="/Library/Preferences/VMware Fusion/vmnet8"
    VMWARE_NET_FILE="/Library/Preferences/VMware Fusion/networking"
    
    # Vérifier si VMware Fusion est installé
    if [[ ! -d "/Applications/VMware Fusion.app" ]]; then
        print_error "VMware Fusion non trouvé dans /Applications"
        echo "Installer VMware Fusion avant de continuer"
        exit 1
    fi
    
    print_step "Arrêt des services VMware..."
    sudo /Applications/VMware\ Fusion.app/Contents/Library/services/services.sh --stop 2>/dev/null || true
    sleep 2
    
    # Backup configuration existante
    if [[ -f "$VMWARE_NET_FILE" ]]; then
        print_step "Sauvegarde de la configuration existante..."
        sudo cp "$VMWARE_NET_FILE" "${VMWARE_NET_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        print_success "Backup créé"
    fi
    
    # Déterminer le prochain vmnet disponible
    VMNET_NUM=8
    for i in {8..20}; do
        if ! grep -q "VNET_${i}_" "$VMWARE_NET_FILE" 2>/dev/null; then
            VMNET_NUM=$i
            break
        fi
    done
    
    VMNET_NAME="vmnet${VMNET_NUM}"
    
    print_step "Configuration du réseau $VMNET_NAME (host-only)..."
    
    # Créer/modifier la configuration networking
    sudo bash -c "cat >> $VMWARE_NET_FILE" << EOF

# Configuration RAG Familial - $(date)
answer VNET_${VMNET_NUM}_DHCP yes
answer VNET_${VMNET_NUM}_DHCP_CFG_HASH $(echo -n "${NETWORK_NAME}" | md5)
answer VNET_${VMNET_NUM}_HOSTONLY_NETMASK 255.255.255.0
answer VNET_${VMNET_NUM}_HOSTONLY_SUBNET ${NETWORK_BASE}.0
answer VNET_${VMNET_NUM}_NAT no
answer VNET_${VMNET_NUM}_VIRTUAL_ADAPTER yes
EOF
    
    # Configuration DHCP
    DHCP_CONF_DIR="/Library/Preferences/VMware Fusion/${VMNET_NAME}"
    sudo mkdir -p "$DHCP_CONF_DIR"
    
    sudo bash -c "cat > $DHCP_CONF_DIR/dhcpd.conf" << EOF
# DHCP Configuration for RAG Familial
subnet ${NETWORK_BASE}.0 netmask 255.255.255.0 {
    range $NETWORK_START $NETWORK_END;
    option routers $HOST_IP;
    option domain-name-servers 8.8.8.8, 8.8.4.4;
}
EOF
    
    print_success "Configuration VMware créée"
    
    # Redémarrer les services
    print_step "Redémarrage des services VMware..."
    sudo /Applications/VMware\ Fusion.app/Contents/Library/services/services.sh --start
    sleep 3
    
    # Vérification interface
    if ifconfig $VMNET_NAME &> /dev/null; then
        ACTUAL_IP=$(ifconfig $VMNET_NAME | grep 'inet ' | awk '{print $2}')
        print_success "Interface $VMNET_NAME active (IP: $ACTUAL_IP)"
        
        if [[ "$ACTUAL_IP" != "$HOST_IP" ]]; then
            print_warning "IP actuelle ($ACTUAL_IP) différente de celle demandée ($HOST_IP)"
            echo "Ajustement de l'IP..."
            sudo ifconfig $VMNET_NAME inet $HOST_IP netmask 255.255.255.0
        fi
    else
        print_error "Interface $VMNET_NAME non créée automatiquement"
        echo "Configuration manuelle requise dans VMware Fusion > Préférences > Réseau"
    fi

# ============================================
# CONFIGURATION VIRTUALBOX
# ============================================

elif [[ "$HYPERVISOR" == "virtualbox" ]]; then
    print_step "Configuration VirtualBox"
    
    if ! command -v VBoxManage &> /dev/null; then
        print_error "VBoxManage non trouvé"
        echo "Installer VirtualBox avant de continuer"
        exit 1
    fi
    
    # Vérifier si le réseau existe déjà
    EXISTING_NET=$(VBoxManage list hostonlyifs | grep -i "$NETWORK_NAME" || true)
    
    if [[ -n "$EXISTING_NET" ]]; then
        print_warning "Un réseau nommé '$NETWORK_NAME' existe déjà"
        read -p "Supprimer et recréer ? (y/n): " RECREATE
        if [[ $RECREATE =~ ^[Yy]$ ]]; then
            VBOX_IF=$(VBoxManage list hostonlyifs | grep -B3 "$NETWORK_NAME" | grep "^Name:" | awk '{print $2}')
            VBoxManage hostonlyif remove "$VBOX_IF"
            print_success "Ancien réseau supprimé"
        else
            print_step "Utilisation du réseau existant"
        fi
    fi
    
    # Créer le réseau host-only
    print_step "Création du réseau host-only..."
    VBOX_IF=$(VBoxManage hostonlyif create | grep -oE 'vboxnet[0-9]+')
    
    if [[ -z "$VBOX_IF" ]]; then
        print_error "Échec de création de l'interface"
        exit 1
    fi
    
    print_success "Interface $VBOX_IF créée"
    
    # Configuration IP
    print_step "Configuration de l'adresse IP..."
    VBoxManage hostonlyif ipconfig $VBOX_IF --ip $HOST_IP --netmask 255.255.255.0
    
    # Configuration DHCP
    print_step "Configuration du serveur DHCP..."
    VBoxManage dhcpserver add --ifname $VBOX_IF \
        --ip $HOST_IP \
        --netmask 255.255.255.0 \
        --lowerip $NETWORK_START \
        --upperip $NETWORK_END \
        --enable
    
    print_success "Configuration VirtualBox terminée"

# ============================================
# CONFIGURATION MANUELLE
# ============================================

elif [[ "$HYPERVISOR" == "manual" ]]; then
    print_warning "Configuration manuelle requise"
    echo ""
    echo "Pour configurer manuellement le réseau :"
    echo ""
    echo "1. Créer une interface réseau host-only dans votre hyperviseur"
    echo "2. Configurer l'IP de l'hôte (Mac) : $HOST_IP"
    echo "3. Configurer le masque de sous-réseau : 255.255.255.0"
    echo "4. Activer DHCP avec la plage : $NETWORK_START - $NETWORK_END"
    echo ""
    read -p "Appuyer sur Entrée après configuration manuelle..."
fi

# ============================================
# ACTIVATION DU PARTAGE RÉSEAU (OPTIONNEL)
# ============================================

echo ""
read -p "Activer le partage Internet pour les VMs ? (y/n): " ENABLE_NAT

if [[ $ENABLE_NAT =~ ^[Yy]$ ]]; then
    print_step "Configuration du partage Internet (NAT)"
    
    # Détecter l'interface Internet principale
    DEFAULT_ROUTE=$(route -n get default 2>/dev/null | grep 'interface:' | awk '{print $2}')
    
    if [[ -n "$DEFAULT_ROUTE" ]]; then
        print_success "Interface Internet détectée: $DEFAULT_ROUTE"
        
        echo ""
        echo "⚠️  Le partage Internet nécessite des privilèges administrateur"
        echo "Configuration dans : Préférences Système > Partage > Partage Internet"
        echo ""
        echo "Partager depuis : $DEFAULT_ROUTE"
        echo "Vers            : $VMNET_NAME (ou l'interface créée)"
        echo ""
        read -p "Configurer automatiquement ? (y/n): " AUTO_NAT
        
        if [[ $AUTO_NAT =~ ^[Yy]$ ]]; then
            sudo /usr/sbin/sysctl -w net.inet.ip.forwarding=1
            print_success "IP forwarding activé"
            
            print_warning "Compléter manuellement dans Préférences Système > Partage"
        fi
    else
        print_warning "Impossible de détecter l'interface Internet principale"
        echo "Configuration manuelle requise"
    fi
fi

# ============================================
# ACTIVATION SSH (REMOTE LOGIN)
# ============================================

echo ""
read -p "Activer Remote Login (SSH) sur le Mac ? (y/n): " ENABLE_SSH

if [[ $ENABLE_SSH =~ ^[Yy]$ ]]; then
    print_step "Activation de Remote Login..."
    
    # Vérifier si déjà activé
    if sudo systemsetup -getremotelogin | grep -q "On"; then
        print_success "Remote Login déjà activé"
    else
        sudo systemsetup -setremotelogin on
        print_success "Remote Login activé"
    fi
    
    # Afficher le nom d'utilisateur pour SSH
    CURRENT_USER=$(whoami)
    print_success "Utilisateur SSH: $CURRENT_USER"
fi

# ============================================
# SAUVEGARDE DE LA CONFIGURATION
# ============================================

print_step "Sauvegarde de la configuration"

CONFIG_FILE="$HOME/.rag_network_config"

cat > "$CONFIG_FILE" << EOF
# Configuration Réseau Mac pour RAG Familial
# Générée le $(date)

HYPERVISOR=$HYPERVISOR
NETWORK_CIDR=$NETWORK_INPUT
NETWORK_BASE=$NETWORK_BASE
HOST_IP=$HOST_IP
NETWORK_NAME=$NETWORK_NAME
DHCP_START=$NETWORK_START
DHCP_END=$NETWORK_END
EOF

if [[ "$HYPERVISOR" == "vmware" ]]; then
    echo "VMNET_NAME=$VMNET_NAME" >> "$CONFIG_FILE"
elif [[ "$HYPERVISOR" == "virtualbox" ]]; then
    echo "VBOX_IF=$VBOX_IF" >> "$CONFIG_FILE"
fi

chmod 600 "$CONFIG_FILE"
print_success "Configuration sauvegardée: $CONFIG_FILE"

# ============================================
# TESTS DE CONNECTIVITÉ
# ============================================

print_step "Tests de connectivité"
echo ""

# Test ping de l'interface
if ping -c 2 $HOST_IP &> /dev/null; then
    print_success "✓ Interface accessible ($HOST_IP)"
else
    print_warning "✗ Interface non accessible (normal si aucune VM active)"
fi

# ============================================
# RÉSUMÉ FINAL
# ============================================

echo ""
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════╗
║                                               ║
║    CONFIGURATION RÉSEAU MAC TERMINÉE         ║
║                                               ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo "📍 Réseau configuré:"
echo "   - Type         : Host-Only (réseau privé)"
echo "   - Réseau       : $NETWORK_INPUT"
echo "   - IP Mac       : $HOST_IP"
echo "   - Plage VMs    : $NETWORK_START - $NETWORK_END"
echo "   - Hyperviseur  : $HYPERVISOR"

if [[ "$HYPERVISOR" == "vmware" ]]; then
    echo "   - Interface    : $VMNET_NAME"
elif [[ "$HYPERVISOR" == "virtualbox" ]]; then
    echo "   - Interface    : $VBOX_IF"
fi

echo ""
echo "📁 Configuration sauvegardée: $CONFIG_FILE"
echo ""
echo -e "${YELLOW}Prochaines étapes:${NC}"
echo "  1. Créer une VM avec le script: ./setup_vm.sh"
echo "  2. Attacher la VM au réseau: $NETWORK_NAME"
echo "  3. Configurer SSH: ./setup_ssh.sh"
echo ""
print_success "Configuration terminée avec succès!"
