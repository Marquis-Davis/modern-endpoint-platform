# AI Platform Engineering Reference

A quick reference for translating familiar Windows Endpoint / Azure concepts into AI Platform Engineering concepts.

| Endpoint / Platform World | AI Platform World |
|---|---|
| Windows | LLM (Large Language Model) |
| Microsoft builds Windows | OpenAI / Microsoft / Anthropic / others build models |
| ConfigMgr / Intune / Azure | Microsoft Foundry |
| Windows device | AI application / agent |
| Windows build / version | Model / version |
| Policies / configuration | Agent instructions / guardrails |
| Apps / scripts | Agent tools |
| Microsoft Graph / API (Application Programming Interface) | Agent APIs / tools |
| Company documentation | RAG (Retrieval-Augmented Generation) knowledge |
| Entra ID / RBAC (Role-Based Access Control) | AI identity / RBAC / security |
| Log Analytics | AI monitoring / observability |

## Mental Model

You do not build Windows from scratch to be a Windows Platform Engineer. Microsoft provides Windows, and you deploy, configure, secure, automate, integrate, monitor, and govern it.

AI Platform Engineering follows a similar pattern:

1. A provider supplies an LLM (Large Language Model).
2. Microsoft Foundry provides the platform for building and operating AI applications and agents.
3. You select and deploy a model.
4. You configure agent instructions and guardrails.
5. You ground the agent with trusted knowledge.
6. RAG (Retrieval-Augmented Generation) can retrieve relevant knowledge at runtime and provide it to the model.
7. Tools and APIs (Application Programming Interfaces) allow the agent to interact with external systems.
8. Entra ID and RBAC (Role-Based Access Control) help secure access.
9. Monitoring and observability help operate the AI system.

## Endpoint Troubleshooting Assistant Direction

```text
Engineer
   |
   v
AI Agent
   |
   +--> LLM (Large Language Model)
   |
   +--> RAG (Retrieval-Augmented Generation)
   |       |
   |       +--> Troubleshooting documentation
   |       +--> Known errors
   |       +--> Engineering procedures
   |
   +--> Tools / APIs
           |
           +--> Microsoft Graph
           +--> Intune
           +--> Entra ID
           +--> Automation
```

### Key distinction

**RAG (Retrieval-Augmented Generation) = KNOW**

It retrieves trusted information and supplies it to the model as context. It does not retrain the underlying model.

**Tools / APIs (Application Programming Interfaces) = DO**

They give the agent controlled capabilities to query or perform actions in external systems.

**Grounding = the goal**

Grounding means making the AI base its response on trusted information. RAG (Retrieval-Augmented Generation) is one technique for grounding an AI system.
