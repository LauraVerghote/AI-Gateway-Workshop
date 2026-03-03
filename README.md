# Workshop: Azure AI Gateway from Scratch

> Build a production-ready AI Gateway using **Azure API Management (APIM)** to secure, observe, and control your AI models.

## 🎯 Workshop Goal

In this workshop you will build an AI Gateway step by step that:

- Protects **Microsoft Foundry** models behind an API Management gateway
- Implements **token rate limiting** to control costs
- Adds **content safety** filters to block harmful content
- Configures **load balancing** across multiple backends
- Sets up **monitoring** with Application Insights and token metrics

## 📋 Prerequisites

- Azure subscription ([free account](https://azure.microsoft.com/free/))
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (v2.60+)
- [Bicep CLI](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install) (included with Azure CLI)
- [VS Code](https://code.visualstudio.com/) with [Bicep extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep)
- [Git](https://git-scm.com/)
- Optional: [GitHub CLI](https://cli.github.com/) (`gh`)

## 📁 Project Structure

```
Dev-ai-gateway/
├── README.md                          # This file
├── infra/                             # Bicep Infrastructure-as-Code
│   ├── main.bicep                     # Main deployment template
│   ├── main.bicepparam                # Parameters
│   └── modules/
│       ├── apim.bicep                 # API Management instance
│       ├── foundry.bicep               # Microsoft Foundry resource (Azure AI Services)
│       ├── app-insights.bicep         # Application Insights
│       ├── role-assignment.bicep      # RBAC role assignments
│       └── apim-api.bicep             # APIM API, backend, policy & subscription
├── labs/
│   ├── lab-01-deploy-gateway.md       # Lab 1: Deploy the AI Gateway
│   ├── lab-02-add-openai-backend.md   # Lab 2: Add Microsoft Foundry as backend
│   ├── lab-03-token-rate-limiting.md   # Lab 3: Token Rate Limiting
│   ├── lab-04-content-safety.md        # Lab 4: Content Safety
│   ├── lab-05-load-balancing.md        # Lab 5: Load Balancing with Retry
│   └── lab-06-monitoring.md            # Lab 6: Monitoring & Token Metrics
├── policies/                          # APIM Policy XML files
│   ├── token-rate-limit.xml
│   ├── content-safety.xml
│   ├── load-balancing.xml
│   └── managed-identity-auth.xml
└── scripts/
    ├── deploy.ps1                     # Full deployment script
    ├── setup-environment.ps1          # Environment setup
    └── test-gateway.ps1               # Test the gateway endpoint
```

## 🚀 Getting Started

There are two ways to work through this workshop:

### Option A: Step by step (recommended for learning)

Start directly with [Lab 1](labs/lab-01-deploy-gateway.md) and follow each lab in order. You will deploy and configure each component yourself, learning what each piece does.

### Option B: Quick Start (deploy infrastructure first)

If you prefer to deploy all infrastructure upfront and focus on the **policies** (Labs 3-7), run the deploy script first:

```powershell
# 1. Clone the repository
git clone https://github.com/LauraVerghote/AI-Gateway-Workshop.git
cd AI-Gateway-Workshop

# 2. Login to Azure
az login

# 3. Deploy the full infrastructure
.\scripts\deploy.ps1 -ResourceGroup "rg-aigateway-workshop" -Location "swedencentral"
```

The script deploys the following resources into a single resource group:

| Resource | Description |
|----------|-------------|
| **API Management (Basicv2)** | The AI Gateway itself, with a system-assigned managed identity |
| **Microsoft Foundry** | GPT-4o-mini model deployment |
| **Application Insights + Log Analytics** | Monitoring and logging for the gateway |
| **RBAC role assignment** | Grants APIM's managed identity the "Cognitive Services OpenAI User" role on the Foundry resource |
| **APIM backends** | Pre-configured `openai-backend` pointing to the Foundry endpoint |

> After running this, you can skip to [Lab 3 - Token Rate Limiting](labs/lab-03-token-rate-limiting.md). Labs 1-2 are still worth reading to understand the architecture.

## 📚 Workshop Modules

| # | Lab | Duration | Topic |
|---|-----|----------|-------|
| 1 | [Deploy the AI Gateway](labs/lab-01-deploy-gateway.md) | 15 min | Deploy APIM Basicv2 + resource group |
| 2 | [Microsoft Foundry Backend](labs/lab-02-add-openai-backend.md) | 20 min | Connect Foundry as backend with managed identity |
| 3 | [Token Rate Limiting](labs/lab-03-token-rate-limiting.md) | 15 min | Limit tokens per minute |
| 4 | [Content Safety](labs/lab-04-content-safety.md) | 15 min | Filter harmful content |
| 5 | [Load Balancing](labs/lab-05-load-balancing.md) | 15 min | Distribute load across multiple backends |
| 6 | [Monitoring & Metrics](labs/lab-06-monitoring.md) | 15 min | Token metrics and Application Insights |

**Total workshop duration: ~1.5 hours**

## 🔗 References

- [Azure AI Gateway Samples (aka.ms/aigateway)](https://github.com/Azure-Samples/AI-Gateway)
- [GenAI Gateway Capabilities](https://learn.microsoft.com/azure/api-management/genai-gateway-capabilities)
- [APIM + Azure OpenAI](https://learn.microsoft.com/azure/api-management/azure-openai-api-from-specification)
- [Token Limits & LLM Logs](https://learn.microsoft.com/azure/api-management/api-management-howto-llm-logs)
- [Content Safety Policies](https://learn.microsoft.com/azure/api-management/llm-content-safety-policy)
- [APIM Policies Reference](https://learn.microsoft.com/azure/api-management/api-management-policies)

## 📄 License

MIT License - Free to use for workshops and training.
