# Workshop: Azure AI Gateway from Scratch

> Build a production-ready AI Gateway using **Azure API Management (APIM)** to secure, observe, and control your AI models.

## 🎯 Workshop Goal

In this workshop you will build an AI Gateway step by step that:

- Protects **Microsoft Foundry** models behind an API Management gateway
- Implements **token rate limiting** to control costs
- Adds **content safety** filters to block harmful content
- Configures **load balancing** across multiple backends

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
│   ├── main.bicep                     # Main deployment template (conditional flags)
│   ├── main.bicepparam                # Default parameters (Lab 1 baseline)
│   ├── all-features.bicepparam        # Full deployment — all features at once
│   └── modules/
│       ├── apim.bicep                 # API Management (Basicv2) + logger
│       ├── foundry.bicep              # Microsoft Foundry (AI Services) + model
│       ├── app-insights.bicep         # Application Insights + Log Analytics
│       ├── role-assignment.bicep      # RBAC role assignments
│       └── apim-api.bicep             # Backend, API import, policy, subscription
├── labs/                              # Workshop labs (each has 3 folded paths)
│   ├── lab-01-deploy-gateway.md
│   ├── lab-02-add-openai-backend.md
│   ├── lab-03-token-rate-limiting.md
│   ├── lab-04-content-safety.md
│   ├── lab-05-load-balancing.md
│   └── lab-06-customer-demo.md
├── policies/                          # APIM Policy XML files (incremental)
│   ├── base-policy.xml                # Empty base (Lab 1)
│   ├── managed-identity-auth.xml      # Managed identity auth (Lab 2)
│   ├── token-rate-limit.xml           # + Token rate limiting (Lab 3)
│   ├── content-safety.xml             # + Content safety (Lab 4)
│   ├── load-balancing.xml             # + Load balancing + retry (Lab 5)
│   └── demo.xml                       # All features combined (Lab 6 / quick deploy)
└── scripts/
    ├── deploy.ps1                     # Full deployment script
    ├── setup-environment.ps1          # Environment setup
    └── test-gateway.ps1               # Test the gateway endpoint
```

## 🚀 Getting Started

Every lab includes **three paths** — choose the one that fits your audience. Each path is folded inside the lab using collapsible sections so you can switch freely.

| Path | Icon | Approach | Best for |
|------|------|----------|----------|
| **Portal** | 🖥️ | Click through the Azure Portal UI | Visual learners, demos |
| **CLI** | 💻 | Azure CLI commands in PowerShell | Developers, automation |
| **Bicep** | 🔧 | `az deployment group create` with Bicep | IaC teams, repeatability |

### Start the workshop

👉 **[Lab 1 — Deploy the AI Gateway](labs/lab-01-deploy-gateway.md)** — then follow each lab in order.

### Quick Start: Deploy Everything at Once

Want to skip the step-by-step labs and deploy the full gateway with all features? Use the all-features parameter file:

```powershell
az login

$RESOURCE_GROUP = "rg-aigateway-workshop"
az group create --name $RESOURCE_GROUP --location swedencentral

cd infra
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters all-features.bicepparam
```

This single deployment creates everything: APIM, two Foundry instances, RBAC, backends, API, and the full demo policy with managed identity auth, token rate limiting, content safety, and load balancing.

After deploying, jump to [Lab 6 — Customer Demo](labs/lab-06-customer-demo.md) to see all features in action.

## 📚 Workshop Labs

Each lab below contains 🖥️ Portal, 💻 CLI, and 🔧 Bicep paths as collapsible sections.

| # | Lab | Topic |
|---|-----|-------|
| 1 | [Deploy the AI Gateway](labs/lab-01-deploy-gateway.md) | APIM Basicv2, Foundry, App Insights, RBAC |
| 2 | [Microsoft Foundry Backend](labs/lab-02-add-openai-backend.md) | Backend, API import, managed identity policy |
| 3 | [Token Rate Limiting](labs/lab-03-token-rate-limiting.md) | Limit tokens per minute per subscription |
| 4 | [Content Safety](labs/lab-04-content-safety.md) | Block harmful content + jailbreak detection |
| 5 | [Load Balancing](labs/lab-05-load-balancing.md) | Multi-region backend pool with retry |
| 6 | [Customer Demo](labs/lab-06-customer-demo.md) | Guided demo of all capabilities |

## 🔧 Bicep Modules

| Module | Purpose |
|--------|---------|
| `main.bicep` | Orchestrator with conditional deployment flags |
| `main.bicepparam` | Default parameters (Lab 1 baseline) |
| `all-features.bicepparam` | Deploy everything at once — all features enabled |
| `modules/apim.bicep` | API Management (Basicv2) with managed identity |
| `modules/foundry.bicep` | Microsoft Foundry (AI Services) + model deployment |
| `modules/app-insights.bicep` | Application Insights + Log Analytics workspace |
| `modules/role-assignment.bicep` | RBAC role assignments |
| `modules/apim-api.bicep` | Backend, API, policy, subscription, diagnostic |

## 🔗 References

- [Azure AI Gateway Samples (aka.ms/aigateway)](https://github.com/Azure-Samples/AI-Gateway)
- [GenAI Gateway Capabilities](https://learn.microsoft.com/azure/api-management/genai-gateway-capabilities)
- [APIM + Azure OpenAI](https://learn.microsoft.com/azure/api-management/azure-openai-api-from-specification)
- [Token Limits & LLM Logs](https://learn.microsoft.com/azure/api-management/api-management-howto-llm-logs)
- [Content Safety Policies](https://learn.microsoft.com/azure/api-management/llm-content-safety-policy)
- [APIM Policies Reference](https://learn.microsoft.com/azure/api-management/api-management-policies)

## 📄 License

MIT License - Free to use for workshops and training.
