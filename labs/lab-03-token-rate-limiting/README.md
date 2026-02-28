# Lab 3: Token Rate Limiting

> Beperk het token-verbruik per minuut om kosten te beheersen en misbruik te voorkomen

## Doel

In deze lab:
- Configureer je **token rate limiting** per subscription
- Test je dat requests worden geblokkeerd bij overschrijding (HTTP 429)
- Leer je de `remainingTokens` response header lezen
- Experimenteer je met verschillende limieten

## Achtergrond

Token rate limiting is cruciaal voor AI Gateway scenarios:

| Probleem | Oplossing |
|----------|-----------|
| Eén gebruiker verbruikt al je quota | Limiet per subscription/IP |
| Onverwacht hoge kosten | Hard token maximum per minuut |
| DDoS/misbruik | Automatische blokkering bij overschrijding |

## Stappen

### Stap 1: Pas de Token Rate Limit Policy toe

```xml
<!-- policies/token-rate-limit.xml -->
<policies>
    <inbound>
        <base />
        <!-- Authenticeer met managed identity -->
        <authentication-managed-identity 
            resource="https://cognitiveservices.azure.com" 
            output-token-variable-name="managed-id-access-token" 
            ignore-error="false" />
        <set-header name="Authorization" exists-action="override">
            <value>@("Bearer " + (string)context.Variables["managed-id-access-token"])</value>
        </set-header>
        <set-backend-service backend-id="openai-backend" />
        
        <!-- Token rate limiting: max 500 tokens per minuut per subscription -->
        <azure-openai-token-limit 
            counter-key="@(context.Subscription.Id)"
            tokens-per-minute="500" 
            estimate-prompt-tokens="false" 
            remaining-tokens-variable-name="remainingTokens" />
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <!-- Toon remaining tokens in response header -->
        <set-header name="X-Tokens-Remaining" exists-action="override">
            <value>@(context.Variables.GetValueOrDefault<int>("remainingTokens", 0).ToString())</value>
        </set-header>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

### Stap 2: Apply de policy

```powershell
$RESOURCE_GROUP = "rg-aigateway-workshop"
$APIM_NAME = az apim list -g $RESOURCE_GROUP --query "[0].name" -o tsv

az apim api policy create `
  --resource-group $RESOURCE_GROUP `
  --service-name $APIM_NAME `
  --api-id "azure-openai-api" `
  --xml-file "../../policies/token-rate-limit.xml"
```

### Stap 3: Test de rate limiting

```powershell
$GATEWAY_URL = az apim show --name $APIM_NAME -g $RESOURCE_GROUP --query "gatewayUrl" -o tsv
$SUB_KEY = az apim subscription show -g $RESOURCE_GROUP --service-name $APIM_NAME --subscription-id "test-sub" --query "primaryKey" -o tsv

# Stuur meerdere requests om de limiet te bereiken
for ($i = 1; $i -le 5; $i++) {
    Write-Host "`n--- Request $i ---" -ForegroundColor Cyan
    
    $body = @{
        messages = @(@{ role = "user"; content = "Schrijf een lang verhaal over Azure." })
        model = "gpt-4o-mini"
        max_tokens = 200
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-WebRequest `
            -Uri "$GATEWAY_URL/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21" `
            -Method POST `
            -Headers @{ 
                "Ocp-Apim-Subscription-Key" = $SUB_KEY
                "Content-Type" = "application/json" 
            } `
            -Body $body

        Write-Host "Status: $($response.StatusCode)" -ForegroundColor Green
        Write-Host "Tokens remaining: $($response.Headers['X-Tokens-Remaining'])"
    }
    catch {
        Write-Host "Status: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        if ($_.Exception.Response.StatusCode.value__ -eq 429) {
            Write-Host "Rate limit bereikt! ✅ Werkt correct." -ForegroundColor Yellow
        }
    }
}
```

### Stap 4: Experimenteer met parameters

Pas de policy aan en test:

| Parameter | Waarde | Effect |
|-----------|--------|--------|
| `tokens-per-minute` | 100 | Zeer restrictief - snel 429 |
| `tokens-per-minute` | 5000 | Normaal gebruik |
| `tokens-per-minute` | 50000 | Hoog volume |
| `estimate-prompt-tokens` | true | Sneller maar minder nauwkeurig |
| `counter-key` | `Request.IpAddress` | Limiet per IP i.p.v. subscription |

## Verwacht resultaat

- ✅ Eerste requests slagen (HTTP 200) met `X-Tokens-Remaining` header
- ✅ Na overschrijding krijg je HTTP 429 (Too Many Requests)
- ✅ Na 1 minuut reset de counter en kun je weer requests doen

## Referenties

- [Azure OpenAI Token Limit Policy](https://learn.microsoft.com/azure/api-management/azure-openai-token-limit-policy)
- [Token Rate Limiting Lab](https://github.com/Azure-Samples/AI-Gateway/tree/main/labs/token-rate-limiting)

---
**Vorige lab:** [← Lab 2 - OpenAI Backend](../lab-02-add-openai-backend/README.md)  
**Volgende lab:** [Lab 4 - Semantic Caching →](../lab-04-semantic-caching/README.md)
