﻿Write-Host "Commit Push and Create Pull Request"
$acceptedShortForms = @('um','am','amd','umd','pi','mpc','u','add','n','arp','pc','pcarp','r','url','urlpc','ss','fn','ssfn','404')
if ($args[0]) {$PkgId = $args[0]} else {$PkgId = Read-Host -Prompt 'Enter Package Name'}
if ($args[1]) {$PkgVersion = $args[1]} else {$PkgVersion = Read-Host -Prompt 'Enter Package Version'}
if ($args[2] -and $args[2] -in $acceptedShortForms) {
    $CommitType = $args[2]
} else {
    while ($CommitType -notin $acceptedShortForms) {
        $CommitType = Read-Host -Prompt 'Enter Commit Message'
    }
}
if ($CommitType -eq 'um') {$CommitType = "Update Moniker"}
elseif ($CommitType -eq 'am') {$CommitType = "Add Moniker"}
elseif ($CommitType -eq 'amd') {$CommitType = "Add Metadata"}
elseif ($CommitType -eq 'umd') {$CommitType = "Update Metadata"}
elseif ($CommitType -eq 'pi') {$CommitType = "PackageIdentifier"}
elseif ($CommitType -eq 'mpc') {$CommitType = "Moniker/ProductCode"}
elseif ($CommitType -eq 'u') {$CommitType = "New Version"}
elseif ($CommitType -eq 'add') {$CommitType = "Add Version"}
elseif ($CommitType -eq 'n') {$CommitType = "New Package"}
elseif ($CommitType -eq 'arp') {$CommitType = "ARP"}
elseif ($CommitType -eq 'pc') {$CommitType = "ProductCode"}
elseif ($CommitType -eq 'pcarp') {$CommitType = "ProductCode/ARP"}
elseif ($CommitType -eq 'r') {$CommitType = "Remove"}
elseif ($CommitType -eq 'url') {$CommitType = "InstallerUrl"}
elseif ($CommitType -eq 'urlpc') {$CommitType = "ProductCode/InstallerUrl"}
elseif ($CommitType -eq 'ss') {$CommitType = "SignatureSha256"}
elseif ($CommitType -eq 'fn') {$CommitType = "PackageFamilyName"}
elseif ($CommitType -eq 'ssfn') {$CommitType = "SignatureSha256/FamilyName"}
git fetch upstream master
git checkout -b "$PkgId-$PkgVersion" FETCH_HEAD
git add -A
git commit -m "$CommitType`: $PkgId version $PkgVersion"
git push
gh pr create --body-file "C:\Users\Bittu\Downloads\winget-pkgs\my-fork\.github\PULL_REQUEST_TEMPLATE.md" -f
git switch "master"