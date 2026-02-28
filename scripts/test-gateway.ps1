# ===========================================================================
# Test Gateway - Azure AI Gateway Workshop
# Sends a test request through the APIM gateway to Azure OpenAI
# ===========================================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$Question = "Wat is Azure API Management in 1 zin?"
)

$ErrorActionPreference = "Stop"

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Test AI Gateway" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Get APIM info
$APIM_NAME = az apim list -g $ResourceGroup --query "[0].name" -o tsv
$GATEWAY_URL = az apim show --name $APIM_NAME -g $ResourceGroup --query "gatewayUrl" -o tsv

Write-Host "Gateway: $GATEWAY_URL" -ForegroundColor White
Write-Host "APIM: $APIM_NAME" -ForegroundColor White

# Get or create subscription key
$subExists = az apim subscription show -g $ResourceGroup --service-name $APIM_NAME --subscription-id "test-sub" --query "primaryKey" -o tsv 2>$null
if (-not $subExists) {
    Write-Host "Creating test subscription..." -ForegroundColor Yellow
    az apim subscription create `
        --resource-group $ResourceGroup `
        --service-name $APIM_NAME `
        --subscription-id "test-sub" `
        --display-name "Test Subscription" `
        --scope "/apis" `
        --output none
}

$SUB_KEY = az apim subscription show -g $ResourceGroup --service-name $APIM_NAME --subscription-id "test-sub" --query "primaryKey" -o tsv

Write-Host ""
Write-Host "Sending request: '$Question'" -ForegroundColor Cyan
Write-Host ""

$body = @{
    messages = @(
        @{
            role = "user"
            content = $Question
        }
    )
    model = "gpt-4o-mini"
    max_tokens = 200
} | ConvertTo-Json -Depth 5

$headers = @{
    "Ocp-Apim-Subscription-Key" = $SUB_KEY
    "Content-Type" = "application/json"
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()

try {
    $response = Invoke-WebRequest `
        -Uri "$GATEWAY_URL/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21" `
        -Method POST `
        -Headers $headers `
        -Body $body

    $sw.Stop()
    
    $result = $response.Content | ConvertFrom-Json
    
    Write-Host "Status: $($response.StatusCode) OK" -ForegroundColor Green
    Write-Host "Latency: $($sw.ElapsedMilliseconds)ms" -ForegroundColor White
    Write-Host ""
    Write-Host "Response:" -ForegroundColor Yellow
    Write-Host $result.choices[0].message.content -ForegroundColor White
    Write-Host ""
    
    # Show usage
    if ($result.usage) {
        Write-Host "Token Usage:" -ForegroundColor Yellow
        Write-Host "  Prompt tokens:     $($result.usage.prompt_tokens)" -ForegroundColor White
        Write-Host "  Completion tokens: $($result.usage.completion_tokens)" -ForegroundColor White
        Write-Host "  Total tokens:      $($result.usage.total_tokens)" -ForegroundColor White
    }

    # Show rate limit headers
    if ($response.Headers['X-Tokens-Remaining']) {
        Write-Host "  Tokens remaining:  $($response.Headers['X-Tokens-Remaining'])" -ForegroundColor White
    }
}
catch {
    $sw.Stop()
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        Write-Host "Status: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
    }
}

Write-Host ""
