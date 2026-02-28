# ===========================================================================
# Environment Setup - Azure AI Gateway Workshop
# Verifies prerequisites and sets up the development environment
# ===========================================================================

$ErrorActionPreference = "Stop"

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Environment Setup Check" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

$allGood = $true

# Check Azure CLI
Write-Host "Checking Azure CLI..." -NoNewline
try {
    $azVersion = (az version --output json | ConvertFrom-Json).'azure-cli'
    Write-Host " v$azVersion" -ForegroundColor Green
} catch {
    Write-Host " NOT FOUND" -ForegroundColor Red
    Write-Host "  Install: https://learn.microsoft.com/cli/azure/install-azure-cli" -ForegroundColor Yellow
    $allGood = $false
}

# Check Git
Write-Host "Checking Git..." -NoNewline
try {
    $gitVersion = git --version
    Write-Host " $gitVersion" -ForegroundColor Green
} catch {
    Write-Host " NOT FOUND" -ForegroundColor Red
    Write-Host "  Install: https://git-scm.com/" -ForegroundColor Yellow
    $allGood = $false
}

# Check GitHub CLI (optional)
Write-Host "Checking GitHub CLI..." -NoNewline
try {
    $ghVersion = gh --version | Select-Object -First 1
    Write-Host " $ghVersion" -ForegroundColor Green
} catch {
    Write-Host " NOT FOUND (optional)" -ForegroundColor Yellow
    Write-Host "  Install: https://cli.github.com/" -ForegroundColor Yellow
}

# Check Bicep
Write-Host "Checking Bicep CLI..." -NoNewline
try {
    $bicepVersion = az bicep version 2>&1
    Write-Host " $bicepVersion" -ForegroundColor Green
} catch {
    Write-Host " NOT FOUND" -ForegroundColor Red
    Write-Host "  Install: az bicep install" -ForegroundColor Yellow
    $allGood = $false
}

# Check Azure login
Write-Host "Checking Azure login..." -NoNewline
try {
    $account = az account show --output json 2>$null | ConvertFrom-Json
    Write-Host " $($account.name)" -ForegroundColor Green
} catch {
    Write-Host " NOT LOGGED IN" -ForegroundColor Red
    Write-Host "  Run: az login" -ForegroundColor Yellow
    $allGood = $false
}

Write-Host ""
if ($allGood) {
    Write-Host "All prerequisites met! You're ready to start the workshop." -ForegroundColor Green
} else {
    Write-Host "Some prerequisites are missing. Please install them before continuing." -ForegroundColor Red
}
Write-Host ""
