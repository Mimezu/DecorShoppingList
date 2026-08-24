[CmdletBinding()]
param(
    [string]$AddonPath = (Join-Path $PSScriptRoot '..'),
    [switch]$RequireLua,
    [string]$LuaJITPath = $env:DECORSHOPPINGLIST_LUAJIT,
    [string]$LuaParseModulePath = $env:DECORSHOPPINGLIST_LUAPARSE,
    [string]$FengariModulePath = $env:DECORSHOPPINGLIST_FENGARI,
    [switch]$RequireBehavior
)

$ErrorActionPreference = 'Stop'
$script:Failures = 0

function Result {
    param(
        [ValidateSet('PASS', 'FAIL', 'WARN', 'SKIP')][string]$Status,
        [string]$Message
    )
    $color = switch ($Status) {
        'PASS' { 'Green' }
        'FAIL' { 'Red' }
        'WARN' { 'Yellow' }
        default { 'DarkYellow' }
    }
    Write-Host ("[{0}] {1}" -f $Status, $Message) -ForegroundColor $color
    if ($Status -eq 'FAIL') { $script:Failures++ }
}

$addonPath = [System.IO.Path]::GetFullPath($AddonPath)
$tocPath = Join-Path $addonPath 'DecorShoppingList.toc'
if (-not (Test-Path -LiteralPath $tocPath -PathType Leaf)) {
    Result FAIL "Missing DecorShoppingList.toc at $addonPath"
    exit 1
}

$tocLines = Get-Content -LiteralPath $tocPath
$toc = $tocLines -join "`n"
$entries = @(
    $tocLines |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') }
)

if ($toc -match '(?m)^##\s*Interface:\s*120100\s*$') { Result PASS 'Retail interface is 120100.' }
else { Result FAIL 'TOC must target Retail interface 120100.' }

if ($toc -match '(?m)^##\s*Title:\s*Decor Shopping List\s*$') { Result PASS 'Addon title is approved.' }
else { Result FAIL 'TOC title must be Decor Shopping List.' }

if ($toc -match '(?m)^##\s*SavedVariables:\s*DecorShoppingListDB\s*$') { Result PASS 'Account-wide list storage is declared.' }
else { Result FAIL 'TOC must declare DecorShoppingListDB.' }

$versionMatch = [regex]::Match($toc, '(?m)^##\s*Version:\s*(\d+\.\d+\.\d+)\s*$')
if ($versionMatch.Success) { Result PASS ("Semantic version is {0}." -f $versionMatch.Groups[1].Value) }
else { Result FAIL 'TOC Version must use major.minor.patch.' }

$seen = @{}
$luaFiles = @()
foreach ($entry in $entries) {
    $relative = $entry -replace '/', '\'
    $key = $relative.ToLowerInvariant()
    if ($seen.ContainsKey($key)) {
        Result FAIL "Duplicate TOC entry: $entry"
        continue
    }
    $seen[$key] = $true
    $path = Join-Path $addonPath $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Result FAIL "Missing TOC entry: $entry"
    } elseif ($relative -match '(?i)\.lua$') {
        $luaFiles += $path
    }
}
if ($script:Failures -eq 0) { Result PASS 'Every TOC entry exists and is unique.' }

$unlisted = @(
    Get-ChildItem -LiteralPath $addonPath -Recurse -Filter '*.lua' -File |
        Where-Object {
            $relative = [System.IO.Path]::GetRelativePath($addonPath, $_.FullName) -replace '/', '\'
            $developmentOnly = $relative -match '^(?i:tests|tools)\\'
            -not $developmentOnly -and -not $seen.ContainsKey($relative.ToLowerInvariant())
        }
)
if ($unlisted.Count -eq 0) { Result PASS 'Every addon Lua file is listed in the TOC.' }
else { Result FAIL ("Unlisted Lua files: {0}" -f (($unlisted.FullName) -join ', ')) }

$source = ($luaFiles | ForEach-Object { Get-Content -Raw -LiteralPath $_ }) -join "`n"

$requiredPatterns = @(
    @{ Pattern = 'HOUSING_BLUEPRINT_CONTENTS_RECEIVED'; Message = 'Blueprint contents event is handled.' },
    @{ Pattern = 'MENU_HOUSING_CATALOG_ENTRY'; Message = 'Housing Catalog declares Blizzard''s supported tagged menu.' },
    @{ Pattern = 'Menu\.ModifyMenu'; Message = 'Housing Catalog uses the supported tagged-menu extension.' },
    @{ Pattern = 'function\s+Store:CreateList'; Message = 'Multiple-list creation is implemented.' },
    @{ Pattern = 'function\s+Store:SetActiveList'; Message = 'Explicit active-list selection is implemented.' },
    @{ Pattern = 'function\s+Store:AddItem'; Message = 'List item insertion is implemented.' },
    @{ Pattern = 'function\s+Store:SetItemDesired'; Message = 'Desired quantities are editable.' },
    @{ Pattern = 'TomTom'; Message = 'Optional TomTom integration is present.' },
    @{ Pattern = 'RemoveWaypoint'; Message = 'Owned TomTom waypoints have a cleanup path.' },
    @{ Pattern = 'housing-basic-container'; Message = 'Verified Blizzard Housing container art is used.' },
    @{ Pattern = 'housing-basic-container-woodheader'; Message = 'Verified Blizzard Housing header art is used.' },
    @{ Pattern = 'housing-basic-panel-innerblackbox'; Message = 'Verified Blizzard Housing list inset art is used.' },
    @{ Pattern = 'issecretvalue'; Message = 'Secret-value detection is present.' },
    @{ Pattern = 'canaccessvalue'; Message = 'Unreadable-value detection is present.' }
)
foreach ($gate in $requiredPatterns) {
    if ($source -match $gate.Pattern) { Result PASS $gate.Message }
    else { Result FAIL $gate.Message }
}

$forbiddenPatterns = @(
    @{ Pattern = '(?i)SetScript\s*\(\s*["'']OnUpdate["'']'; Message = 'No permanent OnUpdate script.' },
    @{ Pattern = '(?i)(?:LoadAddOn|IsAddOnLoaded|GetAddOnMetadata)[^\n]*HomeBound|\b(?:dbHB|hb_settings)\b|Interface\\AddOns\\HomeBound'; Message = 'No runtime Home Bound dependency or SavedVariables access.' },
    @{ Pattern = '(?i)(?:hooksecurefunc|HookScript|SetScript)\s*\([^\n]*(?:HousingCatalogEntry|HousingBlueprintContentListFrame)'; Message = 'No Blizzard Housing frame/script replacement.' },
    @{ Pattern = '(?i)DecorShoppingListDB\s*=\s*nil'; Message = 'Saved lists are never destructively discarded.' }
)
foreach ($gate in $forbiddenPatterns) {
    if ($source -match $gate.Pattern) { Result FAIL $gate.Message }
    else { Result PASS $gate.Message }
}

function Find-Lua51Command {
    foreach ($name in @('luac5.1', 'luac')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $command) { continue }
        $versionOutput = (& $command.Source -v 2>&1 | Out-String)
        if ($versionOutput -match '(?i)\bLua\s+5\.1(?:\.|\b)') { return $command }
        Result WARN ("Ignoring non-5.1 Lua compiler {0}." -f $command.Source)
    }
    return $null
}

function Find-Lua51Runtime {
    foreach ($name in @('lua5.1', 'lua')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $command) { continue }
        $versionOutput = (& $command.Source -v 2>&1 | Out-String)
        if ($versionOutput -match '(?i)\bLua\s+5\.1(?:\.|\b)') { return $command }
        Result WARN ("Ignoring non-5.1 Lua runtime {0}." -f $command.Source)
    }
    return $null
}

function Find-LuaJITCommand {
    $candidates = @()
    if ($LuaJITPath) {
        $candidates += $LuaJITPath
    }
    $command = Get-Command 'luajit' -ErrorAction SilentlyContinue
    if ($command) {
        $candidates += $command.Source
    }
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\LuaJIT\bin\luajit.exe')
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $versionOutput = (& $candidate -v 2>&1 | Out-String)
        if ($versionOutput -match '(?i)\bLuaJIT\s+2\.') {
            return [pscustomobject]@{ Source = $candidate; Version = $versionOutput.Trim() }
        }
        Result WARN ("Ignoring unverified LuaJIT candidate {0}." -f $candidate)
    }
    return $null
}

function Find-WowlessCommand {
    foreach ($name in @('wowless', 'wowless-cli')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $command) { continue }
        $versionOutput = (& $command.Source --version 2>&1 | Out-String)
        if ($versionOutput -match '(?i)wowless') {
            return [pscustomobject]@{ Command = $command; Version = $versionOutput.Trim() }
        }
        Result WARN ("Ignoring unverified Wowless candidate {0}." -f $command.Source)
    }
    return $null
}

$workspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$wowless = Find-WowlessCommand
$wowlessMarkers = @(
    Get-ChildItem -LiteralPath $workspaceRoot -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(?:\.wowless|wowless[.])' }
    Get-ChildItem -LiteralPath (Join-Path $workspaceRoot 'tests\DecorShoppingList') -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(?:\.wowless|wowless[.])' }
)
if ($wowless -and $wowlessMarkers.Count -gt 0) {
    Result WARN ("Genuine Wowless is available ({0}), but this gate has no verified project load command yet." -f $wowless.Version)
} elseif ($wowless) {
    Result WARN ("Genuine Wowless is available ({0}), but no project Wowless profile is configured; it was not run." -f $wowless.Version)
} else {
    Result SKIP 'Genuine Wowless is not installed/configured. Fengari, when selected below, is only a Lua mock harness.'
}

$luaCompiler = Find-Lua51Command
$luaJIT = Find-LuaJITCommand
if ($luaCompiler) {
    foreach ($file in $luaFiles) {
        & $luaCompiler.Source -p -- $file
        if ($LASTEXITCODE -ne 0) { Result FAIL ("Lua syntax failed: {0}" -f $file) }
    }
    if ($script:Failures -eq 0) { Result PASS 'Lua 5.1 syntax checks passed.' }
} elseif ($luaJIT) {
    $bytecodePath = [System.IO.Path]::GetTempFileName()
    try {
        foreach ($file in $luaFiles) {
            & $luaJIT.Source -b $file $bytecodePath
            if ($LASTEXITCODE -ne 0) { Result FAIL ("LuaJIT syntax failed: {0}" -f $file) }
        }
    } finally {
        Remove-Item -LiteralPath $bytecodePath -Force -ErrorAction SilentlyContinue
    }
    if ($script:Failures -eq 0) {
        Result PASS ("Every TOC Lua file compiled with {0}." -f $luaJIT.Version)
    }
} elseif ($LuaParseModulePath) {
    $node = Get-Command node -ErrorAction SilentlyContinue
    $parserRunner = Join-Path $workspaceRoot 'tests\DecorShoppingList\run-luaparse.js'
    if (-not $node) {
        Result FAIL 'luaparse was requested, but Node.js is unavailable.'
    } elseif (-not (Test-Path -LiteralPath $parserRunner -PathType Leaf)) {
        Result FAIL 'luaparse was requested, but its persisted runner is missing.'
    } else {
        & $node.Source $parserRunner --root $workspaceRoot --addon $addonPath --luaparse $LuaParseModulePath
        if ($LASTEXITCODE -eq 0) {
            Result PASS 'Every TOC Lua file passed luaparse Lua 5.1 grammar checks.'
        } else {
            Result FAIL 'Lua 5.1 grammar parsing failed.'
        }
    }
} else {
    Result SKIP 'No Lua 5.1 compiler or explicitly selected luaparse module found.'
}
if ($RequireLua -and -not $luaCompiler -and -not $luaJIT) {
    Result FAIL 'No verified native Lua 5.1 compiler or LuaJIT runtime found; luaparse does not satisfy -RequireLua.'
}

$smokePaths = @(
    'smoke.lua',
    'waypoint_smoke.lua',
    'controller_smoke.lua',
    'source_registry_smoke.lua',
    'merchant_smoke.lua',
    'vendor_nameplate_smoke.lua',
    'ui_view_smoke.lua'
) | ForEach-Object {
    [System.IO.Path]::GetFullPath((Join-Path $workspaceRoot (Join-Path 'tests\DecorShoppingList' $_)))
}
$allFixturesPresent = $true
foreach ($smokePath in $smokePaths) {
    if (-not (Test-Path -LiteralPath $smokePath -PathType Leaf)) {
        Result FAIL ("Missing persisted smoke fixture: {0}" -f ([System.IO.Path]::GetFileName($smokePath)))
        $allFixturesPresent = $false
    }
}
if ($allFixturesPresent) {
    $behaviorRan = $false
    $luaRuntime = Find-Lua51Runtime
    if ($luaRuntime) {
        $allPassed = $true
        Push-Location $workspaceRoot
        try {
            foreach ($smokePath in $smokePaths) {
                $fixtureName = [System.IO.Path]::GetFileName($smokePath)
                & $luaRuntime.Source -- $smokePath
                if ($LASTEXITCODE -eq 0) {
                    Result PASS ("{0} passed in Lua 5.1." -f $fixtureName)
                } else {
                    Result FAIL ("{0} failed in Lua 5.1." -f $fixtureName)
                    $allPassed = $false
                }
            }
        } finally {
            Pop-Location
        }
        $behaviorRan = $allPassed
    } elseif ($luaJIT) {
        $allPassed = $true
        Push-Location $workspaceRoot
        try {
            foreach ($smokePath in $smokePaths) {
                $fixtureName = [System.IO.Path]::GetFileName($smokePath)
                & $luaJIT.Source $smokePath
                if ($LASTEXITCODE -eq 0) {
                    Result PASS ("{0} passed in LuaJIT native mocks." -f $fixtureName)
                } else {
                    Result FAIL ("{0} failed in LuaJIT native mocks." -f $fixtureName)
                    $allPassed = $false
                }
            }
        } finally {
            Pop-Location
        }
        $behaviorRan = $allPassed
    } elseif ($FengariModulePath) {
        $node = Get-Command node -ErrorAction SilentlyContinue
        $fengariRunner = Join-Path $workspaceRoot 'tests\DecorShoppingList\run-fengari.js'
        if (-not $node) {
            Result FAIL 'Fengari was requested, but Node.js is unavailable.'
        } elseif (-not (Test-Path -LiteralPath $fengariRunner -PathType Leaf)) {
            Result FAIL 'Fengari was requested, but its persisted runner is missing.'
        } else {
            $allPassed = $true
            foreach ($smokePath in $smokePaths) {
                $fixtureName = [System.IO.Path]::GetFileName($smokePath)
                & $node.Source $fengariRunner --root $workspaceRoot --smoke $smokePath --fengari $FengariModulePath
                if ($LASTEXITCODE -eq 0) {
                    Result PASS ("{0} passed in Fengari mocks (not Wowless or WoW)." -f $fixtureName)
                } else {
                    Result FAIL ("{0} failed in Fengari mocks." -f $fixtureName)
                    $allPassed = $false
                }
            }
            $behaviorRan = $allPassed
        }
    } else {
        Result SKIP 'No Lua 5.1 runtime or explicitly selected Fengari module; persisted smoke fixtures were not executed.'
    }
    if ($RequireBehavior -and -not $behaviorRan) {
        Result FAIL 'A behavioral runtime was required, but no behavioral smoke completed.'
    }
}

if ($script:Failures -gt 0) {
    Write-Host ("`n{0} Decor Shopping List gate(s) failed." -f $script:Failures) -ForegroundColor Red
    exit 1
}

Write-Host "`nDecor Shopping List static validation passed. Finish the in-game QA matrix before release." -ForegroundColor Green
exit 0
