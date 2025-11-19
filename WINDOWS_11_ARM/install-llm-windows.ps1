#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Setup Ollama sur Windows 11 ARM pour FAMILY RAG
.DESCRIPTION
    Installation complète : Ollama + Service + Partage SMB + Configuration réseau
    Script générique compatible avec toute infrastructure Windows 11 ARM
.NOTES
    - Compatible Windows 11 ARM uniquement
    - Nécessite privilèges administrateur
    - Testé avec VMware Fusion, Hyper-V, Parallels
.AUTHOR
    RAG Project - Version GitHub Standardisée
.LINK
    https://github.com/Liam4Chilll/FAMILY_RAG
#>

# ============================================
# DÉTECTION AUTOMATIQUE IP WINDOWS
# ============================================

function Get-PrimaryIPAddress {
    try {
        $adapters = Get-NetIPAddress -AddressFamily IPv4 | 
            Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.PrefixOrigin -eq 'Dhcp' -or $_.PrefixOrigin -eq 'Manual' } |
            Sort-Object -Property InterfaceIndex |
            Select-Object -First 1
        
        if ($adapters) {
            return $adapters.IPAddress
        }
    } catch {}
    
    # Fallback
    return "192.168.1.100"
}

# ============================================
# FONCTION DE VALIDATION
# ============================================

function Validate-IPAddress {
    param([string]$IP)
    return $IP -match '^(\d{1,3}\.){3}\d{1,3}$'
}

function Validate-Path {
    param([string]$Path)
    try {
        $null = [System.IO.Path]::GetFullPath($Path)
        return $true
    } catch {
        return $false
    }
}

# ============================================
# COULEURS
# ============================================

$RED = "Red"
$GREEN = "Green"
$YELLOW = "Yellow"
$BLUE = "Cyan"
$MAGENTA = "Magenta"

function Print-Step { param($Message) Write-Host "`n[STEP] $Message" -ForegroundColor $BLUE }
function Print-Success { param($Message) Write-Host "✓ $Message" -ForegroundColor $GREEN }
function Print-Error { param($Message) Write-Host "✗ $Message" -ForegroundColor $RED; exit 1 }
function Print-Warning { param($Message) Write-Host "! $Message" -ForegroundColor $YELLOW }
function Print-Info { param($Message) Write-Host "→ $Message" -ForegroundColor $BLUE }

# ============================================
# BANNER
# ============================================

Clear-Host
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════╗" -ForegroundColor $GREEN
Write-Host "║                                               ║" -ForegroundColor $GREEN
Write-Host "║       SETUP OLLAMA - FAMILY RAG               ║" -ForegroundColor $GREEN
Write-Host "║         Windows 11 ARM - Version GitHub       ║" -ForegroundColor $GREEN
Write-Host "║                                               ║" -ForegroundColor $GREEN
Write-Host "╚═══════════════════════════════════════════════╝" -ForegroundColor $GREEN
Write-Host ""

# ============================================
# VÉRIFICATION SYSTÈME
# ============================================

Print-Step "Vérification du système"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Print-Error "Ce script nécessite des privilèges administrateur"
}

Print-Success "Privilèges administrateur confirmés"

$ARCH = $env:PROCESSOR_ARCHITECTURE
Print-Info "Architecture: $ARCH"

if ($ARCH -ne "ARM64") {
    Print-Warning "Architecture détectée: $ARCH (script optimisé pour ARM64)"
}

# ============================================
# CONFIGURATION INTERACTIVE
# ============================================

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════╗" -ForegroundColor $BLUE
Write-Host "║          CONFIGURATION DU SYSTÈME             ║" -ForegroundColor $BLUE
Write-Host "╚═══════════════════════════════════════════════╝" -ForegroundColor $BLUE
Write-Host ""
Write-Host "Veuillez fournir les informations suivantes." -ForegroundColor $YELLOW
Write-Host "Appuyez sur [Entrée] pour accepter la valeur par défaut." -ForegroundColor $YELLOW
Write-Host ""

# Détection automatique IP Windows
$DetectedIP = Get-PrimaryIPAddress
Print-Info "IP Windows détectée automatiquement: $DetectedIP"

# Prompt IP Windows
do {
    $InputWindowsIP = Read-Host "IP de ce PC Windows [$DetectedIP]"
    $WINDOWS_IP = if ([string]::IsNullOrWhiteSpace($InputWindowsIP)) { $DetectedIP } else { $InputWindowsIP }
    
    if (-not (Validate-IPAddress $WINDOWS_IP)) {
        Print-Warning "Format IP invalide. Exemple: 192.168.1.100"
    }
} while (-not (Validate-IPAddress $WINDOWS_IP))

Print-Success "IP Windows: $WINDOWS_IP"

# Prompt IP Machine Distante (VM/Serveur)
Write-Host ""
$DefaultFedoraIP = $WINDOWS_IP -replace '\.\d+$', '.130'
do {
    $InputFedoraIP = Read-Host "IP de la machine distante (VM/Serveur Linux) [$DefaultFedoraIP]"
    $FEDORA_IP = if ([string]::IsNullOrWhiteSpace($InputFedoraIP)) { $DefaultFedoraIP } else { $InputFedoraIP }
    
    if (-not (Validate-IPAddress $FEDORA_IP)) {
        Print-Warning "Format IP invalide"
    }
} while (-not (Validate-IPAddress $FEDORA_IP))

Print-Success "IP Machine distante: $FEDORA_IP"

# Prompt Utilisateur Windows
Write-Host ""
$DefaultUser = $env:USERNAME
$InputUser = Read-Host "Nom d'utilisateur Windows [$DefaultUser]"
$WINDOWS_USER = if ([string]::IsNullOrWhiteSpace($InputUser)) { $DefaultUser } else { $InputUser }
Print-Success "Utilisateur: $WINDOWS_USER"

# Prompt Dossier Partagé
Write-Host ""
$DefaultSharedDir = "C:\Users\$WINDOWS_USER\Documents\RAG"
do {
    $InputSharedDir = Read-Host "Chemin du dossier partagé [$DefaultSharedDir]"
    $SHARED_DIR = if ([string]::IsNullOrWhiteSpace($InputSharedDir)) { $DefaultSharedDir } else { $InputSharedDir }
    
    if (-not (Validate-Path $SHARED_DIR)) {
        Print-Warning "Chemin invalide"
    }
} while (-not (Validate-Path $SHARED_DIR))

Print-Success "Dossier partagé: $SHARED_DIR"

# Prompt Nom du Partage SMB
Write-Host ""
$DefaultSMBShare = "RAG"
$InputSMBShare = Read-Host "Nom du partage SMB [$DefaultSMBShare]"
$SMB_SHARE = if ([string]::IsNullOrWhiteSpace($InputSMBShare)) { $DefaultSMBShare } else { $InputSMBShare }
Print-Success "Partage SMB: $SMB_SHARE"

# Paramètres Ollama (avec défauts optimisés)
Write-Host ""
Print-Info "Configuration Ollama (défauts recommandés)"

$DefaultOllamaHost = "0.0.0.0:11434"
$InputOllamaHost = Read-Host "Ollama Host:Port [$DefaultOllamaHost]"
$OLLAMA_HOST = if ([string]::IsNullOrWhiteSpace($InputOllamaHost)) { $DefaultOllamaHost } else { $InputOllamaHost }

$DefaultEmbedModel = "nomic-embed-text"
$InputEmbedModel = Read-Host "Modèle d'embeddings [$DefaultEmbedModel]"
$EMBED_MODEL = if ([string]::IsNullOrWhiteSpace($InputEmbedModel)) { $DefaultEmbedModel } else { $InputEmbedModel }

$DefaultLLMModel = "mistral:latest"
$InputLLMModel = Read-Host "Modèle LLM [$DefaultLLMModel]"
$LLM_MODEL = if ([string]::IsNullOrWhiteSpace($InputLLMModel)) { $DefaultLLMModel } else { $InputLLMModel }

# Installation Path
Write-Host ""
$DefaultInstallPath = "$env:USERPROFILE\Downloads\Ollama"
$InputInstallPath = Read-Host "Dossier d'installation Ollama [$DefaultInstallPath]"
$INSTALL_PATH = if ([string]::IsNullOrWhiteSpace($InputInstallPath)) { $DefaultInstallPath } else { $InputInstallPath }

# ============================================
# RÉSUMÉ CONFIGURATION
# ============================================

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════╗" -ForegroundColor $BLUE
Write-Host "║          RÉSUMÉ DE LA CONFIGURATION          ║" -ForegroundColor $BLUE
Write-Host "╚═══════════════════════════════════════════════╝" -ForegroundColor $BLUE
Write-Host ""
Write-Host "🖥️  Système         : Windows 11 ARM" -ForegroundColor $BLUE
Write-Host "🏠 IP Windows      : $WINDOWS_IP"
Write-Host "🔗 IP Distante     : $FEDORA_IP"
Write-Host "📂 Installation    : $INSTALL_PATH"
Write-Host "🗂️  Dossier partagé : $SHARED_DIR"
Write-Host "🌐 Ollama écoute   : http://$WINDOWS_IP:11434"
Write-Host "🧠 Modèle embed    : $EMBED_MODEL"
Write-Host "💬 Modèle LLM      : $LLM_MODEL"
Write-Host ""

$Confirm = Read-Host "Confirmer et lancer l'installation ? [y/N]"
if ($Confirm -notmatch '^[Yy]$') {
    Print-Warning "Installation annulée"
    exit 0
}

# ============================================
# SAUVEGARDE CONFIGURATION
# ============================================

Print-Step "Sauvegarde de la configuration"

$ConfigFile = "$env:USERPROFILE\.rag_windows_config"

$ConfigContent = @"
# Configuration RAG Windows - Généré le $(Get-Date)

# Réseau
WINDOWS_IP=$WINDOWS_IP
FEDORA_IP=$FEDORA_IP
WINDOWS_USER=$WINDOWS_USER

# Ollama
OLLAMA_HOST=$OLLAMA_HOST
EMBED_MODEL=$EMBED_MODEL
LLM_MODEL=$LLM_MODEL

# Partage
SHARED_DIR=$SHARED_DIR
SMB_SHARE=$SMB_SHARE

# Installation
INSTALL_PATH=$INSTALL_PATH
"@

$ConfigContent | Out-File -FilePath $ConfigFile -Encoding utf8
Print-Success "Configuration sauvegardée: $ConfigFile"

# ============================================
# TÉLÉCHARGEMENT OLLAMA
# ============================================

Print-Step "Téléchargement d'Ollama"

if (-not (Test-Path $INSTALL_PATH)) {
    New-Item -ItemType Directory -Path $INSTALL_PATH -Force | Out-Null
    Print-Success "Dossier créé: $INSTALL_PATH"
}

$OllamaUrl = "https://github.com/ollama/ollama/releases/latest/download/ollama-windows-amd64.zip"
$ZipPath = "$env:TEMP\ollama-windows.zip"

Print-Info "Téléchargement depuis GitHub..."
try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $OllamaUrl -OutFile $ZipPath -UseBasicParsing
    $ProgressPreference = 'Continue'
    
    $FileSize = [math]::Round((Get-Item $ZipPath).Length / 1MB, 2)
    Print-Success "Téléchargement réussi ($FileSize MB)"
} catch {
    Print-Error "Échec téléchargement: $($_.Exception.Message)"
}

Print-Info "Extraction..."
try {
    Expand-Archive -Path $ZipPath -DestinationPath $INSTALL_PATH -Force
    Remove-Item -Path $ZipPath -Force
    Print-Success "Extraction terminée"
} catch {
    Print-Error "Échec extraction: $($_.Exception.Message)"
}

$OllamaExe = "$INSTALL_PATH\ollama.exe"
if (Test-Path $OllamaExe) {
    Print-Success "Ollama installé: $OllamaExe"
} else {
    Print-Error "ollama.exe introuvable après extraction"
}

# ============================================
# CONFIGURATION PATH
# ============================================

Print-Step "Configuration du PATH système"

$CurrentPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")

if ($CurrentPath -notlike "*$INSTALL_PATH*") {
    Print-Info "Ajout au PATH..."
    [System.Environment]::SetEnvironmentVariable("Path", "$CurrentPath;$INSTALL_PATH", "Machine")
    $env:Path += ";$INSTALL_PATH"
    Print-Success "PATH mis à jour"
} else {
    Print-Success "PATH déjà configuré"
}

# ============================================
# CONFIGURATION PARTAGE SMB
# ============================================

Print-Step "Configuration du partage SMB"

# Création dossier
if (-not (Test-Path $SHARED_DIR)) {
    New-Item -ItemType Directory -Path $SHARED_DIR -Force | Out-Null
    Print-Success "Dossier créé: $SHARED_DIR"
}

# Sous-dossiers
$SubFolders = @("documents", "raw", "processed")
foreach ($SubFolder in $SubFolders) {
    $SubPath = Join-Path $SHARED_DIR $SubFolder
    if (-not (Test-Path $SubPath)) {
        New-Item -ItemType Directory -Path $SubPath -Force | Out-Null
    }
}
Print-Success "Structure créée: documents/, raw/, processed/"

# Suppression partage existant
$ExistingShare = Get-SmbShare -Name $SMB_SHARE -ErrorAction SilentlyContinue
if ($ExistingShare) {
    Remove-SmbShare -Name $SMB_SHARE -Force
    Print-Info "Ancien partage supprimé"
}

# Création partage SMB
Print-Info "Création du partage SMB '$SMB_SHARE'..."
try {
    New-SmbShare -Name $SMB_SHARE `
        -Path $SHARED_DIR `
        -FullAccess $WINDOWS_USER `
        -Description "RAG - Documents partagés avec machine distante" | Out-Null
    
    Print-Success "Partage SMB créé: \\$env:COMPUTERNAME\$SMB_SHARE"
} catch {
    Print-Error "Échec création partage SMB: $($_.Exception.Message)"
}

# Permissions NTFS
Print-Info "Configuration des permissions NTFS..."
try {
    $Acl = Get-Acl $SHARED_DIR
    $Username = "$env:COMPUTERNAME\$WINDOWS_USER"
    $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Username,
        "FullControl",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )
    $Acl.SetAccessRule($AccessRule)
    Set-Acl -Path $SHARED_DIR -AclObject $Acl
    
    Print-Success "Permissions NTFS configurées"
} catch {
    Print-Warning "Erreur permissions NTFS: $($_.Exception.Message)"
}

# Vérification partage
$Share = Get-SmbShare -Name $SMB_SHARE -ErrorAction SilentlyContinue
if ($Share) {
    Print-Success "Partage vérifié: $($Share.Path)"
    Print-Info "Accès réseau: //$WINDOWS_IP/$SMB_SHARE"
} else {
    Print-Warning "Partage SMB non trouvé"
}

# ============================================
# CONFIGURATION PARE-FEU SMB
# ============================================

Print-Step "Configuration du pare-feu pour SMB"

# Règles SMB pour machine distante
$FirewallRules = @(
    @{
        Name = "SMB Server (TCP-In) for Remote Machine"
        Protocol = "TCP"
        Port = 445
        Description = "Autoriser SMB depuis machine distante"
    },
    @{
        Name = "NetBIOS (TCP-In) for Remote Machine"
        Protocol = "TCP"
        Port = 139
        Description = "Autoriser NetBIOS depuis machine distante"
    },
    @{
        Name = "SMB Discovery (UDP-In) for Remote Machine"
        Protocol = "UDP"
        Port = @(137, 138)
        Description = "Autoriser découverte SMB depuis machine distante"
    }
)

foreach ($Rule in $FirewallRules) {
    # Supprimer si existe
    $Existing = Get-NetFirewallRule -DisplayName $Rule.Name -ErrorAction SilentlyContinue
    if ($Existing) {
        Remove-NetFirewallRule -DisplayName $Rule.Name
    }
    
    # Créer règle
    $Params = @{
        DisplayName = $Rule.Name
        Direction = "Inbound"
        Protocol = $Rule.Protocol
        LocalPort = $Rule.Port
        RemoteAddress = $FEDORA_IP
        Action = "Allow"
        Profile = "Private,Domain"
        Description = $Rule.Description
    }
    
    New-NetFirewallRule @Params | Out-Null
    Print-Info "Règle créée: $($Rule.Name)"
}

Print-Success "Règles pare-feu SMB configurées"

# Activer découverte réseau et partage
Print-Info "Activation découverte réseau et partage fichiers..."
Set-NetFirewallRule -DisplayGroup "Network Discovery" -Enabled True -Profile Private -ErrorAction SilentlyContinue
Set-NetFirewallRule -DisplayGroup "File and Printer Sharing" -Enabled True -Profile Private -ErrorAction SilentlyContinue
Print-Success "Découverte réseau et partage activés"

# ============================================
# DÉMARRAGE OLLAMA
# ============================================

Print-Step "Démarrage d'Ollama"

# Arrêt processus existants
Get-Process -Name "ollama" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# Démarrage en arrière-plan avec OLLAMA_HOST
Print-Info "Lancement d'Ollama avec OLLAMA_HOST=$OLLAMA_HOST..."

$ProcessParams = @{
    FilePath = $OllamaExe
    ArgumentList = "serve"
    WindowStyle = "Hidden"
    PassThru = $true
}

$env:OLLAMA_HOST = $OLLAMA_HOST
$OllamaProcess = Start-Process @ProcessParams

Start-Sleep -Seconds 8

# Vérification démarrage
$MaxRetries = 15
$RetryCount = 0
$ApiReady = $false

Write-Host ""
while ($RetryCount -lt $MaxRetries -and -not $ApiReady) {
    try {
        $Response = Invoke-WebRequest -Uri "http://127.0.0.1:11434/api/tags" -TimeoutSec 3 -UseBasicParsing
        $ApiReady = $true
        Print-Success "Ollama démarré et accessible"
    } catch {
        $RetryCount++
        Write-Host "`r→ Attente démarrage... $RetryCount/$MaxRetries" -NoNewline -ForegroundColor $YELLOW
        Start-Sleep -Seconds 2
    }
}

Write-Host ""

if (-not $ApiReady) {
    Print-Warning "Ollama tarde à démarrer"
} else {
    # Test accès réseau
    Print-Info "Test accès réseau..."
    try {
        $Response = Invoke-WebRequest -Uri "http://${WINDOWS_IP}:11434/api/tags" -TimeoutSec 3 -UseBasicParsing
        Print-Success "API accessible depuis le réseau ✓"
    } catch {
        Print-Warning "API non accessible depuis l'IP $WINDOWS_IP"
    }
}

# ============================================
# CONFIGURATION PARE-FEU OLLAMA
# ============================================

Print-Step "Configuration du pare-feu pour Ollama"

# Règle Ollama
$OllamaRule = Get-NetFirewallRule -DisplayName "Ollama API" -ErrorAction SilentlyContinue
if ($OllamaRule) {
    Remove-NetFirewallRule -DisplayName "Ollama API"
}

New-NetFirewallRule -DisplayName "Ollama API" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 11434 `
    -RemoteAddress $FEDORA_IP `
    -Action Allow `
    -Profile Private,Domain `
    -Description "Autoriser API Ollama depuis machine distante" | Out-Null

Print-Success "Règle pare-feu Ollama créée"

# ============================================
# TÉLÉCHARGEMENT MODÈLES
# ============================================

Print-Step "Téléchargement des modèles"

function Download-OllamaModel {
    param($ModelName)
    
    Write-Host ""
    Print-Info "Téléchargement: $ModelName"
    Write-Host "   (Cela peut prendre plusieurs minutes...)" -ForegroundColor $YELLOW
    Write-Host ""
    
    $MaxAttempts = 2
    $Attempt = 0
    $Success = $false
    
    while ($Attempt -lt $MaxAttempts -and -not $Success) {
        $Attempt++
        if ($Attempt -gt 1) {
            Print-Info "Nouvelle tentative ($Attempt/$MaxAttempts)..."
        }
        
        try {
            & $OllamaExe pull $ModelName 2>&1 | ForEach-Object {
                if ($_ -match "pulling|success|digest") {
                    Write-Host "   $_" -ForegroundColor $BLUE
                }
            }
            
            if ($LASTEXITCODE -eq 0) {
                $Success = $true
                Write-Host ""
                Print-Success "Modèle $ModelName téléchargé ✓"
            }
        } catch {
            Print-Warning "Erreur: $($_.Exception.Message)"
        }
    }
    
    return $Success
}

$EmbedSuccess = Download-OllamaModel -ModelName $EMBED_MODEL
$LLMSuccess = Download-OllamaModel -ModelName $LLM_MODEL

# Liste modèles
Write-Host ""
Print-Info "Modèles disponibles:"
& $OllamaExe list

# ============================================
# RÉSUMÉ FINAL
# ============================================

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════╗" -ForegroundColor $GREEN
Write-Host "║                                               ║" -ForegroundColor $GREEN
Write-Host "║       INSTALLATION TERMINÉE AVEC SUCCÈS      ║" -ForegroundColor $GREEN
Write-Host "║                                               ║" -ForegroundColor $GREEN
Write-Host "╚═══════════════════════════════════════════════╝" -ForegroundColor $GREEN
Write-Host ""

Write-Host "✅ Configuration complète:" -ForegroundColor $GREEN
Write-Host ""

Write-Host "🖥️  Système:" -ForegroundColor $BLUE
Write-Host "   - Hostname        : $env:COMPUTERNAME"
Write-Host "   - User            : $env:USERNAME"
Write-Host "   - IP Windows      : $WINDOWS_IP"
Write-Host "   - IP Distante     : $FEDORA_IP"
Write-Host ""

Write-Host "🤖 Ollama:" -ForegroundColor $BLUE
Write-Host "   - Installation    : $INSTALL_PATH"
Write-Host "   - API locale      : http://localhost:11434"
Write-Host "   - API réseau      : http://$WINDOWS_IP:11434"
Write-Host "   - Processus actif : $(if(Get-Process -Name 'ollama' -ErrorAction SilentlyContinue){'✓ Oui'}else{'✗ Non'})"
Write-Host ""

Write-Host "🧠 Modèles:" -ForegroundColor $BLUE
Write-Host "   - Embedding       : $EMBED_MODEL $(if($EmbedSuccess){'✓'}else{'✗'})"
Write-Host "   - LLM             : $LLM_MODEL $(if($LLMSuccess){'✓'}else{'✗'})"
Write-Host ""

Write-Host "🗂️  Partage SMB:" -ForegroundColor $BLUE
Write-Host "   - Nom             : $SMB_SHARE"
Write-Host "   - Chemin          : $SHARED_DIR"
Write-Host "   - Accès réseau    : \\$env:COMPUTERNAME\$SMB_SHARE"
Write-Host "   - Accès distant   : //$WINDOWS_IP/$SMB_SHARE"
Write-Host ""

Write-Host "🔥 Pare-feu:" -ForegroundColor $BLUE
Write-Host "   - SMB (445)       : ✓ Autorisé depuis $FEDORA_IP"
Write-Host "   - Ollama (11434)  : ✓ Autorisé depuis $FEDORA_IP"
Write-Host ""

Write-Host "📝 Commandes utiles:" -ForegroundColor $BLUE
Write-Host ""
Write-Host "   # Tester Ollama localement"
Write-Host "   curl http://localhost:11434/api/tags"
Write-Host ""
Write-Host "   # Lister les modèles"
Write-Host "   ollama list"
Write-Host ""
Write-Host "   # Test interactif"
Write-Host "   ollama run $LLM_MODEL"
Write-Host ""
Write-Host "   # Vérifier partage SMB"
Write-Host "   Get-SmbShare -Name $SMB_SHARE"
Write-Host ""
Write-Host "   # Tester depuis machine distante (SSH)"
Write-Host "   ssh user@$FEDORA_IP `"curl http://${WINDOWS_IP}:11434/api/tags`""
Write-Host ""

Write-Host "🎯 Prochaine étape:" -ForegroundColor $YELLOW
Write-Host "   Sur votre machine distante: ./install-RAG-Fedora.sh"
Write-Host ""

Write-Host "📄 Configuration sauvegardée: $ConfigFile" -ForegroundColor $BLUE
Write-Host ""

Print-Success "Setup Windows terminé!"