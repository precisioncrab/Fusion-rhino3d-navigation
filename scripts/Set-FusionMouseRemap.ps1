#Requires -Version 7.0
<#
.SYNOPSIS
    Maps the 3Dconnexion CadMouse wheel click to Shift + Right Mouse Button in the
    3DxWare profile for Autodesk Fusion, which opens Fusion's marking menu.

.DESCRIPTION
    Pair it with Fusion's "Pan, Zoom, Orbit Shortcuts: Tinkercad" preference for
    Rhino-style navigation: RMB drag orbits, MMB drag pans, wheel zooms, wheel click
    opens the marking menu. See README.md.

    Modes:
      Install  (default) back up the profile, then add the mapping.
      Status   report whether the mapping is in place (exit code 1 if not).
      Restore  put back the oldest backup this script made (the profile as it was
               before the first install).

.EXAMPLE
    pwsh -File .\scripts\Set-FusionMouseRemap.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Install', 'Status', 'Restore')]
    [string]$Mode = 'Install',

    [string]$ProfilePath = (Join-Path $env:APPDATA '3Dconnexion\3DxWare\Cfg\Fusion360FS.xml'),

    [string]$FactoryProfilePath = (Join-Path $env:ProgramFiles '3Dconnexion\3DxWare\3DxWinCore\Cfg\Fusion360FS.xml'),

    # Every CadMouse model in 3DxWare's device list (Base.xml). All of them report
    # the wheel click as HIDButton_4.
    [string[]]$DeviceIds = @(
        'ID_ProductID_C650', # CadMouse
        'ID_ProductID_C651', # CadMouse Wireless
        'ID_ProductID_C654', # CadMouse Pro Wireless
        'ID_ProductID_C655', # CadMouse Compact
        'ID_ProductID_C656', # CadMouse Pro
        'ID_ProductID_C657', # CadMouse Pro Wireless Left
        'ID_ProductID_C658'  # CadMouse Compact Wireless
    ),

    [switch]$NoBackup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$macroId = 'FusionMouseRemap_MarkingMenu'
$wheelButtonId = 'HIDButton_4'
$requiredBankIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
[void]$requiredBankIds.Add('Default')
[void]$requiredBankIds.Add('FusionSolidEnvironmentSketchTab')

function Read-XmlDocument {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "XML file not found: $Path"
    }

    $document = [System.Xml.XmlDocument]::new()
    $document.PreserveWhitespace = $true
    $document.Load($Path)
    return $document
}

function Get-DirectChild {
    param(
        [Parameter(Mandatory)][System.Xml.XmlNode]$Parent,
        [Parameter(Mandatory)][string]$Name
    )

    return @($Parent.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -eq $Name })[0]
}

function Get-ChildText {
    param(
        [Parameter(Mandatory)][System.Xml.XmlNode]$Parent,
        [Parameter(Mandatory)][string]$Name
    )

    $child = Get-DirectChild -Parent $Parent -Name $Name
    if ($null -eq $child) { return $null }
    return $child.InnerText
}

function New-TextElement {
    param(
        [Parameter(Mandatory)][System.Xml.XmlDocument]$Document,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )

    $element = $Document.CreateElement($Name)
    $element.InnerText = $Text
    return $element
}

function Find-ChildById {
    param(
        [Parameter(Mandatory)][System.Xml.XmlNode]$Parent,
        [Parameter(Mandatory)][string]$ElementName,
        [Parameter(Mandatory)][string]$Id
    )

    foreach ($child in $Parent.ChildNodes) {
        if ($child.NodeType -ne 'Element' -or $child.LocalName -ne $ElementName) { continue }
        if ((Get-ChildText -Parent $child -Name 'ID') -eq $Id) { return $child }
    }
    return $null
}

function Get-WheelButtons {
    param([Parameter(Mandatory)][System.Xml.XmlNode]$ButtonBank)

    $found = [System.Collections.Generic.List[System.Xml.XmlNode]]::new()
    foreach ($button in @($ButtonBank.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -eq 'Button' })) {
        $inputNode = Get-DirectChild -Parent $button -Name 'Input'
        if ($null -eq $inputNode) { continue }
        if ((Get-ChildText -Parent $inputNode -Name 'ActionID') -eq $wheelButtonId) {
            $found.Add($button)
        }
    }
    return $found.ToArray()
}

function Set-MarkingMenuMacro {
    param(
        [Parameter(Mandatory)][System.Xml.XmlDocument]$Document,
        [Parameter(Mandatory)][System.Xml.XmlNode]$Root
    )

    $macroTable = Get-DirectChild -Parent $Root -Name 'MacroTable'
    if ($null -eq $macroTable) {
        $macroTable = $Document.CreateElement('MacroTable')
        $devices = Get-DirectChild -Parent $Root -Name 'Devices'
        if ($null -ne $devices) {
            [void]$Root.InsertBefore($macroTable, $devices)
        } else {
            [void]$Root.AppendChild($macroTable)
        }
    }

    $existing = Find-ChildById -Parent $macroTable -ElementName 'MacroEntry' -Id $macroId
    if ($null -ne $existing) {
        [void]$macroTable.RemoveChild($existing)
    }

    $entry = $Document.CreateElement('MacroEntry')
    [void]$entry.AppendChild((New-TextElement -Document $Document -Name 'ID' -Text $macroId))
    $keyStroke = $Document.CreateElement('KeyStroke')
    $modifiers = $Document.CreateElement('Modifiers')
    [void]$modifiers.AppendChild((New-TextElement -Document $Document -Name 'Modifier' -Text 'Shift'))
    [void]$keyStroke.AppendChild($modifiers)
    [void]$keyStroke.AppendChild((New-TextElement -Document $Document -Name 'MouseButton' -Text 'Right'))
    [void]$entry.AppendChild($keyStroke)
    [void]$macroTable.AppendChild($entry)

    $buttonActions = Get-DirectChild -Parent $Root -Name 'ButtonActions'
    if ($null -eq $buttonActions) {
        $buttonActions = $Document.CreateElement('ButtonActions')
        $cfgProperties = Get-DirectChild -Parent $Root -Name 'CfgProperties'
        if ($null -ne $cfgProperties -and $null -ne $cfgProperties.NextSibling) {
            [void]$Root.InsertAfter($buttonActions, $cfgProperties)
        } else {
            [void]$Root.PrependChild($buttonActions)
        }
    }

    $action = Find-ChildById -Parent $buttonActions -ElementName 'ButtonAction' -Id $macroId
    if ($null -eq $action) {
        $action = $Document.CreateElement('ButtonAction')
        $action.SetAttribute('Type', 'Macro')
        [void]$action.AppendChild((New-TextElement -Document $Document -Name 'ID' -Text $macroId))
        [void]$action.AppendChild((New-TextElement -Document $Document -Name 'Name' -Text 'Fusion Marking Menu'))
        [void]$buttonActions.AppendChild($action)
    }
}

function Set-WheelBankMapping {
    param(
        [Parameter(Mandatory)][System.Xml.XmlDocument]$Document,
        [Parameter(Mandatory)][System.Xml.XmlNode]$Device,
        [Parameter(Mandatory)][string]$BankId
    )

    $bank = Find-ChildById -Parent $Device -ElementName 'ButtonBank' -Id $BankId
    if ($null -eq $bank) {
        $bank = $Document.CreateElement('ButtonBank')
        if ($BankId -eq 'Default') { $bank.SetAttribute('Default', 'true') }
        [void]$bank.AppendChild((New-TextElement -Document $Document -Name 'ID' -Text $BankId))
        [void]$Device.AppendChild($bank)
    } elseif ($BankId -eq 'Default') {
        $bank.SetAttribute('Default', 'true')
    }

    $wheelButtons = @(Get-WheelButtons -ButtonBank $bank)
    if ($wheelButtons.Count -eq 0) {
        $button = $Document.CreateElement('Button')
        $inputNode = $Document.CreateElement('Input')
        [void]$inputNode.AppendChild((New-TextElement -Document $Document -Name 'ActionID' -Text $wheelButtonId))
        [void]$button.AppendChild($inputNode)
        $outputNode = $Document.CreateElement('Output')
        [void]$outputNode.AppendChild((New-TextElement -Document $Document -Name 'ActionID' -Text $macroId))
        [void]$button.AppendChild($outputNode)
        [void]$bank.AppendChild($button)
    } else {
        $button = $wheelButtons[0]
        $outputNode = Get-DirectChild -Parent $button -Name 'Output'
        if ($null -eq $outputNode) {
            $outputNode = $Document.CreateElement('Output')
            [void]$button.AppendChild($outputNode)
        }
        $actionId = Get-DirectChild -Parent $outputNode -Name 'ActionID'
        if ($null -eq $actionId) {
            [void]$outputNode.AppendChild((New-TextElement -Document $Document -Name 'ActionID' -Text $macroId))
        } else {
            $actionId.InnerText = $macroId
        }

        foreach ($duplicate in @($wheelButtons | Select-Object -Skip 1)) {
            [void]$bank.RemoveChild($duplicate)
        }
    }
}

function Get-ConfigurationStatus {
    param(
        [Parameter(Mandatory)][System.Xml.XmlDocument]$Document,
        [Parameter(Mandatory)][string[]]$TargetDeviceIds,
        [switch]$RequireAllDevices
    )

    $root = $Document.DocumentElement
    $issues = [System.Collections.Generic.List[string]]::new()
    $missingDevices = [System.Collections.Generic.List[string]]::new()
    $mappedDeviceCount = 0
    $macroTable = Get-DirectChild -Parent $root -Name 'MacroTable'
    $macro = if ($null -ne $macroTable) { Find-ChildById -Parent $macroTable -ElementName 'MacroEntry' -Id $macroId } else { $null }
    if ($null -eq $macro) {
        $issues.Add("Missing macro $macroId")
    } else {
        $keyStroke = Get-DirectChild -Parent $macro -Name 'KeyStroke'
        $mouseButton = if ($null -ne $keyStroke) { Get-ChildText -Parent $keyStroke -Name 'MouseButton' } else { $null }
        $modifiers = if ($null -ne $keyStroke) { Get-DirectChild -Parent $keyStroke -Name 'Modifiers' } else { $null }
        $hasShift = $false
        if ($null -ne $modifiers) {
            $hasShift = @($modifiers.ChildNodes | Where-Object { $_.LocalName -eq 'Modifier' -and $_.InnerText -eq 'Shift' }).Count -gt 0
        }
        if ($mouseButton -ne 'Right' -or -not $hasShift) {
            $issues.Add("Macro $macroId is not Shift + Right Mouse Button")
        }
    }

    $devicesNode = Get-DirectChild -Parent $root -Name 'Devices'
    foreach ($deviceId in $TargetDeviceIds) {
        $device = if ($null -ne $devicesNode) { Find-ChildById -Parent $devicesNode -ElementName 'Device' -Id $deviceId } else { $null }
        if ($null -eq $device) {
            if ($RequireAllDevices) { $issues.Add("Missing device override $deviceId") } else { $missingDevices.Add($deviceId) }
            continue
        }
        $mappedDeviceCount++
        foreach ($bank in @($device.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -eq 'ButtonBank' })) {
            $bankId = Get-ChildText -Parent $bank -Name 'ID'
            $wheelButtons = @(Get-WheelButtons -ButtonBank $bank)
            $isMapped = $wheelButtons.Count -eq 1 -and (Get-ChildText -Parent (Get-DirectChild -Parent $wheelButtons[0] -Name 'Output') -Name 'ActionID') -eq $macroId
            if (-not $isMapped) { $issues.Add("$deviceId/$bankId does not map wheel click to $macroId") }
        }
    }

    if ($mappedDeviceCount -eq 0) { $issues.Add('No CadMouse model is set up in this profile') }

    [pscustomobject]@{
        IsConfigured   = $issues.Count -eq 0
        Issues         = @($issues)
        MissingDevices = @($missingDevices)
    }
}

if ($Mode -eq 'Restore') {
    $profileDirectory = Split-Path -Parent $ProfilePath
    $profileLeaf = Split-Path -Leaf $ProfilePath
    $oldest = Get-ChildItem -LiteralPath $profileDirectory -Filter "$profileLeaf.fusion-mouse-remap.*.bak" -File -ErrorAction SilentlyContinue |
        Sort-Object Name | Select-Object -First 1
    if ($null -eq $oldest) { throw "No backup made by this script was found next to $ProfilePath." }
    if ($PSCmdlet.ShouldProcess($ProfilePath, "Restore from $($oldest.Name)")) {
        Copy-Item -LiteralPath $oldest.FullName -Destination $ProfilePath -Force
        Write-Output "Restored: $ProfilePath"
        Write-Output "From: $($oldest.FullName)"
        Write-Output 'Restart Windows (or sign out and back in) so 3DxWare reloads the profile.'
    }
    return
}

if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
    throw ("No 3DxWare Fusion profile at $ProfilePath. 3DxWare creates it the first time you change a " +
        'CadMouse button for Fusion. Click into Fusion, open the 3Dconnexion settings, set the wheel-click ' +
        'button to any command (this script replaces it), close the settings, then run this script again.')
}

if (Test-Path -LiteralPath $FactoryProfilePath -PathType Leaf) {
    $factoryDocument = Read-XmlDocument -Path $FactoryProfilePath
    $factoryDevices = Get-DirectChild -Parent $factoryDocument.DocumentElement -Name 'Devices'
    $factoryMouse = if ($null -ne $factoryDevices) { Find-ChildById -Parent $factoryDevices -ElementName 'Device' -Id 'ID_Standard_2D_Mouse' } else { $null }
    if ($null -ne $factoryMouse) {
        foreach ($bank in @($factoryMouse.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -eq 'ButtonBank' })) {
            $bankId = Get-ChildText -Parent $bank -Name 'ID'
            if (-not [string]::IsNullOrWhiteSpace($bankId)) { [void]$requiredBankIds.Add($bankId) }
        }
    }
}

$profileDocument = Read-XmlDocument -Path $ProfilePath
$root = $profileDocument.DocumentElement
if ($root.LocalName -ne 'AppCfg') { throw "Unexpected root element '$($root.LocalName)' in $ProfilePath" }

if ($Mode -eq 'Status') {
    $status = Get-ConfigurationStatus -Document $profileDocument -TargetDeviceIds $DeviceIds
    if ($status.IsConfigured) {
        Write-Output "Configured: $ProfilePath"
        if ($status.MissingDevices.Count -gt 0) {
            Write-Output "Not set up for: $($status.MissingDevices -join ', ') (fine if you don't own those models; run Install to add them)."
        }
        return
    }
    Write-Output "Not configured: $ProfilePath"
    $status.Issues | ForEach-Object { Write-Output "- $_" }
    throw 'Fusion Mouse Remap is not configured.'
}

Set-MarkingMenuMacro -Document $profileDocument -Root $root
$devices = Get-DirectChild -Parent $root -Name 'Devices'
if ($null -eq $devices) {
    $devices = $profileDocument.CreateElement('Devices')
    [void]$root.AppendChild($devices)
}

foreach ($deviceId in $DeviceIds) {
    $device = Find-ChildById -Parent $devices -ElementName 'Device' -Id $deviceId
    if ($null -eq $device) {
        $device = $profileDocument.CreateElement('Device')
        [void]$device.AppendChild((New-TextElement -Document $profileDocument -Name 'ID' -Text $deviceId))
        [void]$devices.AppendChild($device)
    }

    foreach ($bank in @($device.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -eq 'ButtonBank' })) {
        $bankId = Get-ChildText -Parent $bank -Name 'ID'
        if (-not [string]::IsNullOrWhiteSpace($bankId)) { [void]$requiredBankIds.Add($bankId) }
    }
    foreach ($bankId in $requiredBankIds) {
        Set-WheelBankMapping -Document $profileDocument -Device $device -BankId $bankId
    }
}

$status = Get-ConfigurationStatus -Document $profileDocument -TargetDeviceIds $DeviceIds -RequireAllDevices
if (-not $status.IsConfigured) {
    throw "Generated configuration failed validation:`n$($status.Issues -join "`n")"
}

if (-not $PSCmdlet.ShouldProcess($ProfilePath, 'Install Fusion wheel-click marking-menu mapping')) { return }

$resolvedProfile = (Resolve-Path -LiteralPath $ProfilePath).Path
$profileDirectory = Split-Path -Parent $resolvedProfile
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath = "$resolvedProfile.fusion-mouse-remap.$timestamp.bak"
$temporaryPath = Join-Path $profileDirectory ('.Fusion360FS.' + [guid]::NewGuid().ToString('N') + '.tmp')

if (-not $NoBackup) {
    Copy-Item -LiteralPath $resolvedProfile -Destination $backupPath -ErrorAction Stop
}

try {
    $writerSettings = [System.Xml.XmlWriterSettings]::new()
    $writerSettings.Encoding = [System.Text.UTF8Encoding]::new($false)
    $writerSettings.Indent = $true
    $writerSettings.IndentChars = '  '
    $writerSettings.NewLineChars = "`r`n"
    $writerSettings.NewLineHandling = 'Replace'
    $writer = [System.Xml.XmlWriter]::Create($temporaryPath, $writerSettings)
    try { $profileDocument.Save($writer) } finally { $writer.Dispose() }

    $writtenDocument = Read-XmlDocument -Path $temporaryPath
    $writtenStatus = Get-ConfigurationStatus -Document $writtenDocument -TargetDeviceIds $DeviceIds -RequireAllDevices
    if (-not $writtenStatus.IsConfigured) {
        throw "Written configuration failed validation:`n$($writtenStatus.Issues -join "`n")"
    }

    [System.IO.File]::Move($temporaryPath, $resolvedProfile, $true)
} finally {
    if (Test-Path -LiteralPath $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
}

Write-Output "Installed: $resolvedProfile"
if (-not $NoBackup) { Write-Output "Backup: $backupPath" }
Write-Output "Mapped $wheelButtonId to Shift + Right Mouse Button for $($DeviceIds.Count) CadMouse device profiles and $($requiredBankIds.Count) Fusion button banks."
Write-Output 'Restart Windows (or sign out and back in) so 3DxWare loads the new profile.'
