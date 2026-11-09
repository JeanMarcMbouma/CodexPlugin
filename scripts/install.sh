#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo 'Usage: bash install.sh [--organization NAME] [--auth interactive|azcli] [--client auto|codex|claude|all] [--source SOURCE] [--replace]'
}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

organization=''
auth=interactive
client=auto
source=JeanMarcMbouma/CodexPlugin
replace=false
marketplace=azure-devops-local
plugin=azure-devops@$marketplace
connection=azure-devops

while [[ $# -gt 0 ]]; do
  case "$1" in
    --organization) [[ $# -ge 2 ]] || fail 'Missing organization name.'; organization=$2; shift 2 ;;
    --auth) [[ $# -ge 2 ]] || fail 'Missing authentication mode.'; auth=$2; shift 2 ;;
    --client) [[ $# -ge 2 ]] || fail 'Missing client.'; client=$2; shift 2 ;;
    --source) [[ $# -ge 2 ]] || fail 'Missing marketplace source.'; source=$2; shift 2 ;;
    --replace) replace=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; fail "Unknown option: $1" ;;
  esac
done

[[ "$auth" == interactive || "$auth" == azcli ]] || fail 'Use --auth interactive or --auth azcli.'
case "$client" in
  all) clients=(codex claude) ;;
  codex|claude) clients=("$client") ;;
  auto)
    clients=()
    for candidate in codex claude; do
      if command -v "$candidate" >/dev/null; then clients+=("$candidate"); fi
    done
    [[ ${#clients[@]} -gt 0 ]] || fail 'Install the Codex CLI or Claude Code and add it to PATH, or pass --client.'
    ;;
  *) fail 'Use --client auto, codex, claude or all.' ;;
esac

for command_name in "${clients[@]}" git node npx; do
  command -v "$command_name" >/dev/null || fail "Install $command_name and add it to PATH."
done
node -e 'process.exit(parseInt(process.versions.node, 10) >= 20 ? 0 : 1)' || fail 'Install Node.js 20 or later.'
if [[ "$auth" == azcli ]]; then
  command -v az >/dev/null || fail 'Install Azure CLI and run az login.'
fi

if [[ -z "$organization" ]]; then
  [[ -t 0 ]] || fail 'Pass --organization NAME when running without a terminal.'
  read -r -p 'Azure DevOps organization name: ' organization
fi
[[ "$organization" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || fail 'Enter the organization name from dev.azure.com/NAME.'

if [[ -d "$source" ]]; then
  source=$(cd "$source" && pwd)
fi

server_args=(--yes @azure-devops/mcp@2.11.0 "$organization" --authentication "$auth" -d core work work-items repositories pipelines search)

# Claude Code on native Windows (Git Bash, MSYS, Cygwin) starts npx through cmd.
# Keep Git Bash from rewriting the /c switch into a drive path for these calls.
claude_command=(npx "${server_args[@]}")
no_path_conversion=()
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    claude_command=(cmd /c npx "${server_args[@]}")
    no_path_conversion=(env MSYS_NO_PATHCONV=1 'MSYS2_ARG_CONV_EXCL=*')
    ;;
esac

contains_client() {
  local name
  for name in "${clients[@]}"; do [[ "$name" == "$1" ]] && return 0; done
  return 1
}

# Check every selected client before changing any configuration.
codex_connection=absent
claude_connection=absent
if contains_client codex; then
  servers=$(codex mcp list --json)
  codex_connection=$(node -e '
    const fs = require("node:fs");
    const servers = JSON.parse(fs.readFileSync(0, "utf8"));
    const server = servers.find(({name}) => name === "azure-devops");
    if (!server) {
      console.log("absent");
    } else {
      const {transport} = server;
      const matches = server.enabled && transport.type === "stdio" &&
        transport.command === "npx" && JSON.stringify(transport.args) === JSON.stringify(process.argv.slice(1));
      console.log(matches ? "match" : "different");
    }
  ' -- "${server_args[@]}" <<< "$servers")
  if [[ "$codex_connection" == different && "$replace" != true ]]; then
    fail 'A different azure-devops MCP connection exists in codex. Use --replace to replace it.'
  fi
fi
if contains_client claude; then
  claude_connection=$(${no_path_conversion[@]+"${no_path_conversion[@]}"} node -e '
    const fs = require("node:fs"), path = require("node:path"), os = require("node:os");
    const [name, command, ...args] = process.argv.slice(1);
    const file = path.join(process.env.CLAUDE_CONFIG_DIR || os.homedir(), ".claude.json");
    let server;
    try {
      server = (JSON.parse(fs.readFileSync(file, "utf8")).mcpServers || {})[name];
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
    console.log(!server ? "absent" : (!server.type || server.type === "stdio") && server.command === command &&
      JSON.stringify(server.args || []) === JSON.stringify(args) ? "match" : "different");
  ' -- "$connection" "${claude_command[@]}") || fail 'Could not read the Claude Code configuration.'
  if [[ "$claude_connection" == different && "$replace" != true ]]; then
    fail 'A different azure-devops MCP connection exists in claude. Use --replace to replace it.'
  fi
  marketplaces=$(claude plugin marketplace list --json)
  claude_marketplace=$(node -e '
    const fs = require("node:fs"), path = require("node:path");
    const [name, source] = process.argv.slice(1);
    const entry = JSON.parse(fs.readFileSync(0, "utf8").replace(/^\uFEFF/, "")).find(item => item.name === name);
    const repo = value => String(value || "").trim().replace(/^https:\/\/github\.com\//i, "")
      .replace(/\.git$/i, "").replace(/\/+$/, "").toLowerCase();
    const folder = value => {
      const full = path.resolve(String(value || ""));
      return process.platform === "win32" ? full.toLowerCase() : full;
    };
    let same = false;
    if (entry && entry.source === "github") same = repo(source) === repo(entry.repo);
    else if (entry && entry.source === "directory") same = folder(source) === folder(entry.path);
    else if (entry) same = [entry.url, entry.repo, entry.path].some(value => value && repo(value) === repo(source));
    console.log(!entry ? "absent" : same ? "match" : "different");
  ' -- "$marketplace" "$source" <<< "$marketplaces") || fail 'Could not read the Claude Code marketplaces.'
  if [[ "$claude_marketplace" == different && "$replace" != true ]]; then
    fail "The $marketplace marketplace in claude uses a different source. Use --replace to switch it to $source."
  fi
fi

if contains_client codex; then
  codex plugin marketplace add "$source"
  codex plugin marketplace upgrade "$marketplace"
  codex plugin add "$plugin"
  if [[ "$codex_connection" != match ]]; then
    codex mcp add "$connection" -- npx "${server_args[@]}"
  fi
fi

if contains_client claude; then
  if [[ "$claude_marketplace" == match ]]; then
    claude plugin marketplace update "$marketplace"
  else
    if [[ "$claude_marketplace" == different ]]; then
      # Removing the marketplace also uninstalls its plugins; the plugin is reinstalled below.
      claude plugin marketplace remove "$marketplace"
    fi
    claude plugin marketplace add "$source"
  fi
  if claude plugin list --json | node -e '
    const list = JSON.parse(require("node:fs").readFileSync(0, "utf8"));
    process.exit(list.some(({id}) => id === process.argv[1]) ? 0 : 1);
  ' -- "$plugin"; then
    claude plugin update "$plugin"
  else
    claude plugin install "$plugin"
  fi
  if [[ "$claude_connection" != match ]]; then
    if [[ "$claude_connection" == different ]]; then
      claude mcp remove --scope user "$connection"
    fi
    ${no_path_conversion[@]+"${no_path_conversion[@]}"} claude mcp add --scope user "$connection" -- "${claude_command[@]}"
  fi
fi

names=()
for name in "${clients[@]}"; do
  if [[ "$name" == codex ]]; then names+=(Codex); else names+=('Claude Code'); fi
done
if [[ ${#names[@]} -eq 2 ]]; then joined="${names[0]} or ${names[1]}"; else joined=${names[0]}; fi
echo "Start a new $joined session and ask: List the Azure DevOps projects I can access."
