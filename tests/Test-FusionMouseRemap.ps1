#Requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path $PSScriptRoot 'fixtures\Fusion360FS.xml'
$script = Join-Path $projectRoot 'scripts\Set-FusionMouseRemap.ps1'
$testDirectory = Join-Path $projectRoot '.test-output'
$testProfile = Join-Path $testDirectory 'Fusion360FS.xml'
$noFactory = '__missing_factory_profile__.xml'
$allCadMice = @('C650', 'C651', 'C654', 'C655', 'C656', 'C657', 'C658') | ForEach-Object { "ID_ProductID_$_" }

if (Test-Path -LiteralPath $testDirectory) { Remove-Item -LiteralPath $testDirectory -Recurse -Force }
[void](New-Item -ItemType Directory -Path $testDirectory)
Copy-Item -LiteralPath $fixture -Destination $testProfile -Force

# Install (with a backup, so Restore can be tested), then Status.
& $script -Mode Install -ProfilePath $testProfile -FactoryProfilePath $noFactory | Out-Null
& $script -Mode Status -ProfilePath $testProfile -FactoryProfilePath $noFactory | Out-Null

[xml]$xml = Get-Content -Raw -LiteralPath $testProfile
$macro = @($xml.AppCfg.MacroTable.MacroEntry | Where-Object { $_.ID -eq 'FusionMouseRemap_MarkingMenu' })
if ($macro.Count -ne 1) { throw "Expected one marking-menu macro, found $($macro.Count)." }
if ($macro[0].KeyStroke.Modifiers.Modifier -ne 'Shift' -or $macro[0].KeyStroke.MouseButton -ne 'Right') {
    throw 'The marking-menu macro is not Shift + Right Mouse Button.'
}

# Every CadMouse model gets the mapping, including models not yet in the profile.
foreach ($deviceId in $allCadMice) {
    $device = @($xml.AppCfg.Devices.Device | Where-Object { $_.ID -eq $deviceId })
    if ($device.Count -ne 1) { throw "Expected one device override for $deviceId, found $($device.Count)." }
    foreach ($bank in @($device[0].ButtonBank)) {
        $wheel = @($bank.Button | Where-Object { $_.Input.ActionID -eq 'HIDButton_4' })
        if ($wheel.Count -ne 1 -or $wheel[0].Output.ActionID -ne 'FusionMouseRemap_MarkingMenu') {
            throw "Invalid wheel mapping in $deviceId/$($bank.ID)."
        }
    }
}

$preserved = @($xml.AppCfg.Devices.Device[0].ButtonBank[0].Button | Where-Object { $_.Input.ActionID -eq 'HIDButton_7' })
if ($preserved.Count -ne 1 -or $preserved[0].Output.ActionID -ne 'ExistingRadialMenu') {
    throw 'An unrelated existing mapping was not preserved.'
}

# A second install changes nothing.
Start-Sleep -Seconds 1  # backups are named by the second
& $script -Mode Install -ProfilePath $testProfile -FactoryProfilePath $noFactory | Out-Null
[xml]$secondPass = Get-Content -Raw -LiteralPath $testProfile
$secondMacro = @($secondPass.AppCfg.MacroTable.MacroEntry | Where-Object { $_.ID -eq 'FusionMouseRemap_MarkingMenu' })
if ($secondMacro.Count -ne 1) { throw 'Install is not idempotent.' }

# Restore puts back the oldest backup (the profile before the first install), not the newest.
& $script -Mode Restore -ProfilePath $testProfile -FactoryProfilePath $noFactory | Out-Null
if ((Get-FileHash -LiteralPath $testProfile).Hash -ne (Get-FileHash -LiteralPath $fixture).Hash) {
    throw 'Restore did not put back the original profile.'
}
$statusFailed = $false
try { & $script -Mode Status -ProfilePath $testProfile -FactoryProfilePath $noFactory | Out-Null } catch { $statusFailed = $true }
if (-not $statusFailed) { throw 'Status should fail after Restore.' }

# A missing profile gives the instructions, not a bare "file not found".
$missingMessage = $null
try { & $script -ProfilePath (Join-Path $testDirectory 'missing.xml') -FactoryProfilePath $noFactory | Out-Null } catch { $missingMessage = $_.Exception.Message }
if ($missingMessage -notmatch 'wheel-click') { throw "Missing-profile message lacks instructions: $missingMessage" }

# Windows PowerShell 5.1 is refused up front.
if (Get-Command powershell.exe -ErrorAction SilentlyContinue) {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Mode Status -ProfilePath $testProfile 2>&1 | Out-String
    if ($output -notmatch '7\.0') { throw "Windows PowerShell 5.1 was not refused: $output" }
}

Write-Output 'PASS: install, all seven CadMouse models, preservation, idempotency, restore, missing profile and version checks succeeded.'
