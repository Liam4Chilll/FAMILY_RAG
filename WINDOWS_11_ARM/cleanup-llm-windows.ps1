#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Nettoyage TOTAL Family RAG sur Windows 11 ARM
.DESCRIPTION
    Supprime TOUT : Ollama, partages SMB, règles pare-feu, configurations
#>

$ErrorActionPreference = "SilentlyContinue"

# Couleurs
$Blue = "Cyan"
$Green = "Green"
$Yellow = "Yellow"
$Red = "Red"

Clear-Host
Write-Host "`n╔═══════════════════════════════════════════════╗" -ForegroundColor $Red
Write-Host "║  NETTOYAGE TOTAL - FAMILY RAG WINDOWS 11     ║" -ForegroundColor $Red
Write-Host "╚═══════════════════════════════════════════════╝`n" -ForegroundColor $Red

$Confirm = Read-Host "⚠️  Confirmer la suppression TOTALE de tout (Ollama inclus) ? [y/N]"
if ($Confirm -notmatch '^[Yy]$') {
    Write-Host "Annulé" -ForegroundColor $Yellow
    exit 0
}

Write-Host "`n[→] Démarrage du nettoyage total...`n" -ForegroundColor $Blue

# ============================================
# ARRÊT PROCESSUS OLLAMA
# ============================================

Write-Host "[1/8] Arrêt des processus Ollama..." -ForegroundColor $Blue
Get-Process -Name "ollama" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Write-Host "✓ Processus arrêtés" -ForegroundColor $Green

# ============================================
# SUPPRESSION PARTAGE SMB
# ============================================

Write-Host "`n[2/8] Suppression du partage SMB 'RAG'..." -ForegroundColor $Blue
$Share = Get-SmbShare -Name "RAG" -ErrorAction SilentlyContinue
if ($Share) {
    Remove-SmbShare -Name "RAG" -Force
    Write-Host "✓ Partage SMB supprimé" -ForegroundColor $Green
} else {
    Write-Host "  Aucun partage à supprimer" -ForegroundColor $Yellow
}

# ============================================
# SUPPRESSION RÈGLES PARE-FEU
# ============================================

Write-Host "`n[3/8] Suppression des règles pare-feu..." -ForegroundColor $Blue
$Rules = @(
    "*Ollama*",
    "*Fedora*",
    "*RAG*",
    "*SMB*Fedora*"
)

$RemovedCount = 0
foreach ($Pattern in $Rules) {
    $Found = Get-NetFirewallRule -DisplayName $Pattern -ErrorAction SilentlyContinue
    if ($Found) {
        $Found | Remove-NetFirewallRule
        $RemovedCount += $Found.Count
    }
}

if ($RemovedCount -gt 0) {
    Write-Host "✓ $RemovedCount règle(s) supprimée(s)" -ForegroundColor $Green
} else {
    Write-Host "  Aucune règle à supprimer" -ForegroundColor $Yellow
}

# ============================================
# SUPPRESSION DOSSIER OLLAMA
# ============================================

Write-Host "`n[4/8] Suppression de l'installation Ollama..." -ForegroundColor $Blue
$OllamaPaths = @(
    "$env:USERPROFILE\Downloads\Ollama",
    "$env:LOCALAPPDATA\Programs\Ollama",
    "$env:USERPROFILE\.ollama"
)

foreach ($Path in $OllamaPaths) {
    if (Test-Path $Path) {
        Remove-Item -Path $Path -Recurse -Force
        Write-Host "✓ Supprimé: $Path" -ForegroundColor $Green
    }
}

# ============================================
# NETTOYAGE PATH
# ============================================

Write-Host "`n[5/8] Nettoyage de la variable PATH..." -ForegroundColor $Blue
$CurrentPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
$PathsToRemove = @(
    "$env:USERPROFILE\Downloads\Ollama"
)

$NewPath = $CurrentPath
foreach ($PathToRemove in $PathsToRemove) {
    if ($NewPath -like "*$PathToRemove*") {
        $NewPath = $NewPath -replace [regex]::Escape(";$PathToRemove"), ""
        $NewPath = $NewPath -replace [regex]::Escape("$PathToRemove;"), ""
    }
}

if ($NewPath -ne $CurrentPath) {
    [System.Environment]::SetEnvironmentVariable("Path", $NewPath, "Machine")
    Write-Host "✓ PATH nettoyé" -ForegroundColor $Green
} else {
    Write-Host "  PATH déjà propre" -ForegroundColor $Yellow
}

# Supprimer OLLAMA_HOST
[System.Environment]::SetEnvironmentVariable('OLLAMA_HOST', $null, 'Machine')

# ============================================
# SUPPRESSION CONFIGURATION
# ============================================

Write-Host "`n[6/8] Suppression des configurations..." -ForegroundColor $Blue
$ConfigFiles = @(
    "$env:USERPROFILE\.rag_windows_config"
)

foreach ($File in $ConfigFiles) {
    if (Test-Path $File) {
        Remove-Item -Path $File -Force
        Write-Host "✓ Supprimé: $File" -ForegroundColor $Green
    }
}

# ============================================
# SUPPRESSION DOSSIER RAG (OPTIONNEL)
# ============================================

Write-Host "`n[7/8] Dossier partagé RAG..." -ForegroundColor $Blue
$RagPath = "C:\Users\user\Documents\RAG"

if (Test-Path $RagPath) {
    $DeleteFolder = Read-Host "  Supprimer le dossier $RagPath ? [y/N]"
    if ($DeleteFolder -match '^[Yy]$') {
        Remove-Item -Path $RagPath -Recurse -Force
        Write-Host "✓ Dossier supprimé" -ForegroundColor $Green
    } else {
        Write-Host "  Dossier conservé" -ForegroundColor $Yellow
    }
} else {
    Write-Host "  Dossier inexistant" -ForegroundColor $Yellow
}

# ============================================
# VÉRIFICATION FINALE
# ============================================

Write-Host "`n[8/8] Vérification..." -ForegroundColor $Blue
$Issues = 0

if (Get-Process -Name "ollama" -ErrorAction SilentlyContinue) {
    Write-Host "⚠️  Processus Ollama encore actif" -ForegroundColor $Yellow
    $Issues++
}

if (Get-SmbShare -Name "RAG" -ErrorAction SilentlyContinue) {
    Write-Host "⚠️  Partage SMB encore présent" -ForegroundColor $Yellow
    $Issues++
}

if (Test-Path "$env:USERPROFILE\Downloads\Ollama") {
    Write-Host "⚠️  Dossier Ollama encore présent" -ForegroundColor $Yellow
    $Issues++
}

if ($Issues -eq 0) {
    Write-Host "✓ Nettoyage complet vérifié" -ForegroundColor $Green
} else {
    Write-Host "⚠️  $Issues élément(s) restant(s)" -ForegroundColor $Yellow
}

# ============================================
# RÉSUMÉ
# ============================================

Write-Host "`n╔═══════════════════════════════════════════════╗" -ForegroundColor $Green
Write-Host "║       NETTOYAGE WINDOWS TERMINÉ              ║" -ForegroundColor $Green
Write-Host "╚═══════════════════════════════════════════════╝`n" -ForegroundColor $Green

Write-Host "✅ Éléments supprimés:" -ForegroundColor $Green
Write-Host "  ✓ Processus Ollama"
Write-Host "  ✓ Partage SMB RAG"
Write-Host "  ✓ Règles pare-feu"
Write-Host "  ✓ Installation Ollama"
Write-Host "  ✓ Variable PATH"
Write-Host "  ✓ Variables d'environnement"
Write-Host "  ✓ Configurations"
Write-Host "`n🔄 Prochaine étape: ./setup-windows.ps1`n"