#Requires -Version 5.1
[CmdletBinding()]
param(
    [string] $Organization,

    [ValidateSet('interactive', 'azcli')]
    [string] $Auth = 'interactive',

    [ValidateSet('auto', 'codex', 'claude', 'all')]
    [string] $Client = 'auto',

    [string] $Source = 'JeanMarcMbouma/CodexPlugin',

    [switch] $Replace
)

$ErrorActionPreference = 'Stop'
$marketplace = 'azure-devops-local'
$plugin = "azure-devops@$marketplace"
$connection = 'azure-devops'

function Invoke-Cli {
    param([string] $Name, [string[]] $Arguments)
    & $Name @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Name command failed with exit code $LASTEXITCODE."
    }
}

function Test-SameArgs($Actual, $Expected) {
    (ConvertTo-Json -Compress -InputObject @($Actual)) -ceq (ConvertTo-Json -Compress -InputObject @($Expected))
}

# Prints absent, match or different for the user-scope Claude Code MCP connection.
# Keep this script free of double quotes so Windows PowerShell passes it to node intact.
$claudeCheck = "const fs = require('fs'), path = require('path'), os = require('os');" +
    "const [name, command, ...args] = process.argv.slice(1);" +
    "const file = path.join(process.env.CLAUDE_CONFIG_DIR || os.homedir(), '.claude.json');" +
    "let server;" +
    "try { server = (JSON.parse(fs.readFileSync(file, 'utf8')).mcpServers || {})[name]; }" +
    "catch (error) { if (error.code !== 'ENOENT') throw error; }" +
    "console.log(!server ? 'absent' : (!server.type || server.type === 'stdio') && server.command === command &&" +
    " JSON.stringify(server.args || []) === JSON.stringify(args) ? 'match' : 'different');"

# Reads `claude plugin marketplace list --json` on stdin and prints absent, match or different
# for the named marketplace and the requested source. Keep it free of double quotes as above.
$marketplaceCheck = "const fs = require('fs'), path = require('path');" +
    "const [name, source] = process.argv.slice(1);" +
    "const entry = JSON.parse(fs.readFileSync(0, 'utf8').replace(/^\uFEFF/, '')).find(item => item.name === name);" +
    "const repo = value => String(value || '').trim().replace(/^https:\/\/github\.com\//i, '')" +
    ".replace(/\.git$/i, '').replace(/\/+$/, '').toLowerCase();" +
    "const folder = value => { const full = path.resolve(String(value || ''));" +
    " return process.platform === 'win32' ? full.toLowerCase() : full; };" +
    "let same = false;" +
    "if (entry && entry.source === 'github') same = repo(source) === repo(entry.repo);" +
    "else if (entry && entry.source === 'directory') same = folder(source) === folder(entry.path);" +
    "else if (entry) same = [entry.url, entry.repo, entry.path].some(value => value && repo(value) === repo(source));" +
    "console.log(!entry ? 'absent' : same ? 'match' : 'different');"

$Client = $Client.ToLowerInvariant()
$clients = switch ($Client) {
    'all' { @('codex', 'claude') }
    'auto' { @('codex', 'claude') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } }
    default { @($Client) }
}
if (-not $clients) {
    throw 'Install the Codex CLI or Claude Code and add it to PATH, or pass -Client.'
}

foreach ($commandName in @($clients) + @('git', 'node', 'npx')) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "Install $commandName and add it to PATH."
    }
}
& node -e 'process.exit(parseInt(process.versions.node, 10) >= 20 ? 0 : 1)'
if ($LASTEXITCODE -ne 0) {
    throw 'Install Node.js 20 or later.'
}
if ($Auth -eq 'azcli' -and -not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Install Azure CLI and run az login.'
}

if (-not $Organization) {
    $Organization = Read-Host 'Azure DevOps organization name'
}
if ($Organization -notmatch '^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$') {
    throw 'Enter the organization name from dev.azure.com/NAME.'
}

if (Test-Path -LiteralPath $Source -PathType Container) {
    $Source = (Resolve-Path -LiteralPath $Source).ProviderPath
}

$Auth = $Auth.ToLowerInvariant()
$serverArgs = @('--yes', '@azure-devops/mcp@2.11.0', $Organization, '--authentication', $Auth,
    '-d', 'core', 'work', 'work-items', 'repositories', 'pipelines', 'search')

# Check every selected client before changing any configuration.
$plans = @{}
foreach ($name in $clients) {
    if ($name -eq 'codex') {
        $command = 'npx'
        $commandArgs = $serverArgs
        $servers = (Invoke-Cli codex @('mcp', 'list', '--json') | Out-String) | ConvertFrom-Json
        $server = $servers | Where-Object { $_.name -ceq $connection }
        $existing = [bool] $server
        $same = $existing -and $server.enabled -and $server.transport.type -ceq 'stdio' -and
            $server.transport.command -ceq $command -and (Test-SameArgs $server.transport.args $commandArgs)
    } else {
        # Claude Code on native Windows starts npx through cmd.
        $onWindows = $PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows
        $command = if ($onWindows) { 'cmd' } else { 'npx' }
        $commandArgs = if ($onWindows) { @('/c', 'npx') + $serverArgs } else { $serverArgs }
        # Read the user-scope connection with Node; ~/.claude.json can hold keys that differ only by case.
        $state = & node -e $claudeCheck -- $connection $command @commandArgs
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not read the Claude Code configuration.'
        }
        $existing = $state -ne 'absent'
        $same = $state -eq 'match'
        $marketplaceState = Invoke-Cli claude @('plugin', 'marketplace', 'list', '--json') |
            & node -e $marketplaceCheck -- $marketplace $Source
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not read the Claude Code marketplaces.'
        }
        if ($marketplaceState -eq 'different' -and -not $Replace) {
            throw "The $marketplace marketplace in claude uses a different source. Use -Replace to switch it to $Source."
        }
    }
    if ($existing -and -not $same -and -not $Replace) {
        throw "A different $connection MCP connection exists in $name. Use -Replace to replace it."
    }
    $plans[$name] = @{ Command = $command; Args = $commandArgs; Existing = [bool] $existing; Matches = [bool] $same
        Marketplace = $marketplaceState }
}

foreach ($name in $clients) {
    $plan = $plans[$name]
    if ($name -eq 'codex') {
        Invoke-Cli codex @('plugin', 'marketplace', 'add', $Source)
        Invoke-Cli codex @('plugin', 'marketplace', 'upgrade', $marketplace)
        Invoke-Cli codex @('plugin', 'add', $plugin)
        if (-not $plan.Matches) {
            Invoke-Cli codex (@('mcp', 'add', $connection, '--', $plan.Command) + $plan.Args)
        }
    } else {
        if ($plan.Marketplace -eq 'match') {
            Invoke-Cli claude @('plugin', 'marketplace', 'update', $marketplace)
        } else {
            if ($plan.Marketplace -eq 'different') {
                # Removing the marketplace also uninstalls its plugins; the plugin is reinstalled below.
                Invoke-Cli claude @('plugin', 'marketplace', 'remove', $marketplace)
            }
            Invoke-Cli claude @('plugin', 'marketplace', 'add', $Source)
        }
        $installed = (Invoke-Cli claude @('plugin', 'list', '--json') | Out-String) | ConvertFrom-Json
        if ($installed | Where-Object { $_.id -ceq $plugin }) {
            Invoke-Cli claude @('plugin', 'update', $plugin)
        } else {
            Invoke-Cli claude @('plugin', 'install', $plugin)
        }
        if (-not $plan.Matches) {
            if ($plan.Existing) {
                Invoke-Cli claude @('mcp', 'remove', '--scope', 'user', $connection)
            }
            Invoke-Cli claude (@('mcp', 'add', '--scope', 'user', $connection, '--', $plan.Command) + $plan.Args)
        }
    }
}

$names = ($clients | ForEach-Object { if ($_ -eq 'codex') { 'Codex' } else { 'Claude Code' } }) -join ' or '
Write-Host "Start a new $names session and ask: List the Azure DevOps projects I can access."
