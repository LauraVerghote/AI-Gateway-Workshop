# Workshop: Azure AI Gateway from Scratch

> Build a production-ready AI Gateway using **Azure API Management (APIM)** to secure, observe, and control your AI models.

## 🎯 Workshop Doel

In deze workshop bouw je stap voor stap een AI Gateway die:

- **Azure OpenAI** modellen beschermt achter een API Management gateway
- **Token rate limiting** implementeert om kosten te beheersen
- **Semantic caching** inschakelt om kosten te verlagen (60-80% besparing)
- **Content safety** filters toevoegt om schadelijke content te blokkeren
- **Load balancing** configureert over meerdere backends
- **Monitoring** opzet met Application Insights en token metrics

## 📋 Vereisten

- Azure subscription ([gratis account](https://azure.microsoft.com/free/))
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (v2.60+)
- [Bicep CLI](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install) (meegeleverd met Azure CLI)
- [VS Code](https://code.visualstudio.com/) met [Bicep extensie](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep)
- [Git](https://git-scm.com/)
- Optioneel: [GitHub CLI](https://cli.github.com/) (`gh`)

## 📁 Projectstructuur

```
Dev-ai-gateway/
├── README.md                          # Deze file
├── infra/                             # Bicep Infrastructure-as-Code
│   ├── main.bicep                     # Hoofd deployment template
│   ├── main.bicepparam                # Parameters
│   └── modules/
│       ├── apim.bicep                 # API Management instance
│       ├── openai.bicep               # Azure OpenAI resource
│       ├── app-insights.bicep         # Application Insights
│       └── role-assignment.bicep      # RBAC role assignments
├── labs/
│   ├── lab-01-deploy-gateway/         # Lab 1: Deploy de AI Gateway
│   ├── lab-02-add-openai-backend/     # Lab 2: Voeg Azure OpenAI toe als backend
│   ├── lab-03-token-rate-limiting/    # Lab 3: Token Rate Limiting
│   ├── lab-04-semantic-caching/       # Lab 4: Semantic Caching
│   ├── lab-05-content-safety/         # Lab 5: Content Safety
│   ├── lab-06-load-balancing/         # Lab 6: Load Balancing met Retry
│   └── lab-07-monitoring/             # Lab 7: Monitoring & Token Metrics
├── policies/                          # APIM Policy XML bestanden
│   ├── token-rate-limit.xml
│   ├── semantic-cache.xml
│   ├── content-safety.xml
│   ├── load-balancing.xml
│   └── managed-identity-auth.xml
└── scripts/
    ├── deploy.ps1                     # Volledige deployment script
    ├── setup-environment.ps1          # Environment setup
    └── test-gateway.ps1               # Test het gateway endpoint
```

## 🚀 Quick Start

```powershell
# 1. Clone de repository
git clone https://github.com/<your-org>/Dev-ai-gateway.git
cd Dev-ai-gateway

# 2. Login bij Azure
az login

# 3. Stel je subscription in
az account set --subscription "<subscription-id>"

# 4. Deploy de volledige infrastructuur
.\scripts\deploy.ps1 -ResourceGroup "rg-aigateway-workshop" -Location "swedencentral"
```

## 📚 Workshop Modules

| # | Lab | Duur | Onderwerp |
|---|-----|------|-----------|
| 1 | [Deploy de AI Gateway](labs/lab-01-deploy-gateway/README.md) | 15 min | APIM Basicv2 + resource group deployen |
| 2 | [Azure OpenAI Backend](labs/lab-02-add-openai-backend/README.md) | 20 min | OpenAI koppelen als backend met managed identity |
| 3 | [Token Rate Limiting](labs/lab-03-token-rate-limiting/README.md) | 15 min | Tokens per minuut limiteren |
| 4 | [Semantic Caching](labs/lab-04-semantic-caching/README.md) | 20 min | Vergelijkbare prompts cachen |
| 5 | [Content Safety](labs/lab-05-content-safety/README.md) | 15 min | Schadelijke content filteren |
| 6 | [Load Balancing](labs/lab-06-load-balancing/README.md) | 15 min | Verdeel load over meerdere backends |
| 7 | [Monitoring & Metrics](labs/lab-07-monitoring/README.md) | 15 min | Token metrics en Application Insights |

**Totale workshopduur: ~2 uur**

## 🔗 Referenties

- [Azure AI Gateway Samples (aka.ms/aigateway)](https://github.com/Azure-Samples/AI-Gateway)
- [GenAI Gateway Capabilities](https://learn.microsoft.com/azure/api-management/genai-gateway-capabilities)
- [APIM + Azure OpenAI](https://learn.microsoft.com/azure/api-management/azure-openai-api-from-specification)
- [Semantic Caching Docs](https://learn.microsoft.com/azure/api-management/azure-openai-enable-semantic-caching)
- [Token Limits & LLM Logs](https://learn.microsoft.com/azure/api-management/api-management-howto-llm-logs)
- [Content Safety Policies](https://learn.microsoft.com/azure/api-management/llm-content-safety-policy)
- [APIM Policies Reference](https://learn.microsoft.com/azure/api-management/api-management-policies)

## 📄 Licentie

MIT License - Vrij te gebruiken voor workshops en trainingen.
