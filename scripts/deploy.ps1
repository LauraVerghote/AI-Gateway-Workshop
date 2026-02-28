# ===========================================================================
# Deploy Script - Azure AI Gateway Workshop
# Deploys all infrastructure resources to Azure
# ===========================================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$Location = "swedencentral",

    [Parameter(Mandatory = $false)]
    [string]$PublisherEmail = "workshop@contoso.com",

    [Parameter(Mandatory = $false)]
    [string]$PublisherName = "AI Gateway Workshop",

    [Parameter(Mandatory = $false)]
    [switch]$EnableSecondaryOpenAi
)

$ErrorActionPreference = "Stop"

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Azure AI Gateway Workshop - Deployment" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Check Azure CLI
Write-Host "[1/6] Checking Azure CLI..." -ForegroundColor Yellow
$azVersion = az version --output json | ConvertFrom-Json
Write-Host "  Azure CLI version: $($azVersion.'azure-cli')" -ForegroundColor Green

# Check login status
Write-Host "[2/6] Checking Azure login..." -ForegroundColor Yellow
$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "  Not logged in. Running az login..." -ForegroundColor Yellow
    az login
    $account = az account show --output json | ConvertFrom-Json
}
Write-Host "  Subscription: $($account.name) ($($account.id))" -ForegroundColor Green

# Create resource group
Write-Host "[3/6] Creating resource group '$ResourceGroup' in '$Location'..." -ForegroundColor Yellow
az group create --name $ResourceGroup --location $Location --output none
Write-Host "  Resource group created." -ForegroundColor Green

# Deploy infrastructure
Write-Host "[4/6] Deploying infrastructure (this may take 5-10 minutes)..." -ForegroundColor Yellow
$deployParams = @(
    "--resource-group", $ResourceGroup,
    "--template-file", "$PSScriptRoot/../infra/main.bicep",
    "--parameters", "location=$Location",
    "--parameters", "apimPublisherEmail=$PublisherEmail",
    "--parameters", "apimPublisherName=$PublisherName",
    "--parameters", "enableSecondaryOpenAi=$($EnableSecondaryOpenAi.IsPresent.ToString().ToLower())"
)

$deployment = az deployment group create @deployParams --output json | ConvertFrom-Json
Write-Host "  Infrastructure deployed successfully!" -ForegroundColor Green

# Extract outputs
Write-Host "[5/6] Extracting deployment outputs..." -ForegroundColor Yellow
$outputs = $deployment.properties.outputs
$gatewayUrl = $outputs.apimGatewayUrl.value
$apimName = $outputs.apimName.value
$openAiEndpoint = $outputs.openAiPrimaryEndpoint.value

Write-Host "  APIM Gateway URL: $gatewayUrl" -ForegroundColor Green
Write-Host "  APIM Name: $apimName" -ForegroundColor Green
Write-Host "  OpenAI Endpoint: $openAiEndpoint" -ForegroundColor Green

# Create APIM backends
Write-Host "[6/6] Configuring APIM backends..." -ForegroundColor Yellow

# OpenAI chat backend
az apim backend create `
    --resource-group $ResourceGroup `
    --service-name $apimName `
    --backend-id "openai-backend" `
    --protocol "http" `
    --url "${openAiEndpoint}openai" `
    --output none 2>$null

# OpenAI embeddings backend  
az apim backend create `
    --resource-group $ResourceGroup `
    --service-name $apimName `
    --backend-id "embeddings-backend" `
    --protocol "http" `
    --url "${openAiEndpoint}openai/deployments/text-embedding-3-small" `
    --output none 2>$null

Write-Host "  Backends configured." -ForegroundColor Green

# Summary
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Deployment Complete!" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Resource Group:  $ResourceGroup" -ForegroundColor White
Write-Host "  Location:        $Location" -ForegroundColor White
Write-Host "  Gateway URL:     $gatewayUrl" -ForegroundColor White
Write-Host "  APIM Name:       $apimName" -ForegroundColor White
Write-Host "  OpenAI Endpoint: $openAiEndpoint" -ForegroundColor White
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Yellow
Write-Host "  1. Start with Lab 1: labs/lab-01-deploy-gateway/README.md" -ForegroundColor White
Write-Host "  2. Or test the gateway: .\scripts\test-gateway.ps1 -ResourceGroup $ResourceGroup" -ForegroundColor White
Write-Host ""
