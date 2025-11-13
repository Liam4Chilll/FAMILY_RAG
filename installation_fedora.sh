#!/bin/bash
#
# Script de création automatique VM Fedora pour RAG Familial
# Supporte VMware Fusion et VirtualBox
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
║       CRÉATION VM FEDORA 43                   ║
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
VMWARE_PATH="/Applications/VMware Fusion.app"
VBOX_CLI="/usr/local/bin/VBoxManage"

if [[ -d "$VMWARE_PATH" ]]; then
    VMWARE_VERSION=$("$VMWARE_PATH/Contents/Library/vmware-vmx" --version 2>/dev/null | head -1 || echo "inconnue")
    echo "  ✓ VMware Fusion détecté ($VMWARE_VERSION)"
    HYPERVISOR="vmware"
elif command -v VBoxManage &> /dev/null; then
    VBOX_VERSION=$(VBoxManage --version 2>/dev/null || echo "inconnue")
    echo "  ✓ VirtualBox détecté ($VBOX_VERSION)"
    HYPERVISOR="virtualbox"
else
    print_error "Aucun hyperviseur détecté"
    echo ""
    echo "Installer l'un des hyperviseurs suivants :"
    echo "  - VMware Fusion (https://www.vmware.com/products/fusion.html)"
    echo "  - VirtualBox (https://www.virtualbox.org/)"
    exit 1
fi

print_success "Hyperviseur sélectionné: $HYPERVISOR"

# ============================================
# CHARGEMENT CONFIG RÉSEAU (SI EXISTE)
# ============================================

NETWORK_CONFIG="$HOME/.rag_network_config"

if [[ -f "$NETWORK_CONFIG" ]]; then
    print_step "Chargement de la configuration réseau existante"
    source "$NETWORK_CONFIG"
    print_success "Configuration réseau chargée"
    echo "  - IP Mac       : $HOST_IP"
    echo "  - Réseau       : $NETWORK_CIDR"
    echo "  - Plage DHCP   : $DHCP_START - $DHCP_END"
    echo ""
else
    print_warning "Configuration réseau non trouvée ($NETWORK_CONFIG)"
    echo "Exécuter d'abord: ./setup_network_mac.sh"
    echo ""
    read -p "Continuer sans configuration réseau sauvegardée ? (y/n): " CONTINUE
    [[ ! $CONTINUE =~ ^[Yy]$ ]] && exit 1
fi

# ============================================
# CONFIGURATION VM - PARAMÈTRES GÉNÉRAUX
# ============================================

print_step "Configuration de la machine virtuelle"
echo ""

# Nom de la VM
read -p "Nom de la VM (défaut: rag-fedora): " VM_NAME
VM_NAME=${VM_NAME:-rag-fedora}

# Hostname
read -p "Hostname de la VM (défaut: playground): " VM_HOSTNAME
VM_HOSTNAME=${VM_HOSTNAME:-playground}

# Utilisateur
read -p "Nom d'utilisateur dans la VM (défaut: user): " VM_USER
VM_USER=${VM_USER:-user}

# RAM
echo ""
echo "Configuration matérielle:"
read -p "RAM (en GB, défaut: 8): " VM_RAM_GB
VM_RAM_GB=${VM_RAM_GB:-8}
VM_RAM_MB=$((VM_RAM_GB * 1024))

# Disque
read -p "Taille disque (en GB, défaut: 100): " VM_DISK_GB
VM_DISK_GB=${VM_DISK_GB:-100}

# CPUs
AVAILABLE_CPUS=$(sysctl -n hw.ncpu)
SUGGESTED_CPUS=$((AVAILABLE_CPUS / 2))
[[ $SUGGESTED_CPUS -lt 2 ]] && SUGGESTED_CPUS=2

read -p "Nombre de CPUs (disponibles: $AVAILABLE_CPUS, suggéré: $SUGGESTED_CPUS): " VM_CPUS
VM_CPUS=${VM_CPUS:-$SUGGESTED_CPUS}

# ============================================
# CONFIGURATION RÉSEAU VM
# ============================================

echo ""
print_step "Configuration réseau de la VM"
echo ""
echo "Types de réseau disponibles :"
echo "  1) Bridge      - VM accessible depuis le réseau local (Internet direct)"
echo "  2) Host-Only   - VM accessible uniquement depuis le Mac (réseau privé)"
echo "  3) NAT         - VM accède à Internet via le Mac"
echo "  4) Dual        - Bridge + Host-Only (recommandé pour RAG)"
echo ""

read -p "Type de réseau [1-4] (défaut: 4): " NETWORK_TYPE
NETWORK_TYPE=${NETWORK_TYPE:-4}

case $NETWORK_TYPE in
    1) NETWORK_MODE="bridged" ;;
    2) NETWORK_MODE="hostonly" ;;
    3) NETWORK_MODE="nat" ;;
    4) NETWORK_MODE="dual" ;;
    *) print_error "Choix invalide"; exit 1 ;;
esac

# Si réseau host-only ou dual, demander le nom du réseau
if [[ "$NETWORK_MODE" == "hostonly" ]] || [[ "$NETWORK_MODE" == "dual" ]]; then
    if [[ -n "$NETWORK_NAME" ]]; then
        echo ""
        print_success "Réseau privé détecté: $NETWORK_NAME"
        read -p "Utiliser ce réseau ? (y/n): " USE_DETECTED
        if [[ ! $USE_DETECTED =~ ^[Yy]$ ]]; then
            read -p "Nom du réseau host-only: " HOSTONLY_NET
        else
            HOSTONLY_NET="$NETWORK_NAME"
        fi
    else
        read -p "Nom du réseau host-only (ex: ragnet): " HOSTONLY_NET
    fi
fi

# IP statique ou DHCP
echo ""
read -p "IP statique pour la VM sur le réseau privé ? (y/n, défaut: n): " STATIC_IP
if [[ $STATIC_IP =~ ^[Yy]$ ]]; then
    read -p "Adresse IP (ex: 172.16.74.141): " VM_IP
    while [[ ! $VM_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; do
        print_error "IP invalide"
        read -p "Adresse IP: " VM_IP
    done
    
    read -p "Masque (défaut: 255.255.255.0): " VM_NETMASK
    VM_NETMASK=${VM_NETMASK:-255.255.255.0}
    
    if [[ -n "$HOST_IP" ]]; then
        VM_GATEWAY="$HOST_IP"
        echo "Gateway détectée automatiquement: $VM_GATEWAY"
    else
        read -p "Gateway (IP du Mac): " VM_GATEWAY
    fi
    
    USE_DHCP="no"
else
    USE_DHCP="yes"
    VM_IP="DHCP"
fi

# ============================================
# ISO FEDORA
# ============================================

echo ""
print_step "Configuration de l'ISO Fedora"
echo ""

# Chercher ISOs Fedora dans ~/Downloads et ~/Documents
FEDORA_ISOS=$(find ~/Downloads ~/Documents -maxdepth 2 -name "Fedora-*.iso" 2>/dev/null || true)

if [[ -n "$FEDORA_ISOS" ]]; then
    echo "ISOs Fedora trouvées :"
    echo "$FEDORA_ISOS" | nl
    echo ""
    read -p "Sélectionner une ISO [numéro] ou entrer un chemin personnalisé: " ISO_CHOICE
    
    if [[ $ISO_CHOICE =~ ^[0-9]+$ ]]; then
        ISO_PATH=$(echo "$FEDORA_ISOS" | sed -n "${ISO_CHOICE}p")
    else
        ISO_PATH="$ISO_CHOICE"
    fi
else
    print_warning "Aucune ISO Fedora trouvée automatiquement"
    read -p "Chemin complet vers l'ISO Fedora 43: " ISO_PATH
fi

# Vérifier que l'ISO existe
if [[ ! -f "$ISO_PATH" ]]; then
    print_error "ISO non trouvée: $ISO_PATH"
    echo ""
    echo "Télécharger Fedora 43 :"
    echo "  https://fedoraproject.org/server/download"
    exit 1
fi

print_success "ISO trouvée: $(basename "$ISO_PATH")"

# ============================================
# EMPLACEMENT VM
# ============================================

echo ""
read -p "Dossier pour stocker la VM (défaut: ~/Virtual Machines): " VM_DIR
VM_DIR=${VM_DIR:-"$HOME/Virtual Machines"}

mkdir -p "$VM_DIR"
VM_PATH="$VM_DIR/$VM_NAME"

if [[ -d "$VM_PATH" ]] || [[ -f "$VM_PATH.vmwarevm" ]] || [[ -d "$VM_PATH.vbox" ]]; then
    print_warning "Une VM nommée '$VM_NAME' existe déjà"
    read -p "Écraser ? (y/n): " OVERWRITE
    if [[ $OVERWRITE =~ ^[Yy]$ ]]; then
        rm -rf "$VM_PATH"* 2>/dev/null || true
        print_success "Ancienne VM supprimée"
    else
        print_error "Choisir un autre nom"
        exit 1
    fi
fi

# ============================================
# RÉCAPITULATIF
# ============================================

echo ""
print_step "Récapitulatif de la configuration"
echo "════════════════════════════════════════════"
echo "VM :"
echo "  - Nom          : $VM_NAME"
echo "  - Hostname     : $VM_HOSTNAME"
echo "  - Utilisateur  : $VM_USER"
echo "  - RAM          : ${VM_RAM_GB} GB"
echo "  - Disque       : ${VM_DISK_GB} GB"
echo "  - CPUs         : $VM_CPUS"
echo ""
echo "Réseau :"
echo "  - Type         : $NETWORK_MODE"
if [[ "$NETWORK_MODE" == "hostonly" ]] || [[ "$NETWORK_MODE" == "dual" ]]; then
    echo "  - Réseau privé : $HOSTONLY_NET"
    echo "  - IP VM        : $VM_IP"
fi
echo ""
echo "Système :"
echo "  - ISO          : $(basename "$ISO_PATH")"
echo "  - Emplacement  : $VM_PATH"
echo "  - Hyperviseur  : $HYPERVISOR"
echo "════════════════════════════════════════════"
echo ""
read -p "Créer la VM avec cette configuration ? (y/n): " CONFIRM
[[ ! $CONFIRM =~ ^[Yy]$ ]] && { print_error "Création annulée"; exit 1; }

# ============================================
# CRÉATION VM - VMWARE FUSION
# ============================================

if [[ "$HYPERVISOR" == "vmware" ]]; then
    print_step "Création de la VM VMware Fusion"
    
    VMWARE_CLI="$VMWARE_PATH/Contents/Library"
    VMX_FILE="$VM_PATH/$VM_NAME.vmx"
    VMDK_FILE="$VM_PATH/$VM_NAME.vmdk"
    
    mkdir -p "$VM_PATH"
    
    # Création du disque virtuel
    print_step "Création du disque virtuel (${VM_DISK_GB} GB)..."
    "$VMWARE_CLI/vmware-vdiskmanager" -c -s "${VM_DISK_GB}GB" -a lsilogic -t 0 "$VMDK_FILE"
    print_success "Disque créé"
    
    # Génération du fichier .vmx
    print_step "Génération de la configuration VM..."
    
    cat > "$VMX_FILE" << EOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "20"
displayName = "$VM_NAME"
guestOS = "fedora-64"

# Hardware
memsize = "$VM_RAM_MB"
numvcpus = "$VM_CPUS"
cpuid.coresPerSocket = "1"

# Disque
scsi0.present = "TRUE"
scsi0.virtualDev = "lsilogic"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "$VM_NAME.vmdk"
scsi0:0.deviceType = "scsi-hardDisk"

# CD/DVD pour ISO
ide1:0.present = "TRUE"
ide1:0.deviceType = "cdrom-image"
ide1:0.fileName = "$ISO_PATH"
ide1:0.startConnected = "TRUE"

# USB
usb.present = "TRUE"
usb.generic.autoconnect = "FALSE"

# Sound
sound.present = "TRUE"
sound.autoDetect = "TRUE"

# Réseau
EOF

    if [[ "$NETWORK_MODE" == "bridged" ]]; then
        cat >> "$VMX_FILE" << EOF
ethernet0.present = "TRUE"
ethernet0.connectionType = "bridged"
ethernet0.virtualDev = "e1000e"
ethernet0.addressType = "generated"
EOF
    elif [[ "$NETWORK_MODE" == "hostonly" ]]; then
        # Trouver le vmnet correspondant
        if [[ -n "$VMNET_NAME" ]]; then
            VMNET_INTERFACE="$VMNET_NAME"
        else
            VMNET_INTERFACE="vmnet8"
        fi
        
        cat >> "$VMX_FILE" << EOF
ethernet0.present = "TRUE"
ethernet0.connectionType = "custom"
ethernet0.vnet = "$VMNET_INTERFACE"
ethernet0.virtualDev = "e1000e"
ethernet0.addressType = "generated"
EOF
    elif [[ "$NETWORK_MODE" == "nat" ]]; then
        cat >> "$VMX_FILE" << EOF
ethernet0.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.virtualDev = "e1000e"
ethernet0.addressType = "generated"
EOF
    elif [[ "$NETWORK_MODE" == "dual" ]]; then
        # Trouver le vmnet pour host-only
        if [[ -n "$VMNET_NAME" ]]; then
            VMNET_INTERFACE="$VMNET_NAME"
        else
            VMNET_INTERFACE="vmnet8"
        fi
        
        cat >> "$VMX_FILE" << EOF
# Interface 1 - Bridge (Internet)
ethernet0.present = "TRUE"
ethernet0.connectionType = "bridged"
ethernet0.virtualDev = "e1000e"
ethernet0.addressType = "generated"

# Interface 2 - Host-Only (réseau privé)
ethernet1.present = "TRUE"
ethernet1.connectionType = "custom"
ethernet1.vnet = "$VMNET_INTERFACE"
ethernet1.virtualDev = "e1000e"
ethernet1.addressType = "generated"
EOF
    fi
    
    # Options additionnelles
    cat >> "$VMX_FILE" << EOF

# Options diverses
powerType.powerOff = "soft"
powerType.suspend = "soft"
powerType.reset = "soft"
tools.syncTime = "TRUE"
time.synchronize.continue = "TRUE"
time.synchronize.restore = "TRUE"
time.synchronize.resume.disk = "TRUE"
tools.upgrade.policy = "upgradeAtPowerCycle"

# EFI boot (pour Fedora moderne)
firmware = "efi"
EOF
    
    print_success "Configuration VMX créée"
    
    # Enregistrer la VM
    print_step "Enregistrement de la VM dans VMware Fusion..."
    open -a "VMware Fusion" "$VMX_FILE"
    
    print_success "VM créée et enregistrée"
    
    VM_IDENTIFIER="$VMX_FILE"

# ============================================
# CRÉATION VM - VIRTUALBOX
# ============================================

elif [[ "$HYPERVISOR" == "virtualbox" ]]; then
    print_step "Création de la VM VirtualBox"
    
    VM_UUID=$(VBoxManage createvm --name "$VM_NAME" --ostype "Fedora_64" --register --basefolder "$VM_DIR" | grep -oE '[a-f0-9-]{36}')
    
    if [[ -z "$VM_UUID" ]]; then
        print_error "Échec de création de la VM"
        exit 1
    fi
    
    print_success "VM créée (UUID: $VM_UUID)"
    
    # Configuration matérielle
    print_step "Configuration matérielle..."
    VBoxManage modifyvm "$VM_NAME" \
        --memory "$VM_RAM_MB" \
        --cpus "$VM_CPUS" \
        --vram 128 \
        --boot1 dvd \
        --boot2 disk \
        --boot3 none \
        --boot4 none \
        --firmware efi \
        --rtcuseutc on \
        --graphicscontroller vmsvga
    
    # Création du disque
    print_step "Création du disque virtuel (${VM_DISK_GB} GB)..."
    DISK_PATH="$VM_DIR/$VM_NAME/$VM_NAME.vdi"
    VBoxManage createmedium disk --filename "$DISK_PATH" --size $((VM_DISK_GB * 1024)) --format VDI
    
    # Contrôleur SATA
    VBoxManage storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAhci --portcount 2 --bootable on
    
    # Attacher disque
    VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "$DISK_PATH"
    
    # Attacher ISO
    VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 1 --device 0 --type dvddrive --medium "$ISO_PATH"
    
    print_success "Stockage configuré"
    
    # Configuration réseau
    print_step "Configuration réseau..."
    
    if [[ "$NETWORK_MODE" == "bridged" ]]; then
        VBoxManage modifyvm "$VM_NAME" --nic1 bridged --bridgeadapter1 "$(VBoxManage list bridgedifs | grep '^Name:' | head -1 | awk -F: '{print $2}' | xargs)"
    elif [[ "$NETWORK_MODE" == "hostonly" ]]; then
        if [[ -n "$VBOX_IF" ]]; then
            HOSTONLY_ADAPTER="$VBOX_IF"
        else
            HOSTONLY_ADAPTER=$(VBoxManage list hostonlyifs | grep '^Name:' | head -1 | awk '{print $2}')
        fi
        VBoxManage modifyvm "$VM_NAME" --nic1 hostonly --hostonlyadapter1 "$HOSTONLY_ADAPTER"
    elif [[ "$NETWORK_MODE" == "nat" ]]; then
        VBoxManage modifyvm "$VM_NAME" --nic1 nat
    elif [[ "$NETWORK_MODE" == "dual" ]]; then
        # NIC1 = Bridged
        VBoxManage modifyvm "$VM_NAME" --nic1 bridged --bridgeadapter1 "$(VBoxManage list bridgedifs | grep '^Name:' | head -1 | awk -F: '{print $2}' | xargs)"
        
        # NIC2 = Host-Only
        if [[ -n "$VBOX_IF" ]]; then
            HOSTONLY_ADAPTER="$VBOX_IF"
        else
            HOSTONLY_ADAPTER=$(VBoxManage list hostonlyifs | grep '^Name:' | head -1 | awk '{print $2}')
        fi
        VBoxManage modifyvm "$VM_NAME" --nic2 hostonly --hostonlyadapter2 "$HOSTONLY_ADAPTER"
    fi
    
    print_success "Réseau configuré"
    
    VM_IDENTIFIER="$VM_NAME"
fi

# ============================================
# SAUVEGARDE CONFIGURATION
# ============================================

print_step "Sauvegarde de la configuration VM"

VM_CONFIG_FILE="$HOME/.rag_vm_config"

cat > "$VM_CONFIG_FILE" << EOF
# Configuration VM pour RAG Familial
# Générée le $(date)

HYPERVISOR=$HYPERVISOR
VM_NAME=$VM_NAME
VM_HOSTNAME=$VM_HOSTNAME
VM_USER=$VM_USER
VM_RAM_GB=$VM_RAM_GB
VM_DISK_GB=$VM_DISK_GB
VM_CPUS=$VM_CPUS
VM_PATH=$VM_PATH
VM_IDENTIFIER=$VM_IDENTIFIER

NETWORK_MODE=$NETWORK_MODE
VM_IP=$VM_IP
USE_DHCP=$USE_DHCP
EOF

if [[ "$NETWORK_MODE" == "hostonly" ]] || [[ "$NETWORK_MODE" == "dual" ]]; then
    echo "HOSTONLY_NET=$HOSTONLY_NET" >> "$VM_CONFIG_FILE"
fi

if [[ "$HYPERVISOR" == "vmware" ]]; then
    echo "VMX_FILE=$VMX_FILE" >> "$VM_CONFIG_FILE"
elif [[ "$HYPERVISOR" == "virtualbox" ]]; then
    echo "VM_UUID=$VM_UUID" >> "$VM_CONFIG_FILE"
fi

chmod 600 "$VM_CONFIG_FILE"
print_success "Configuration sauvegardée: $VM_CONFIG_FILE"

# ============================================
# INSTRUCTIONS POST-CRÉATION
# ============================================

echo ""
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════╗
║                                               ║
║         VM CRÉÉE AVEC SUCCÈS                 ║
║                                               ║
╚═══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo "📍 Configuration VM:"
echo "   - Nom          : $VM_NAME"
echo "   - RAM          : ${VM_RAM_GB} GB"
echo "   - Disque       : ${VM_DISK_GB} GB"
echo "   - CPUs         : $VM_CPUS"
echo "   - Réseau       : $NETWORK_MODE"
echo ""
echo "📁 Fichiers:"
echo "   - Configuration: $VM_CONFIG_FILE"
echo "   - Emplacement  : $VM_PATH"
echo ""
echo -e "${YELLOW}Prochaines étapes:${NC}"
echo ""
echo "1. Démarrer la VM et installer Fedora 43"

if [[ "$HYPERVISOR" == "vmware" ]]; then
    echo "   VMware Fusion > Démarrer $VM_NAME"
elif [[ "$HYPERVISOR" == "virtualbox" ]]; then
    echo "   VBoxManage startvm \"$VM_NAME\" --type gui"
    echo "   ou via l'interface VirtualBox"
fi

echo ""
echo "2. Pendant l'installation Fedora:"
echo "   - Hostname     : $VM_HOSTNAME"
echo "   - Utilisateur  : $VM_USER"

if [[ "$USE_DHCP" == "no" ]]; then
    echo "   - IP statique  : $VM_IP"
    echo "   - Netmask      : $VM_NETMASK"
    echo "   - Gateway      : $VM_GATEWAY"
fi

echo ""
echo "3. Après installation, configurer SSH:"
echo "   ./setup_ssh.sh"
echo ""
echo "4. Installer le système RAG:"
echo "   ./setup_rag.sh"
echo ""
print_success "VM prête à être démarrée!"
