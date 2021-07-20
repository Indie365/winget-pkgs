#Requires -Version 5
$PSVersion = (Get-Host).Version.Major
$ScriptHeader = '# Created with YamlCreate.ps1 v2.0.0'
$ManifestVersion = '1.0.0'

<#
.SYNOPSIS
    Winget Manifest creation helper script
.DESCRIPTION
    The intent of this file is to help you generate a manifest for publishing
    to the Windows Package Manager repository. 
    
    It'll attempt to download an installer from the user-provided URL to calculate
    a checksum. That checksum and the rest of the input data will be compiled in a 
    .YAML file.
.EXAMPLE
    PS C:\Projects\winget-pkgs> Get-Help .\Tools\YamlCreate.ps1 -Full
    Show this script's help
.EXAMPLE
    PS C:\Projects\winget-pkgs> .\Tools\YamlCreate.ps1
    Run the script to create a manifest file
.NOTES
    Please file an issue if you run into errors with this script:
    https://github.com/microsoft/winget-pkgs/issues/
.LINK
    https://github.com/microsoft/winget-pkgs/blob/master/Tools/YamlCreate.ps1
#>

<#
TO-DO:
    - Handle writing null parameters as comments
    - Ensure licensing for powershell-yaml is met
#>

if (Get-Module -ListAvailable -Name powershell-yaml) {
} 
else {
    try {
        Install-Module -Name powershell-yaml -Force -Repository PSGallery -Scope CurrentUser
    } 
    catch {
        Throw "Unmet dependency. 'powershell-yaml' unable to be installed successfully."
    }
}

filter TrimString {
    $_.Trim()
}

$ToNatural = { [regex]::Replace($_, '\d+', { $args[0].Value.PadLeft(20) }) }

Function Write-Colors {
    Param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [string[]] $TextStrings,
        [Parameter(Mandatory = $true, Position = 1)]
        [string[]] $Colors
    )
    If ($TextStrings.Count -ne $Colors.Count) { Throw "Invalid Function Parameters. Arguments must be of equal length" }
    $_index = 0
    Foreach ($String in $TextStrings) {
        Write-Host -ForegroundColor $Colors[$_index] -NoNewline $String
        $_index++
    }
}
Function Show-OptionMenu {
    Clear-Host
    Write-Host -ForegroundColor 'Cyan' "Select Mode"
    Write-Colors "`n[", "1", "] New Manifest or Package Version`n" 'DarkCyan', 'White', 'DarkCyan'
    Write-Colors "`n[", "2", "] Update Package Metadata`n" 'DarkCyan', 'White', 'DarkCyan'
    Write-Colors "`n[", "3", "] New Locale`n" 'DarkCyan', 'White', 'DarkCyan'
    Write-Colors "`n[", "q", "]", " Any key to quit`n" 'DarkCyan', 'White', 'DarkCyan', 'Red'
    Write-Colors "`nSelection: " 'White'

    $Keys = @{
        [ConsoleKey]::D1      = '1';
        [ConsoleKey]::D2      = '2';
        [ConsoleKey]::D3      = '3';
        [ConsoleKey]::NumPad1 = '1';
        [ConsoleKey]::NumPad2 = '2';
        [ConsoleKey]::NumPad3 = '3';
    }

    do {
        $keyInfo = [Console]::ReadKey($false)
    } until ($keyInfo.Key)

    switch ($Keys[$keyInfo.Key]) {
        '1' { $script:Option = 'New' }
        '2' { $script:Option = 'EditMetadata' }
        '3' { $script:Option = 'NewLocale' }
        default { Write-Host; exit }
    }
}

Function Read-WinGet-MandatoryInfo {
    while ($PackageIdentifier.Length -lt 4 -or $ID.Length -gt 255) {
        Write-Host "`n"
        Write-Host -ForegroundColor 'Green' -Object '[Required] Enter the Package Identifier, in the following format <Publisher shortname.Application shortname>. For example: Microsoft.Excel'
        $script:PackageIdentifier = Read-Host -Prompt 'PackageIdentifier' | TrimString
        $PackageIdentifierFolder = $PackageIdentifier.Replace('.', '\')
    }
    
    while ([string]::IsNullOrWhiteSpace($PackageVersion) -or $PackageName.Length -gt 128) {
        Write-Host
        Write-Host -ForegroundColor 'Green' -Object '[Required] Enter the version. for example: 1.33.7'
        $script:PackageVersion = Read-Host -Prompt 'Version' | TrimString
    }
    
    if (Test-Path -Path "$PSScriptRoot\..\manifests") {
        $ManifestsFolder = (Resolve-Path "$PSScriptRoot\..\manifests").Path
    }
    else {
        $ManifestsFolder = (Resolve-Path ".\").Path
    }
    
    $script:AppFolder = Join-Path $ManifestsFolder -ChildPath $PackageIdentifier.ToLower().Chars(0) | Join-Path -ChildPath $PackageIdentifierFolder | Join-Path -ChildPath $PackageVersion
}

Function Read-WinGet-InstallerValues {
    $InstallerValues = @(
        "Architecture"
        "InstallerType"
        "InstallerUrl"
        "InstallerSha256"
        "Custom"
        "Silent"
        "SilentWithProgress"
        "ProductCode"
        "Scope"
        "InstallerLocale"
        "UpgradeBehavior"
        "AnotherInstaller"
    )
    Foreach ($InstallerValue in $InstallerValues) { Clear-Variable -Name $InstallerValue -Force -ErrorAction SilentlyContinue }

    while ([string]::IsNullOrWhiteSpace($InstallerUrl)) {
        Write-Host
        Write-Host -ForegroundColor 'Green' -Object '[Required] Enter the download url to the installer.'
        $InstallerUrl = Read-Host -Prompt 'Url' | TrimString
    }

    Write-Host
    Write-Host -ForegroundColor 'White' "Save to disk?"
    Write-Host "Do you want to save the files to the Temp folder?"
    Write-Host -ForegroundColor 'White' -NoNewline "[Y] Yes  "
    Write-Host -ForegroundColor 'Yellow' -NoNewline '[N] No  '
    Write-Host -ForegroundColor 'White' -NoNewline "[M] Manually Enter SHA256 "
    Write-Host -NoNewline "(default is 'N'): "
    do {
        $keyInfo = [Console]::ReadKey($false)
    } until ($keyInfo.Key)

    switch ($keyInfo.Key) {
        'Y' { $SaveOption = '0' }
        'N' { $SaveOption = '1' }
        'M' { $SaveOption = '2' }
        default { $SaveOption = '1' }
    }

    if ($SaveOption -ne '2') {
        Write-Host
        $start_time = Get-Date
        Write-Host $NewLine
        Write-Host 'Downloading URL. This will take a while...' -ForegroundColor Blue
        $WebClient = New-Object System.Net.WebClient
        $Filename = [System.IO.Path]::GetFileName($InstallerUrl)
        $dest = "$env:TEMP\$FileName"

        try {
            $WebClient.DownloadFile($InstallerUrl, $dest)
        }
        catch {
            Write-Host 'Error downloading file. Please run the script again.' -ForegroundColor Red
            exit 1
        }
        finally {
            Write-Host "Time taken: $((Get-Date).Subtract($start_time).Seconds) second(s)" -ForegroundColor Green
            $InstallerSha256 = (Get-FileHash -Path $dest -Algorithm SHA256).Hash
            if ($PSVersion -eq '5') { $FileInformation = Get-AppLockerFileInformation -Path $dest | Select-Object -ExpandProperty Publisher }
            if ($PSVersion -eq '5') { $MSIProductCode = $FileInformation.BinaryName }
            if ($SaveOption -eq '1') { Remove-Item -Path $dest }
        }
    }

    else {
        while (!($InstallerSha256 -match '[0-9A-Z]{64}')) {
            Write-Host
            Write-Host
            Write-Host -ForegroundColor 'Green' -Object '[Required] Enter the installer SHA256 Hash'
            $InstallerSha256 = Read-Host -Prompt 'InstallerSha256' | TrimString
            $InstallerSHA256 = $InstallerSha256.toUpper()
        }
    }

    while ($architecture -notin @('x86', 'x64', 'arm', 'arm64', 'neutral')) {
        Write-Host
        Write-Host -ForegroundColor 'Green' -Object '[Required] Enter the architecture (x86, x64, arm, arm64, neutral)'
        $architecture = Read-Host -Prompt 'Architecture' | TrimString
    }

    while ($InstallerType -notin @('exe', 'msi', 'msix', 'inno', 'nullsoft', 'appx', 'wix', 'zip', 'burn', 'pwa')) {
        Write-Host
        Write-Host -ForegroundColor 'Green' -Object '[Required] Enter the InstallerType. For example: exe, msi, msix, inno, nullsoft, appx, wix, burn, pwa, zip'
        $InstallerType = Read-Host -Prompt 'InstallerType' | TrimString
    }

    if ($InstallerType -ieq 'exe') {
        while ([string]::IsNullOrWhiteSpace($Silent) -or ([string]::IsNullOrWhiteSpace($SilentWithProgress))) {
            Write-Host
            Write-Host -ForegroundColor 'Green' -Object '[Required] Enter the silent install switch. For example: /S, -verysilent, /qn, --silent, /exenoui'
            $Silent = Read-Host -Prompt 'Silent switch' | TrimString

            Write-Host
            Write-Host -ForegroundColor 'Green' -Object '[Required] Enter the silent with progress install switch. For example: /S, -silent, /qb, /exebasicui'
            $SilentWithProgress = Read-Host -Prompt 'Silent with progress switch' | TrimString

            do {
                Write-Host
                Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter any custom switches for the installer. For example: /norestart, -norestart'
                $Custom = Read-Host -Prompt 'Custom Switch' | TrimString
            } while ($Custom.Length -gt '2048')
        }
    }
    else {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the silent install switch. For example: /S, -verysilent, /qn, --silent'
            $Silent = Read-Host -Prompt 'Silent' | TrimString

            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the silent with progress install switch. For example: /S, -silent, /qb'
            $SilentWithProgress = Read-Host -Prompt 'SilentWithProgress' | TrimString

            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter any custom switches for the installer. For example: /norestart, -norestart'
            $Custom = Read-Host -Prompt 'CustomSwitch' | TrimString
        } while ($Silent.Length -gt '2048' -or $SilentWithProgress.Lenth -gt '512' -or $Custom.Length -gt '2048')
    }

    do {
        Write-Host
        Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the installer locale. For example: en-US, en-CA'
        Write-Host -ForegroundColor 'Blue' -Object 'https://docs.microsoft.com/en-us/openspecs/office_standards/ms-oe376/6c085406-a698-4e12-9d4d-c3b0ee3dbc4a'
        $ProductCode = Read-Host -Prompt 'InstallerLocale' | TrimString
    } while (-not [string]::IsNullOrWhiteSpace($InstallerLocale) -and ($InstallerLocale -gt 10))
    if ([string]::IsNullOrWhiteSpace($InstallerLocale)) { $InstallerLocale = 'en-US' }

    do {
        Write-Host
        Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the application product code. Looks like {CF8E6E00-9C03-4440-81C0-21FACB921A6B}'
        Write-Host -ForegroundColor 'White' -Object "ProductCode found from installer: $MSIProductCode"
        Write-Host -ForegroundColor 'White' -Object 'Can be found with ' -NoNewline; Write-Host -ForegroundColor 'DarkYellow' 'get-wmiobject Win32_Product | Sort-Object Name | Format-Table IdentifyingNumber, Name -AutoSize'
        $ProductCode = Read-Host -Prompt 'ProductCode' | TrimString
    } while (-not [string]::IsNullOrWhiteSpace($ProductCode) -and ($ProductCode.Length -lt 1 -or $ProductCode.Length -gt 255))

    Write-Host
    Write-Host -ForegroundColor 'White' "Scope"
    Write-Host "[Optional] Enter the Installer Scope."
    Write-Host -ForegroundColor 'White' -NoNewline "[M] Machine  [U] User  "
    Write-Host -ForegroundColor 'Yellow' -NoNewline '[N] No idea '
    Write-Host -NoNewline "(default is 'N'): "
    do {
        $keyInfo = [Console]::ReadKey($false)
    } until ($keyInfo.Key)

    switch ($keyInfo.Key) {
        'M' { $Scope = 'machine' }
        'U' { $Scope = 'user' }
        'N' { $Scope = '' }
        default { $Scope = '' }
    }

    Write-Host
    Write-Host
    Write-Host -ForegroundColor 'White' "UpgradeBehavior"
    Write-Host "[Optional] Enter the UpgradeBehavior."
    Write-Host -ForegroundColor 'Yellow' -NoNewline '[I] install  '
    Write-Host -ForegroundColor 'White' -NoNewline "[U] uninstallPrevious "
    Write-Host -NoNewline "(default is 'I'): "
    do {
        $keyInfo = [Console]::ReadKey($false)
    } until ($keyInfo.Key)

    switch ($keyInfo.Key) {
        'I' { $UpgradeBehavior = 'install' }
        'U' { $UpgradeBehavior = 'uninstallPrevious' }
        default { $UpgradeBehavior = 'install' }
    }
    
    if (!$script:Installers) {
        $script:Installers = @()
    }
    $_Installer = [ordered] @{}

    $_InstallerSingletons = [ordered] @{
        "InstallerLocale" = $InstallerLocale
        "Architecture"    = $Architecture
        "InstallerType"   = $InstallerType
        "Scope"           = $Scope
        "InstallerUrl"    = $InstallerUrl
        "InstallerSha256" = $InstallerSha256
    }
    foreach ($_Item in $_InstallerSingletons.GetEnumerator()) {
        If ($_Item.Value) { AddYamlParameter $_Installer $_Item.Name $_Item.Value }
    }

    If ($Silent -or $SilentWithProgress -or $Custom) {
        $_InstallerSwitches = [ordered]@{}
        $_Switches = [ordered] @{
            "Custom"             = $Custom
            "Silent"             = $Silent
            "SilentWithProgress" = $SilentWithProgress
        }
        
        foreach ($_Item in $_Switches.GetEnumerator()) {
            If ($_Item.Value) { AddYamlParameter $_InstallerSwitches $_Item.Name $_Item.Value }
        }
        $_Installer["InstallerSwitches"] = $_InstallerSwitches
    }

    If ($ProductCode) { AddYamlParameter $_Installer "ProductCode" $ProductCode }
    AddYamlParameter $_Installer "UpgradeBehavior" $UpgradeBehavior

    $script:Installers += $_Installer

    Write-Host
    Write-Host
    Write-Host -ForegroundColor 'White' "Another Installer"
    Write-Host "[Optional] Do you want to create another installer?"
    Write-Host -ForegroundColor 'White' -NoNewline "[Y] Yes  "
    Write-Host -ForegroundColor 'Yellow' -NoNewline '[N] No '
    Write-Host -NoNewline "(default is 'N'): "
    do {
        $keyInfo = [Console]::ReadKey($false)
    } until ($keyInfo.Key)

    switch ($keyInfo.Key) {
        'Y' { $AnotherInstaller = '0' }
        'N' { $AnotherInstaller = '1' }
        default { $AnotherInstaller = '1' }
    }

    if ($AnotherInstaller -eq '0') {
        Write-Host; Read-WinGet-InstallerValues
    }
}

Function PromptInstallerManifestValue {
    Param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [PSCustomObject] $Variable,
        [Parameter(Mandatory = $true, Position = 1)]
        [string] $Key,
        [Parameter(Mandatory = $true, Position = 2)]
        [string] $Prompt
    )
    Write-Host
    Write-Host -ForegroundColor 'Yellow' -Object $Prompt
    if (![string]::IsNullOrWhiteSpace($Variable)) { Write-Host -ForegroundColor 'DarkGray' "Old Value: $Variable" }
    $NewValue = Read-Host -Prompt $Key | TrimString

    if (-not [string]::IsNullOrWhiteSpace($NewValue)) {
        return $NewValue
    }
    else {
        return $Variable
    }
}

Function Read-WinGet-InstallerManifest {
    Write-Host
    do {
        if (!$FileExtensions) { $FileExtensions = '' }
        $script:FileExtensions = PromptInstallerManifestValue $FileExtensions 'FileExtensions' '[Optional] Enter any File Extensions the application could support. For example: html, htm, url (Max 256)'
    } while (($FileExtensions -split ", ").Count -gt '256')

    do {
        if (!$Protocols) { $Protocols = '' }
        $script:Protocols = PromptInstallerManifestValue $Protocols 'Protocols' '[Optional] Enter any Protocols the application provides a handler for. For example: http, https (Max 16)'
    } while (($Protocols -split ", ").Count -gt '16')

    do {
        if (!$Commands) { $Commands = '' }
        $script:Commands = PromptInstallerManifestValue $Commands 'Commands' '[Optional] Enter any Commands or aliases to run the application. For example: msedge (Max 16)'
    } while (($Commands -split ", ").Count -gt '16')

    do {
        if (!$InstallerSuccessCodes) { $InstallerSuccessCodes = '' }
        $script:InstallerSuccessCodes = PromptInstallerManifestValue $InstallerSuccessCodes 'InstallerSuccessCodes' '[Optional] List of additional non-zero installer success exit codes other than known default values by winget (Max 16)'
    } while (($InstallerSuccessCodes -split ", ").Count -gt '16')

    do {
        if (!$InstallModes) { $InstallModes = '' }
        $script:InstallModes = PromptInstallerManifestValue $InstallModes 'InstallModes' '[Optional] List of supported installer modes. Options: interactive, silent, silentWithProgress'
    } while (($InstallModes -split ", ").Count -gt '3')
}

Function Read-WinGet-LocaleManifest {
    while ([string]::IsNullOrWhiteSpace($PackageLocale) -or $PackageLocale.Length -gt '128') {
        Write-Host
        Write-Host -ForegroundColor 'Green' -Object '[Required] Enter the Package Locale. For example: en-US, en-CA https://docs.microsoft.com/en-us/openspecs/office_standards/ms-oe376/6c085406-a698-4e12-9d4d-c3b0ee3dbc4a'
        $script:PackageLocale = Read-Host -Prompt 'PackageLocale' | TrimString
    }
    
    if ([string]::IsNullOrWhiteSpace($Publisher)) {
        while ([string]::IsNullOrWhiteSpace($Publisher) -or $Publisher.Length -gt '128') {
            Write-Host
            Write-Host -ForegroundColor 'Green' -Object '[Required] Enter the full publisher name. For example: Microsoft Corporation'
            $script:Publisher = Read-Host -Prompt 'Publisher' | TrimString
        }
    }
    else {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the full publisher name. For example: Microsoft Corporation'
            Write-Host -ForegroundColor 'DarkGray' "Old Variable: $Publisher"
            $NewPublisher = Read-Host -Prompt 'Publisher' | TrimString
    
            if (-not [string]::IsNullOrWhiteSpace($NewPublisher)) {
                $script:Publisher = $NewPublisher
            }
        } while ($Publisher.Length -gt '128')
    }

    if ([string]::IsNullOrWhiteSpace($PackageName)) {
        while ([string]::IsNullOrWhiteSpace($PackageName) -or $PackageName.Length -gt '128') {
            Write-Host
            Write-Host -ForegroundColor 'Green' -Object '[Required] Enter the full application name. For example: Microsoft Teams'
            $script:PackageName = Read-Host -Prompt 'PackageName' | TrimString
        }
    }
    else {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the full application name. For example: Microsoft Teams'
            Write-Host -ForegroundColor 'DarkGray' "Old Variable: $PackageName"
            $NewPackageName = Read-Host -Prompt 'PackageName' | TrimString
    
            if (-not [string]::IsNullOrWhiteSpace($NewPackageName)) {
                $script:PackageName = $NewPackageName
            }
        } while ($PackageName.Length -gt '128')
    }

    if ([string]::IsNullOrWhiteSpace($Moniker)) {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the Moniker (friendly name/alias). For example: vscode'
            $script:Moniker = Read-Host -Prompt 'Moniker' | TrimString
        } while ($Moniker.Length -gt '40')
    }
    else {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the Moniker (friendly name/alias). For example: vscode'
            Write-Host -ForegroundColor 'DarkGray' "Old Variable: $Moniker"
            $NewMoniker = Read-Host -Prompt 'Moniker' | TrimString
    
            if (-not [string]::IsNullOrWhiteSpace($NewMoniker)) {
                $script:Moniker = $NewMoniker
            }
        } while ($Moniker.Length -gt '40')
    }

    if ([string]::IsNullOrWhiteSpace($PublisherUrl)) {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the Publisher Url.'
            $script:PublisherUrl = Read-Host -Prompt 'Publisher Url' | TrimString
        } while (-not [string]::IsNullOrWhiteSpace($PublisherUrl) -and ($PublisherUrl.Length -lt 5 -or $LicenseUrl.Length -gt 2000))
    }
    else {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the Publisher Url.'
            Write-Host -ForegroundColor 'DarkGray' "Old Variable: $PublisherUrl"
            $NewPublisherUrl = Read-Host -Prompt 'Publisher Url' | TrimString
    
            if (-not [string]::IsNullOrWhiteSpace($NewNewPublisherUrl)) {
                $script:PublisherUrl = $NewPublisherUrl
            }
        } while (-not [string]::IsNullOrWhiteSpace($PublisherUrl) -and ($PublisherUrl.Length -lt 5 -or $LicenseUrl.Length -gt 2000))
    }

    if ([string]::IsNullOrWhiteSpace($PublisherSupportUrl)) {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the Publisher Support Url.'
            $script:PublisherSupportUrl = Read-Host -Prompt 'Publisher Support Url' | TrimString
        } while (-not [string]::IsNullOrWhiteSpace($PublisherSupportUrl) -and ($PublisherSupportUrl.Length -lt 5 -or $PublisherSupportUrl.Length -gt 2000))
    }
    else {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the Publisher Support Url.'
            Write-Host -ForegroundColor 'DarkGray' "Old Variable: $PublisherSupportUrl"
            $NewPublisherSupportUrl = Read-Host -Prompt 'Publisher Support Url' | TrimString
    
            if (-not [string]::IsNullOrWhiteSpace($NewPublisherSupportUrl)) {
                $script:PublisherSupportUrl = $NewPublisherSupportUrl
            }
        } while (-not [string]::IsNullOrWhiteSpace($PublisherSupportUrl) -and ($PublisherSupportUrl.Length -lt 5 -or $PublisherSupportUrl.Length -gt 2000))
    }

    if ([string]::IsNullOrWhiteSpace($PrivacyUrl)) {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the Publisher Privacy Url.'
            $script:PrivacyUrl = Read-Host -Prompt 'Privacy Url' | TrimString
        } while (-not [string]::IsNullOrWhiteSpace($PrivacyUrl) -and ($PrivacyUrl.Length -lt 5 -or $PrivacyUrl.Length -gt 2000))
    }
    else {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the Publisher Privacy Url.'
            Write-Host -ForegroundColor 'DarkGray' "Old Variable: $PrivacyUrl"
            $NewPrivacyUrl = Read-Host -Prompt 'Privacy Url' | TrimString
    
            if (-not [string]::IsNullOrWhiteSpace($NewPrivacyUrl)) {
                $script:PrivacyUrl = $NewPrivacyUrl
            }
        } while (-not [string]::IsNullOrWhiteSpace($PrivacyUrl) -and ($PrivacyUrl.Length -lt 5 -or $PrivacyUrl.Length -gt 2000))
    }

    if ([string]::IsNullOrWhiteSpace($Author)) {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the application Author.'
            $script:Author = Read-Host -Prompt 'Author' | TrimString
        } while (-not [string]::IsNullOrWhiteSpace($Author) -and ($Author.Length -lt 2 -or $Author.Length -gt 256))
    }
    else {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the application Author.'
            Write-Host -ForegroundColor 'DarkGray' "Old Variable: $Author"
            $NewAuthor = Read-Host -Prompt 'Author' | TrimString
    
            if (-not [string]::IsNullOrWhiteSpace($NewAuthor)) {
                $script:Author = $NewAuthor
            }
        } while (-not [string]::IsNullOrWhiteSpace($Author) -and ($Author.Length -lt 2 -or $Author.Length -gt 256))
    }

    if ([string]::IsNullOrWhiteSpace($PackageUrl)) {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the Url to the homepage of the application.'
            $script:PackageUrl = Read-Host -Prompt 'Homepage' | TrimString
        } while (-not [string]::IsNullOrWhiteSpace($PackageUrl) -and ($PackageUrl.Length -lt 5 -or $PackageUrl.Length -gt 2000))
    }
    else {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the Url to the homepage of the application.'
            Write-Host -ForegroundColor 'DarkGray' "Old Variable: $PackageUrl"
            $NewPackageUrl = Read-Host -Prompt 'Homepage' | TrimString
    
            if (-not [string]::IsNullOrWhiteSpace($NewPackageUrl)) {
                $script:PackageUrl = $NewPackageUrl
            }
        } while (-not [string]::IsNullOrWhiteSpace($PackageUrl) -and ($PackageUrl.Length -lt 5 -or $PackageUrl.Length -gt 2000))
    }

    if ([string]::IsNullOrWhiteSpace($License)) {
        while ([string]::IsNullOrWhiteSpace($License) -or $License.Length -gt 512) {
            Write-Host
            Write-Host -ForegroundColor 'Green' -Object '[Required] Enter the application License. For example: MIT, GPL, Freeware, Proprietary'
            $script:License = Read-Host -Prompt 'License' | TrimString
        }
    }
    else {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the application License. For example: MIT, GPL, Freeware, Proprietary'
            Write-Host -ForegroundColor 'DarkGray' "Old Variable: $License"
            $NewLicense = Read-Host -Prompt 'License' | TrimString
    
            if (-not [string]::IsNullOrWhiteSpace($NewLicense)) {
                $script:License = $NewLicense
            }
        } while ([string]::IsNullOrWhiteSpace($License) -or $License.Length -gt 512)
    }

    if ([string]::IsNullOrWhiteSpace($LicenseUrl)) {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the application License URL.'
            $script:LicenseUrl = Read-Host -Prompt 'License URL' | TrimString
        } while (-not [string]::IsNullOrWhiteSpace($LicenseUrl) -and ($LicenseUrl.Length -lt 10 -or $LicenseUrl.Length -gt 2000))
    }
    else {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the application License URL.'
            Write-Host -ForegroundColor 'DarkGray' "Old Variable: $LicenseUrl"
            $NewLicenseUrl = Read-Host -Prompt 'License URL' | TrimString
    
            if (-not [string]::IsNullOrWhiteSpace($NewLicenseUrl)) {
                $script:LicenseUrl = $NewLicenseUrl
            }
        } while (-not [string]::IsNullOrWhiteSpace($LicenseUrl) -and ($LicenseUrl.Length -lt 10 -or $LicenseUrl.Length -gt 2000))
    }

    if ([string]::IsNullOrWhiteSpace($Copyright)) {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the application Copyright. For example: Copyright (c) Microsoft Corporation'
            $script:Copyright = Read-Host -Prompt 'Copyright' | TrimString
        } while (-not [string]::IsNullOrWhiteSpace($Copyright) -and ($Copyright.Length -lt 5 -or $Copyright.Length -gt 512))
    }
    else {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the application Copyright. For example: Copyright (c) Microsoft Corporation'
            Write-Host -ForegroundColor 'DarkGray' "Old Variable: $Copyright"
            $NewCopyright = Read-Host -Prompt 'Copyright' | TrimString
    
            if (-not [string]::IsNullOrWhiteSpace($NewCopyright)) {
                $script:Copyright = $NewCopyright
            }
        } while (-not [string]::IsNullOrWhiteSpace($Copyright) -and ($Copyright.Length -lt 5 -or $Copyright.Length -gt 512))
    }

    if ([string]::IsNullOrWhiteSpace($CopyrightUrl)) {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the application Copyright Url.'
            $script:CopyrightUrl = Read-Host -Prompt 'CopyrightUrl' | TrimString
        } while (-not [string]::IsNullOrWhiteSpace($CopyrightUrl) -and ($LicenseUrl.Length -lt 10 -or $LicenseUrl.Length -gt 2000))
    }
    else {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter the application Copyright Url.'
            Write-Host -ForegroundColor 'DarkGray' "Old Variable: $CopyrightUrl"
            $NewCopyrightUrl = Read-Host -Prompt 'CopyrightUrl' | TrimString
    
            if (-not [string]::IsNullOrWhiteSpace($NewCopyrightUrl)) {
                $script:CopyrightUrl = $NewCopyrightUrl
            }
        } while (-not [string]::IsNullOrWhiteSpace($CopyrightUrl) -and ($LicenseUrl.Length -lt 10 -or $LicenseUrl.Length -gt 2000))
    }

    if ([string]::IsNullOrWhiteSpace($Tags)) {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter any tags that would be useful to discover this tool. For example: zip, c++ (Max 16)'
            $script:Tags = Read-Host -Prompt 'Tags' | TrimString
        } while (($Tags -split ", ").Count -gt '16')
    }
    else {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter any tags that would be useful to discover this tool. For example: zip, c++ (Max 16)'
            Write-Host -ForegroundColor 'DarkGray' "Old Variable: $Tags"
            $NewTags = Read-Host -Prompt 'Tags' | TrimString
    
            if (-not [string]::IsNullOrWhiteSpace($NewTags)) {
                $script:Tags = $NewTags
            }
        } while (($Tags -split ", ").Count -gt '16')
    }

    if ([string]::IsNullOrWhiteSpace($ShortDescription)) {
        while ([string]::IsNullOrWhiteSpace($ShortDescription) -or $ShortDescription.Length -gt '256') {
            Write-Host
            Write-Host -ForegroundColor 'Green' -Object '[Required] Enter a short description of the application.'
            $script:ShortDescription = Read-Host -Prompt 'Short Description' | TrimString
        }
    }
    else {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter a short description of the application.'
            Write-Host -ForegroundColor 'DarkGray' "Old Variable: $ShortDescription"
            $NewShortDescription = Read-Host -Prompt 'Short Description' | TrimString
    
            if (-not [string]::IsNullOrWhiteSpace($NewShortDescription)) {
                $script:ShortDescription = $NewShortDescription
            }
        } while ([string]::IsNullOrWhiteSpace($ShortDescription) -or $ShortDescription.Length -gt '256')
    }

    if ([string]::IsNullOrWhiteSpace($Description)) {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter a long description of the application.'
            $script:Description = Read-Host -Prompt 'Long Description' | TrimString
        } while (-not [string]::IsNullOrWhiteSpace($Description) -and ($Description.Length -lt 3 -or $Description.Length -gt 10000))
    }
    else {
        do {
            Write-Host
            Write-Host -ForegroundColor 'Yellow' -Object '[Optional] Enter a long description of the application.'
            Write-Host -ForegroundColor 'DarkGray' "Old Variable: $Description"
            $NewDescription = Read-Host -Prompt 'Description' | TrimString
    
            if (-not [string]::IsNullOrWhiteSpace($NewDescription)) {
                $script:Description = $NewDescription
            }
        } while (-not [string]::IsNullOrWhiteSpace($Description) -and ($Description.Length -lt 3 -or $Description.Length -gt 10000))
    }

}

Function Test-Manifest {
    if (Get-Command 'winget.exe' -ErrorAction SilentlyContinue) { winget validate $AppFolder }

    if (Get-Command 'WindowsSandbox.exe' -ErrorAction SilentlyContinue) {
        Write-Host
        Write-Host -ForegroundColor 'White' "Sandbox Test"
        Write-Host "[Recommended] Do you want to test your Manifest in Windows Sandbox?"
        Write-Host -ForegroundColor 'Yellow' -NoNewline '[Y] Yes  '
        Write-Host -ForegroundColor 'White' -NoNewline "[N] No "
        Write-Host -NoNewline "(default is 'Y'): "
        do {
            $keyInfo = [Console]::ReadKey($false)
        } until ($keyInfo.Key)

        switch ($keyInfo.Key) {
            'Y' { $SandboxTest = '0' }
            'N' { $SandboxTest = '1' }
            default { $SandboxTest = '0' }
        }

        if ($SandboxTest -eq '0') {
            if (Test-Path -Path "$PSScriptRoot\SandboxTest.ps1") {
                $SandboxScriptPath = (Resolve-Path "$PSScriptRoot\SandboxTest.ps1").Path
            }
            else {
                while ([string]::IsNullOrWhiteSpace($SandboxScriptPath)) {
                    Write-Host
                    Write-Host -ForegroundColor 'Green' -Object 'SandboxTest.ps1 not found, input path'
                    $SandboxScriptPath = Read-Host -Prompt 'SandboxTest.ps1' | TrimString
                }
            }

            & $SandboxScriptPath -Manifest $AppFolder
        }
    }
}

Function Submit-Manifest {
    if (Get-Command 'git.exe' -ErrorAction SilentlyContinue) {
        Write-Host
        Write-Host
        Write-Host -ForegroundColor 'White' "Submit PR?"
        Write-Host "Do you want to submit your PR now?"
        Write-Host -ForegroundColor 'Yellow' -NoNewline '[Y] Yes  '
        Write-Host -ForegroundColor 'White' -NoNewline "[N] No "
        Write-Host -NoNewline "(default is 'Y'): "
        do {
            $keyInfo = [Console]::ReadKey($false)
        } until ($keyInfo.Key)

        switch ($keyInfo.Key) {
            'Y' { $PromptSubmit = '0' }
            'N' { $PromptSubmit = '1' }
            default { $PromptSubmit = '0' }
        }
    }

    if ($PromptSubmit -eq '0') {
        switch ($Option) {
            'New' {
                if ($script:OldManifestType -eq 'None') { $CommitType = 'New' }
                else {
                    $CommitType = 'Update'
                }
            }
            'EditMetadata' { $CommitType = 'Metadata' }
            'NewLocale' { $CommitType = 'Locale' }
        }

        git fetch upstream
        git checkout -b "$PackageIdentifier-$PackageVersion" FETCH_HEAD

        git add -A
        git commit -m "$CommitType`: $PackageIdentifier version $PackageVersion"
        git push

        if (Get-Command 'gh.exe' -ErrorAction SilentlyContinue) {
        
            if (Test-Path -Path "$PSScriptRoot\..\.github\PULL_REQUEST_TEMPLATE.md") {
                gh pr create --body-file "$PSScriptRoot\..\.github\PULL_REQUEST_TEMPLATE.md" -f
            }
            else {
                while ([string]::IsNullOrWhiteSpace($SandboxScriptPath)) {
                    Write-Host
                    Write-Host -ForegroundColor 'Green' -Object 'PULL_REQUEST_TEMPLATE.md not found, input path'
                    $PRTemplate = Read-Host -Prompt 'PR Template' | TrimString
                }
                gh pr create --body-file "$PRTemplate" -f
            }
        }
    }
    else {
        Write-Host
        Exit
    }
}

Function AddYamlListParameter {
    Param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [PSCustomObject] $Object,
        [Parameter(Mandatory = $true, Position = 1)]
        [string] $Parameter,
        [Parameter(Mandatory = $true, Position = 2)]
        $Values
    )
    $_Values = @()
    Foreach ($Value in $Values.Split(",").Trim()) {
        try {
            $Value = [int]$Value
        }
        catch {}
        $_Values += $Value
    }
    $Object[$Parameter] = $_Values
}

Function AddYamlParameter {
    Param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [PSCustomObject] $Object,
        [Parameter(Mandatory = $true, Position = 1)]
        [string] $Parameter,
        [Parameter(Mandatory = $true, Position = 2)]
        [string] $Value
    )
    $Object[$Parameter] = $Value
}

Function GetMultiManifestParameter {
    Param(
        [Parameter(Mandatory = $true, Position = 1)]
        [string] $Parameter
    )
    $_vals = $($script:OldInstallerManifest[$Parameter] + $script:OldLocaleManifest[$Parameter] + $script:OldVersionManifest[$Parameter] | Where-Object { $_ })
    return ($_vals -join ", ")
}
Function Write-WinGet-VersionManifest-Yaml {
    [PSCustomObject]$VersionManifest = [ordered]@{}

    $_Singletons = [ordered]@{
        "PackageIdentifier" = $PackageIdentifier
        "PackageVersion"    = $PackageVersion
        "DefaultLocale"     = "en-US"
        "ManifestType"      = "version"
        "ManifestVersion"   = $ManifestVersion
    }

    foreach ($_Item in $_Singletons.GetEnumerator()) {
        If ($_Item.Value) { AddYamlParameter $VersionManifest $_Item.Name $_Item.Value }
    }

    
    New-Item -ItemType "Directory" -Force -Path $AppFolder | Out-Null
    $VersionManifestPath = $AppFolder + "\$PackageIdentifier" + '.yaml'
    
    #TO-DO: Write keys with no values as comments
    
    $ScriptHeader + " using YAML parsing`n# yaml-language-server: `$schema=https://aka.ms/winget-manifest.version.1.0.0.schema.json`n" > $VersionManifestPath
    ConvertTo-Yaml $VersionManifest >> $VersionManifestPath
    
    Write-Host 
    Write-Host "Yaml file created: $VersionManifestPath"
}
Function Write-WinGet-InstallerManifest-Yaml {

    if ($script:OldManifestType = 'MultiManifest') {
        $InstallerManifest = $script:OldInstallerManifest
    }

    if (!$InstallerManifest) { [PSCustomObject]$InstallerManifest = [ordered]@{} }

    AddYamlParameter $InstallerManifest "PackageIdentifier" $PackageIdentifier
    AddYamlParameter $InstallerManifest "PackageVersion" $PackageVersion
    $InstallerManifest["MinimumOSVersion"] = If ($MinimumOSVersion) { $MinimumOSVersion } Else { "10.0.0.0" }

    $_ListSections = [ordered]@{
        "FileExtensions"        = $FileExtensions
        "Protocols"             = $Protocols
        "Commands"              = $Commands
        "InstallerSuccessCodes" = $InstallerSuccessCodes
        "InstallModes"          = $InstallModes
    }
    foreach ($Section in $_ListSections.GetEnumerator()) {
        If ($Section.Value) { AddYamlListParameter $InstallerManifest $Section.Name $Section.Value }
    }

    if ($Option -ne 'EditMetadata') {
        $InstallerManifest["Installers"] = $script:Installers
    }
    elseif ($script:OldInstallerManifest) {
        $InstallerManifest["Installers"] = $script:OldInstallerManifest["Installers"]
    }
    else {
        $InstallerManifest["Installers"] = $script:OldVersionManifest["Installers"]
    }

    AddYamlParameter $InstallerManifest "ManifestType" "installer"
    AddYamlParameter $InstallerManifest "ManifestVersion" $ManifestVersion
   
    New-Item -ItemType "Directory" -Force -Path $AppFolder | Out-Null
    $InstallerManifestPath = $AppFolder + "\$PackageIdentifier" + '.installer' + '.yaml'
    
    #TO-DO: Write keys with no values as comments
    
    $ScriptHeader + " using YAML parsing`n# yaml-language-server: `$schema=https://aka.ms/winget-manifest.installer.1.0.0.schema.json`n" > $InstallerManifestPath
    ConvertTo-Yaml $InstallerManifest >> $InstallerManifestPath

    Write-Host 
    Write-Host "Yaml file created: $InstallerManifestPath"
}

Function Write-WinGet-LocaleManifest-Yaml {
    
    if ($script:OldManifestType = 'MultiManifest') {
        $LocaleManifest = $script:OldLocaleManifest
    }
    
    if (!$LocaleManifest) { [PSCustomObject]$LocaleManifest = [ordered]@{} }
    
    if ($PackageLocale -eq 'en-US') { $yamlServer = '# yaml-language-server: $schema=https://aka.ms/winget-manifest.defaultLocale.1.0.0.schema.json' }else { $yamlServer = '# yaml-language-server: $schema=https://aka.ms/winget-manifest.locale.1.0.0.schema.json' }
    
    $_Singletons = [ordered]@{
        "PackageIdentifier"   = $PackageIdentifier
        "PackageVersion"      = $PackageVersion
        "PackageLocale"       = $PackageLocale
        "Publisher"           = $Publisher
        "PublisherUrl"        = $PublisherUrl
        "PublisherSupportUrl" = $PublisherSupportUrl
        "PrivacyUrl"          = $PrivacyUrl
        "Author"              = $Author
        "PackageName"         = $PackageName
        "PackageUrl"          = $PackageUrl
        "License"             = $License
        "LicenseUrl"          = $LicenseUrl
        "Copyright"           = $Copyright
        "CopyrightUrl"        = $CopyrightUrl
        "ShortDescription"    = $ShortDescription
        "Description"         = $Description
    }

    foreach ($_Item in $_Singletons.GetEnumerator()) {
        If ($_Item.Value) { AddYamlParameter $LocaleManifest $_Item.Name $_Item.Value }
    }

    If ($Tags) { AddYamlListParameter $LocaleManifest "Tags" $Tags }
    If ($Moniker -and $PackageLocale -eq 'en-US') { AddYamlParameter $LocaleManifest "Moniker" $Moniker }
    If ($PackageLocale -eq 'en-US') { $_ManifestType = "defaultLocale" }else { $_ManifestType = "locale" }
    AddYamlParameter $LocaleManifest "ManifestType" $_ManifestType
    AddYamlParameter $LocaleManifest "ManifestVersion" $ManifestVersion

    New-Item -ItemType "Directory" -Force -Path $AppFolder | Out-Null
    $LocaleManifestPath = $AppFolder + "\$PackageIdentifier" + ".locale." + "$PackageLocale" + '.yaml'

    #TO-DO: Write keys with no values as comments

    $ScriptHeader + " using YAML parsing`n$yamlServer`n" > $LocaleManifestPath
    ConvertTo-Yaml $LocaleManifest >> $LocaleManifestPath

    if ($OldManifests) {
        ForEach ($DifLocale in $OldManifests) {
            if ($DifLocale.Name -notin @("$PackageIdentifier.yaml", "$PackageIdentifier.installer.yaml", "$PackageIdentifier.locale.en-US.yaml")) {
                if (!(Test-Path $AppFolder)) { New-Item -ItemType "Directory" -Force -Path $AppFolder | Out-Null }
                $script:OldLocaleManifest = ConvertFrom-Yaml -Yaml (Get-Content -Path $DifLocale.FullName -Raw) -Ordered
                $script:OldLocaleManifest["PackageVersion"] = $PackageVersion

                $yamlServer = '# yaml-language-server: $schema=https://aka.ms/winget-manifest.locale.1.0.0.schema.json'
            
                $ScriptHeader + " using YAML parsing`n$yamlServer`n" > ($AppFolder + "\" + $DifLocale.Name)
                ConvertTo-Yaml $OldLocaleManifest >> ($AppFolder + "\" + $DifLocale.Name)
            }
        }
    }

    Write-Host 
    Write-Host "Yaml file created: $LocaleManifestPath"
}


Function Read-PreviousWinGet-Manifest-Yaml {
    
    if (($Option -eq 'NewLocale') -or ($Option -eq 'EditMetadata')) {
        if (Test-Path  -Path "$AppFolder\..\$PackageVersion") {
            $script:OldManifests = Get-ChildItem -Path "$AppFolder\..\$PackageVersion"
            $LastVersion = $PackageVersion
        }
        while (-not ($OldManifests.Name -like "$PackageIdentifier*.yaml")) {
            Write-Host
            Write-Host -ForegroundColor 'Red' -Object 'Could not find required manifests, input a version containing required manifests or "exit" to cancel'
            $PromptVersion = Read-Host -Prompt 'Version' | TrimString
            if ($PromptVersion -eq 'exit') { exit 1 }
            if (Test-Path -Path "$AppFolder\..\$PromptVersion") {
                $script:OldManifests = Get-ChildItem -Path "$AppFolder\..\$PromptVersion" 
            }
            $LastVersion = $PromptVersion
            $script:AppFolder = (Split-Path $AppFolder) + "\$LastVersion"
            $script:PackageVersion = $LastVersion
        }
    }

    if (-not (Test-Path  -Path "$AppFolder\..")) {
        $script:OldManifestType = 'None'
        return
    }
    
    if (!$LastVersion) {
        try {
            $LastVersion = Split-Path (Split-Path (Get-ChildItem -Path "$AppFolder\..\" -Recurse -Depth 1 -File).FullName ) -Leaf | Sort-Object $ToNatural | Select-Object -Last 1
            Write-Host -ForegroundColor 'DarkYellow' -Object "Found Existing Version: $LastVersion"
            $script:OldManifests = Get-ChildItem -Path "$AppFolder\..\$LastVersion"
        }
        catch {
            Out-Null
        }
    }

    if ($OldManifests.Name -eq "$PackageIdentifier.installer.yaml" -and $OldManifests.Name -eq "$PackageIdentifier.locale.en-US.yaml" -and $OldManifests.Name -eq "$PackageIdentifier.yaml") {
        $script:OldManifestType = 'MultiManifest'
        $script:OldInstallerManifest = ConvertFrom-Yaml -Yaml (Get-Content -Path $(Resolve-Path "$AppFolder\..\$LastVersion\$PackageIdentifier.installer.yaml") -Raw) -Ordered
        $script:OldLocaleManifest = ConvertFrom-Yaml -Yaml (Get-Content -Path $(Resolve-Path "$AppFolder\..\$LastVersion\$PackageIdentifier.locale.en-US.yaml") -Raw) -Ordered
        $script:OldVersionManifest = ConvertFrom-Yaml -Yaml (Get-Content -Path $(Resolve-Path "$AppFolder\..\$LastVersion\$PackageIdentifier.yaml") -Raw) -Ordered
    }
    elseif ($OldManifests.Name -eq "$PackageIdentifier.yaml") {
        if ($Option -eq 'NewLocale') { Throw "Error: MultiManifest Required" }
        $script:OldManifestType = 'Singleton'
        $script:OldVersionManifest = ConvertFrom-Yaml -Yaml (Get-Content -Path $(Resolve-Path "$AppFolder\..\$LastVersion\$PackageIdentifier.yaml") -Raw) -Ordered
    }
    else {
        Throw "Error: Version $LastVersion does not contain the required manifests"
    }

    if ($OldManifests) {

        $_Parameters = @(
            "Publisher"; "PublisherUrl"; "PublisherSupportUrl"; "PrivacyUrl"
            "Author"; 
            "PackageName"; "PackageUrl"; "Moniker"
            "License"; "LicenseUrl"
            "Copyright"; "CopyrightUrl"
            "ShortDescription"; "Description"
            "Channel"
            "Platform"; "MinimumOSVersion"
            "InstallerType"
            "Scope"
            "UpgradeBehavior"
            "PackageFamilyName"; "ProductCode"
            "Tags"; "FileExtensions"
            "Protocols"; "Commands"
            "InstallModes"; "InstallerSuccessCodes"
            "Capabilities"; "RestrictedCapabilities"
        )

        Foreach ($param in $_Parameters) {
            New-Variable -Name $param -Value $(if ($script:OldManifestType -eq 'MultiManifest') { (GetMultiManifestParameter $param) } else { $script:OldVersionManifest[$param] }) -Scope Script -Force
        }
    }
}
        
Show-OptionMenu
Read-WinGet-MandatoryInfo
Read-PreviousWinGet-Manifest-Yaml

Switch ($Option) {
    
    'New' {
        Read-WinGet-InstallerValues
        Read-WinGet-InstallerManifest
        New-Variable -Name "PackageLocale" -Value "en-US" -Scope "Script" -Force
        Read-WinGet-LocaleManifest
        Write-WinGet-InstallerManifest-Yaml
        Write-WinGet-VersionManifest-Yaml
        Write-WinGet-LocaleManifest-Yaml
        Test-Manifest
        Submit-Manifest
    }

    'EditMetadata' {
        Read-WinGet-InstallerManifest
        New-Variable -Name "PackageLocale" -Value "en-US" -Scope "Script" -Force
        Read-WinGet-LocaleManifest
        Write-WinGet-InstallerManifest-Yaml
        Write-WinGet-VersionManifest-Yaml
        Write-WinGet-LocaleManifest-Yaml
        Test-Manifest
        Submit-Manifest
    }

    'Update' {
        # Read-PreviousWinGet-Manifest-Yaml
        Read-WinGet-InstallerValues
        Read-WinGet-InstallerManifest
        New-Variable -Name "PackageLocale" -Value "en-US" -Scope "Script" -Force
        Read-WinGet-LocaleManifest
        Write-WinGet-InstallerManifest-Yaml
        Write-WinGet-VersionManifest-Yaml
        Write-WinGet-LocaleManifest-Yaml
        Test-Manifest
        Submit-Manifest
    }

    'NewLocale' {
        # Read-PreviousWinGet-Manifest-Yaml
        Read-WinGet-LocaleManifest
        Write-WinGet-LocaleManifest-Yaml
        if (Get-Command "winget.exe" -ErrorAction SilentlyContinue) { winget validate $AppFolder }
        Submit-Manifest
    }
}
