# Parse Arguments

Param(
  [Parameter(Mandatory, HelpMessage = "The path for the Manifest.")]
  [String] $Manifest
)

if (-not (Test-Path -Path $Manifest -PathType Leaf)) {
  throw 'The Manifest file does not exist.'
}

# Validate manifest file
# We can't rely on status code until https://github.com/microsoft/winget-cli/issues/312 is solved
$validationResult = winget.exe validate $Manifest
if ($validationResult -like '*Manifest validation failed.*') {
  throw 'Manifest validation failed.'
}

# Check if Windows Sandbox is enabled

if (-Not (Test-Path "$env:windir\System32\WindowsSandbox.exe")) {
  Write-Error -Category NotInstalled -Message @'
Windows Sandbox does not seem to be available. Check the following URL for prerequisites and further details:    
https://docs.microsoft.com/en-us/windows/security/threat-protection/windows-sandbox/windows-sandbox-overview
  
You can run the following command in an elevated PowerShell for enabling Windows Sandbox:
Enable-WindowsOptionalFeature -Online -FeatureName 'Containers-DisposableClientVM'
'@ -ErrorAction Stop
}

# Set dependencies

$desktopAppInstaller = @{
  fileName = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.appxbundle'
  url      = 'https://github.com/microsoft/winget-cli/releases/download/v0.1.41821-preview/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.appxbundle'
  hash     = '3fff593736c8272a640b5ba0e48343ccc0bbc1630b11abf057c22cedb6ac8ec1'
}

$vcLibs = @{
  fileName = 'Microsoft.VCLibs.140.00_14.0.27810.0_x64__8wekyb3d8bbwe.Appx'
  url      = 'https://github.com/felipecassiors/winget-pkgs/raw/da8548d90369eb8f69a4738dc1474caaffb58e12/Tools/SandboxTest_Temp/Microsoft.VCLibs.140.00_14.0.27810.0_x64__8wekyb3d8bbwe.Appx'
  hash     = 'fe660c46a3ff8462d9574902e735687e92eeb835f75ec462a41ef76b54ef13ed'
}

$vcLibsUwp = @{
  fileName = 'Microsoft.VCLibs.140.00.UWPDesktop_14.0.27810.0_x64__8wekyb3d8bbwe.Appx'
  url      = 'https://raw.githubusercontent.com/felipecassiors/winget-pkgs/da8548d90369eb8f69a4738dc1474caaffb58e12/Tools/SandboxTest_Temp/Microsoft.VCLibs.140.00.UWPDesktop_14.0.27810.0_x64__8wekyb3d8bbwe.Appx'
  hash     = '66de9fde9d2ebf18893a890987f35d2d145c18cc5ee0e8ecaa09477dcc13b16b'
}

$dependencies = @($desktopAppInstaller, $vcLibs, $vcLibsUwp)

# Initialize Temp Folder

$tempFolder = Join-Path -Path $PSScriptRoot -ChildPath 'SandboxTest_Temp'

New-Item $tempFolder -ItemType Directory -ea 0 | Out-Null

Get-ChildItem $tempFolder -Recurse -Exclude $dependencies.fileName | Remove-Item -Force

Copy-Item -Path $Manifest -Destination $tempFolder

# Download dependencies

$WebClient = New-Object System.Net.WebClient

foreach ($dependency in $dependencies) {
  $dependency.file = Join-Path -Path $tempFolder -ChildPath $dependency.fileName

  # Only download if the file does not exist, or its hash does not match.
  if (-Not ((Test-Path -Path $dependency.file -PathType Leaf) -And $dependency.hash -eq $(get-filehash $dependency.file).Hash)) {
    # This downloads the file
    Write-Host "Downloading $($dependency.url) ..."
    try { 
      $WebClient.DownloadFile($dependency.url, $dependency.file) 
    } 
    catch {
      throw "Error downloading $($dependency.url) ."
    }
    if (-not ($dependency.hash -eq $(get-filehash $dependency.file).Hash)) {
      throw 'Hashes do not match, try gain.'
    }
  }
}

# Create Bootstrap script

$manifestFileName = Split-Path $Manifest -Leaf

$bootstrapPs1Content = @"
Set-PSDebug -Trace 1

Add-AppxPackage -Path '$($desktopAppInstaller.fileName)' -DependencyPath '$($vcLibs.fileName)','$($vcLibsUwp.fileName)'

winget install -m '$manifestFileName'
"@

$bootstrapPs1FileName = 'Bootstrap.ps1'
$bootstrapPs1Content | Out-File (Join-Path -Path $tempFolder -ChildPath $bootstrapPs1FileName)

# Create Wsb file

$tempFolderInSandbox = Join-Path -Path 'C:\Users\WDAGUtilityAccount\Desktop' -ChildPath (Split-Path $tempFolder -Leaf)

$sandboxTestWsbContent = @"
<Configuration>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$tempFolder</HostFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
  <Command>PowerShell Start-Process PowerShell -WorkingDirectory '$tempFolderInSandbox' -ArgumentList '-ExecutionPolicy Bypass -NoExit -File $bootstrapPs1FileName'</Command>
  </LogonCommand>
</Configuration>
"@

$sandboxTestWsbFileName = 'SandboxTest.wsb'
$sandboxTestWsbFile = Join-Path -Path $tempFolder -ChildPath $sandboxTestWsbFileName
$sandboxTestWsbContent | Out-File $sandboxTestWsbFile

Write-Host 'Starting Windows Sandbox and trying to install the manifest file.'

WindowsSandbox $SandboxTestWsbFile
