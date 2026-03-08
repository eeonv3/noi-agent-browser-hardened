param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigFile,
    [Parameter(Mandatory = $true)]
    [string]$Token,
    [Parameter(Mandatory = $true)]
    [string]$SkillsDir,
    [Parameter(Mandatory = $true)]
    [string]$MemoryDir,
    [Parameter(Mandatory = $true)]
    [string]$SessionsDir,
    [Parameter(Mandatory = $true)]
    [string]$AuditLog
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Quote-Toml {
    param([string]$Value)

    '"' + ($Value.Replace('\', '\\').Replace('"', '\"')) + '"'
}

function Set-TomlEntry {
    param(
        [System.Collections.ArrayList]$Lines,
        [string]$Section,
        [string]$Key,
        [string]$Value
    )

    $header = "[$Section]"
    $sectionStart = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -eq $header) {
            $sectionStart = $i
            break
        }
    }

    if ($sectionStart -lt 0) {
        if ($Lines.Count -gt 0 -and $Lines[$Lines.Count - 1].Trim() -ne '') {
            [void]$Lines.Add('')
        }
        [void]$Lines.Add($header)
        [void]$Lines.Add("$Key = $Value")
        return
    }

    $sectionEnd = $Lines.Count
    for ($i = $sectionStart + 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -match '^\[.+\]$') {
            $sectionEnd = $i
            break
        }
    }

    $keyPattern = '^\s*' + [regex]::Escape($Key) + '\s*='
    for ($i = $sectionStart + 1; $i -lt $sectionEnd; $i++) {
        if ($Lines[$i] -match $keyPattern) {
            $Lines[$i] = "$Key = $Value"
            if ($Value.StartsWith('[')) {
                for ($j = $i + 1; $j -lt $sectionEnd;) {
                    if ($Lines[$j].Trim() -match '^\[.+\]$') {
                        break
                    }
                    $candidate = $Lines[$j].Trim()
                    if ($candidate -eq '') {
                        break
                    }
                    $Lines.RemoveAt($j)
                    $sectionEnd--
                    if ($candidate -match '\]') {
                        break
                    }
                }
            }
            return
        }
    }

    $Lines.Insert($sectionEnd, "$Key = $Value")
}

$backupStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
if (Test-Path -LiteralPath $ConfigFile) {
    Copy-Item -LiteralPath $ConfigFile -Destination "$ConfigFile.backup_$backupStamp" -Force
    $content = Get-Content -LiteralPath $ConfigFile
} else {
    $content = @()
}

$lines = [System.Collections.ArrayList]::new()
foreach ($line in $content) {
    [void]$lines.Add([string]$line)
}

$allowedCommands = @(
    'git',
    'npm',
    'node',
    'python',
    'ls',
    'cat',
    'grep',
    'find',
    'echo',
    'pwd',
    'wc',
    'head',
    'tail',
    'date'
) | ForEach-Object { Quote-Toml $_ }

$gatewayTokenList = '[' + (Quote-Toml $Token) + ']'
$commandList = '[' + ($allowedCommands -join ', ') + ']'

$entries = @(
    @{ Section = 'gateway'; Key = 'host'; Value = Quote-Toml '127.0.0.1' },
    @{ Section = 'gateway'; Key = 'port'; Value = '42617' },
    @{ Section = 'gateway'; Key = 'require_pairing'; Value = 'true' },
    @{ Section = 'gateway'; Key = 'allow_public_bind'; Value = 'false' },
    @{ Section = 'gateway'; Key = 'trust_forwarded_headers'; Value = 'false' },
    @{ Section = 'gateway'; Key = 'pair_rate_limit_per_minute'; Value = '5' },
    @{ Section = 'gateway'; Key = 'webhook_rate_limit_per_minute'; Value = '20' },
    @{ Section = 'gateway'; Key = 'paired_tokens'; Value = $gatewayTokenList },
    @{ Section = 'autonomy'; Key = 'level'; Value = Quote-Toml 'supervised' },
    @{ Section = 'autonomy'; Key = 'workspace_only'; Value = 'true' },
    @{ Section = 'autonomy'; Key = 'allowed_commands'; Value = $commandList },
    @{ Section = 'autonomy'; Key = 'max_actions_per_hour'; Value = '30' },
    @{ Section = 'autonomy'; Key = 'require_approval_for_medium_risk'; Value = 'true' },
    @{ Section = 'autonomy'; Key = 'block_high_risk_commands'; Value = 'true' },
    @{ Section = 'security.audit'; Key = 'enabled'; Value = 'true' },
    @{ Section = 'security.audit'; Key = 'log_path'; Value = Quote-Toml $AuditLog },
    @{ Section = 'security.audit'; Key = 'max_size_mb'; Value = '25' },
    @{ Section = 'security.audit'; Key = 'sign_events'; Value = 'false' },
    @{ Section = 'security.resources'; Key = 'max_memory_mb'; Value = '768' },
    @{ Section = 'security.resources'; Key = 'max_cpu_time_seconds'; Value = '120' },
    @{ Section = 'security.resources'; Key = 'max_subprocesses'; Value = '8' },
    @{ Section = 'security.resources'; Key = 'memory_monitoring'; Value = 'true' },
    @{ Section = 'agent'; Key = 'compact_context'; Value = 'true' },
    @{ Section = 'agent'; Key = 'max_tool_iterations'; Value = '12' },
    @{ Section = 'agent'; Key = 'parallel_tools'; Value = 'true' },
    @{ Section = 'skills'; Key = 'open_skills_enabled'; Value = 'true' },
    @{ Section = 'web_search'; Key = 'enabled'; Value = 'true' },
    @{ Section = 'web_search'; Key = 'provider'; Value = Quote-Toml 'duckduckgo' },
    @{ Section = 'web_search'; Key = 'max_results'; Value = '5' },
    @{ Section = 'web_search'; Key = 'timeout_secs'; Value = '10' },
    @{ Section = 'browser'; Key = 'enabled'; Value = 'false' },
    @{ Section = 'browser'; Key = 'backend'; Value = Quote-Toml 'agent_browser' },
    @{ Section = 'browser'; Key = 'native_headless'; Value = 'true' },
    @{ Section = 'browser'; Key = 'native_webdriver_url'; Value = Quote-Toml 'http://127.0.0.1:9515' },
    @{ Section = 'browser.computer_use'; Key = 'endpoint'; Value = Quote-Toml 'http://127.0.0.1:8787/v1/actions' },
    @{ Section = 'browser.computer_use'; Key = 'timeout_ms'; Value = '15000' },
    @{ Section = 'browser.computer_use'; Key = 'allow_remote_endpoint'; Value = 'false' },
    @{ Section = 'browser.computer_use'; Key = 'window_allowlist'; Value = '[]' },
    @{ Section = 'http_request'; Key = 'enabled'; Value = 'false' },
    @{ Section = 'web_fetch'; Key = 'enabled'; Value = 'false' },
    @{ Section = 'multimodal'; Key = 'allow_remote_fetch'; Value = 'false' },
    @{ Section = 'memory'; Key = 'backend'; Value = Quote-Toml 'sqlite' },
    @{ Section = 'memory'; Key = 'auto_save'; Value = 'true' },
    @{ Section = 'tunnel'; Key = 'provider'; Value = Quote-Toml 'none' },
    @{ Section = 'secrets'; Key = 'encrypt'; Value = 'true' }
)

foreach ($entry in $entries) {
    Set-TomlEntry -Lines $lines -Section $entry.Section -Key $entry.Key -Value $entry.Value
}

Set-Content -LiteralPath $ConfigFile -Value $lines -Encoding UTF8
