# Azure DevOps for Codex and Claude Code

Use Codex or Claude Code to triage Azure Boards work items, review Azure Repos pull requests, and diagnose Azure Pipelines failures. The installers add the plugin and configure Microsoft's local Azure DevOps MCP server in your user-level Codex or Claude Code settings.

## Install

You'll need the Codex CLI or Claude Code, Git, Node.js 20 or later, and access to an Azure DevOps Services organization. Run the installer on the same machine and under the same user account as the client. By default it sets up every client it finds on PATH; see [Choose the client](#choose-the-client).

### Windows PowerShell

On a fresh Windows machine, install the prerequisites with WinGet, then open a new PowerShell window.

```powershell
winget install --id OpenAI.Codex --exact --source winget
winget install --id Git.Git --exact --source winget
winget install --id OpenJS.NodeJS.LTS --exact --source winget
```

Install the plugin using [install.ps1](https://raw.githubusercontent.com/JeanMarcMbouma/CodexPlugin/main/scripts/install.ps1).

```powershell
irm 'https://raw.githubusercontent.com/JeanMarcMbouma/CodexPlugin/main/scripts/install.ps1' | iex
```
Or 
```powershell
az login
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/JeanMarcMbouma/CodexPlugin/main/scripts/install.ps1'))) -Organization 'YOUR_ORG' -Auth azcli -Replace
```

### macOS or Linux

```sh
curl -fsSLo install.sh https://raw.githubusercontent.com/JeanMarcMbouma/CodexPlugin/main/scripts/install.sh && bash install.sh
```

Enter the organization name from your Azure DevOps URL. For `https://dev.azure.com/contoso`, enter `contoso`. Start a new Codex session and ask **“List the Azure DevOps projects I can access.”** Complete the Microsoft sign-in prompt on first use.

### Pass the organization or use Azure CLI sign-in

Append `-Organization contoso` to the PowerShell command or `--organization contoso` after `bash install.sh` to skip the prompt. If you already signed in with `az login`, use `-Auth azcli` or `--auth azcli`.

Run the installer again to refresh the plugin. It reuses a matching MCP configuration. To switch organizations or change authentication, rerun with `-Replace` or `--replace`. This replaces the user-level connection named `azure-devops`.

If you installed version 0.1 from a local checkout, remove that marketplace entry with `codex plugin marketplace remove azure-devops-local` before running the installer. Version 0.2 uses the installer-managed connection.

### Choose the client

Use `-Client` (PowerShell) or `--client` (Bash) with `codex`, `claude`, or `all`. The default, `auto`, selects each of `codex` and `claude` found on PATH. Every selected client is checked for a conflicting `azure-devops` connection before any configuration changes.

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/JeanMarcMbouma/CodexPlugin/main/scripts/install.ps1'))) -Organization 'YOUR_ORG' -Auth azcli -Client claude
```

`-Source` or `--source` installs from a fork, a Git URL, or a local checkout instead of `JeanMarcMbouma/CodexPlugin`. If Claude Code already has the `azure-devops-local` marketplace from a different source, the installer stops. Rerun with `-Replace` or `--replace` to switch it. Claude Code uninstalls the plugin when its marketplace is removed, so the installer then reinstalls it from the new source.

## Claude Code

For Claude Code, the installer adds the `azure-devops-local` marketplace, installs `azure-devops@azure-devops-local` at user scope, and adds the user-scope `azure-devops` MCP connection. On Windows, Claude Code starts the server with `cmd /c npx`. Start a new Claude Code session and ask **“List the Azure DevOps projects I can access.”** The skills load automatically for matching requests; you can also invoke them as `/azure-devops:azure-devops-scrum-master` and similar.

On Windows, the `claude` command must be on PATH. A standalone Claude Code installation adds it. The copy bundled with the Claude desktop app lives in a versioned folder that changes with each app update. Add that folder to your shell's PATH at startup rather than hard-coding a version.

To set up Claude Code manually, run the equivalent commands. On macOS or Linux, replace `cmd /c npx` with `npx`.

```sh
claude plugin marketplace add JeanMarcMbouma/CodexPlugin
claude plugin install azure-devops@azure-devops-local
claude mcp add --scope user azure-devops -- cmd /c npx --yes @azure-devops/mcp@2.11.0 YOUR_ORG --authentication azcli -d core work work-items repositories pipelines search
```

Claude Code asks for approval before each MCP tool call. To skip prompts for routine reads, allow specific read tools under `permissions.allow` in `~/.claude/settings.json`, for example `mcp__azure-devops__core_list_projects`. Keep write tools behind approval.

## Private ChatGPT connector

For ChatGPT web, see the [separate read-only connector](chatgpt/README.md). It supports multiple Azure DevOps organizations with a separate server-side PAT for each one.

## Workflow skills

The plugin includes Scrum Master support, backlog refinement, and a bridge for Jira records synchronized with Azure DevOps.

| Skill | Example request |
| --- | --- |
| [Scrum Master support](plugins/azure-devops/skills/azure-devops-scrum-master/SKILL.md) | “Prepare a sprint briefing for Care Team in Fabrikam.” |
| [Backlog refinement](plugins/azure-devops/skills/azure-devops-backlog-refinement/SKILL.md) | “Review the next ten backlog items for grooming and draft acceptance criteria.” |
| [Jira bridge](plugins/azure-devops/skills/azure-devops-jira-bridge/SKILL.md) | “Compare CARE-12 with its linked DevOps work item and draft the change on the owning side.” |

The Scrum and refinement skills discover organization, project, team, backlog level, and process fields before analyzing work. Briefings identify missing evidence. Refinement produces proposed changes and questions for the team. The private ChatGPT connector exposes the same guidance through its `get_workflow_guidance` tool.

## Jira and Azure DevOps bridge

Connect your existing Jira MCP server or the Atlassian plugin alongside the Azure DevOps connection. The Jira bridge skill uses the counterpart references maintained by your sync tool, including custom fields, Azure work item relations, Jira remote links, and description links. If the link field or ownership rule is unclear, it asks for the relevant mapping.

A comparison shows both records, values, and observed differences. A verified mirrored pair counts once in combined reports, with links to both records. Similar titles and generic related links are kept as unverified candidates. For requested edits, the skill resolves the owning system, updates the requested fields there when tools permit, and reports whether propagation is verified, pending, or unavailable.

The private ChatGPT connector supplies Azure DevOps reads and workflow guidance. Jira reads and writes use your separate Jira connection. Its credentials stay with that connection. The skill uses your existing sync tool to propagate mapped edits.

In ChatGPT or Codex, open Plugins or Connectors, find Atlassian, connect the relevant site, and sign in. For other MCP clients, follow the [official Atlassian setup guide](https://developer.atlassian.com/cloud/rovo-mcp/guides/getting-started/). Use your organization's existing Jira connection for a Jira deployment it supports.

## Try it

- “Open the Jira counterpart linked to DevOps work item 42.”
- “Refine these synced stories and show one entry per verified pair.”
- “Show me the active bugs assigned to me in project Dispatch.”
- “Review Azure Repos PR 42 in Dispatch/API and keep any comments as drafts.”
- “Investigate the latest failed Dispatch CI run on main and link me to the failed step.”

Azure DevOps applies the signed-in account's permissions. The workflow reads by default and writes on explicit request.

[Codex plugin packaging and installation](https://developers.openai.com/plugins/build/plugins) · [Microsoft’s local MCP setup for Codex](https://github.com/microsoft/azure-devops-mcp/blob/main/docs/GETTINGSTARTED.md#codex)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, testing, and pull request guidance.

## License

Licensed under the [MIT License](LICENSE).
