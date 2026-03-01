# Workshop: Azure AI Gateway from Scratch

> Build a production-ready AI Gateway using **Azure API Management (APIM)** to secure, observe, and control your AI models.

## 🎯 Workshop Goal

In this workshop you will build an AI Gateway step by step that:

- Protects **Azure OpenAI** models behind an API Management gateway
- Implements **token rate limiting** to control costs
- Enables **semantic caching** to reduce costs (60-80% savings)
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
│       ├── openai.bicep               # Azure OpenAI resource
│       ├── app-insights.bicep         # Application Insights
│       └── role-assignment.bicep      # RBAC role assignments
├── labs/
│   ├── lab-01-deploy-gateway/         # Lab 1: Deploy the AI Gateway
│   ├── lab-02-add-openai-backend/     # Lab 2: Add Azure OpenAI as backend
│   ├── lab-03-token-rate-limiting/    # Lab 3: Token Rate Limiting
│   ├── lab-04-semantic-caching/       # Lab 4: Semantic Caching
│   ├── lab-05-content-safety/         # Lab 5: Content Safety
│   ├── lab-06-load-balancing/         # Lab 6: Load Balancing with Retry
│   └── lab-07-monitoring/             # Lab 7: Monitoring & Token Metrics
├── policies/                          # APIM Policy XML files
│   ├── token-rate-limit.xml
│   ├── semantic-cache.xml
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

Start directly with [Lab 1](labs/lab-01-deploy-gateway/README.md) and follow each lab in order. You will deploy and configure each component yourself, learning what each piece does.

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
| **Azure OpenAI** | GPT-4o-mini and text-embedding-3-small model deployments |
| **Application Insights + Log Analytics** | Monitoring and logging for the gateway |
| **RBAC role assignment** | Grants APIM's managed identity the "Cognitive Services OpenAI User" role on the OpenAI resource |
| **APIM backends** | Pre-configured `openai-backend` and `embeddings-backend` pointing to the OpenAI endpoint |

> After running this, you can skip to [Lab 3 - Token Rate Limiting](labs/lab-03-token-rate-limiting/README.md). Labs 1-2 are still worth reading to understand the architecture.

## 📚 Workshop Modules

| # | Lab | Duration | Topic |
|---|-----|----------|-------|
| 1 | [Deploy the AI Gateway](labs/lab-01-deploy-gateway/README.md) | 15 min | Deploy APIM Basicv2 + resource group |
| 2 | [Azure OpenAI Backend](labs/lab-02-add-openai-backend/README.md) | 20 min | Connect OpenAI as backend with managed identity |
| 3 | [Token Rate Limiting](labs/lab-03-token-rate-limiting/README.md) | 15 min | Limit tokens per minute |
| 4 | [Semantic Caching](labs/lab-04-semantic-caching/README.md) | 20 min | Cache similar prompts |
| 5 | [Content Safety](labs/lab-05-content-safety/README.md) | 15 min | Filter harmful content |
| 6 | [Load Balancing](labs/lab-06-load-balancing/README.md) | 15 min | Distribute load across multiple backends |
| 7 | [Monitoring & Metrics](labs/lab-07-monitoring/README.md) | 15 min | Token metrics and Application Insights |

**Total workshop duration: ~2 hours**

## 🔗 References

- [Azure AI Gateway Samples (aka.ms/aigateway)](https://github.com/Azure-Samples/AI-Gateway)
- [GenAI Gateway Capabilities](https://learn.microsoft.com/azure/api-management/genai-gateway-capabilities)
- [APIM + Azure OpenAI](https://learn.microsoft.com/azure/api-management/azure-openai-api-from-specification)
- [Semantic Caching Docs](https://learn.microsoft.com/azure/api-management/azure-openai-enable-semantic-caching)
- [Token Limits & LLM Logs](https://learn.microsoft.com/azure/api-management/api-management-howto-llm-logs)
- [Content Safety Policies](https://learn.microsoft.com/azure/api-management/llm-content-safety-policy)
- [APIM Policies Reference](https://learn.microsoft.com/azure/api-management/api-management-policies)

## 📄 License

MIT License - Free to use for workshops and training.
