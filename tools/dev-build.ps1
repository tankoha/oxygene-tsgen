# Builds the Tsgen CLI and works around a known EBuild issue where
# non-copy-local / NuGet-resolved runtime dependencies are not fully
# registered in the generated deps.json (see HANDOFF.md sections 10 and 12).
# This is a dev-support script, not product code -- PowerShell is fine here
# even though CLAUDE.md's "always Oxygene" rule applies to src/.
#
# Environment-specific: the paths/version below assume RemObjects Elements
# 13.0.0.3101 installed at the default path; update RemObjectsElementsVersion
# if the local install is upgraded.

$ErrorActionPreference = "Stop"

$RemObjectsElementsVersion = "13.0.0.3101"
$ElementsBin = "C:\Program Files (x86)\RemObjects Software\Elements\Bin"
$EBuild = Join-Path $ElementsBin "EBuild.exe"

$root = Split-Path -Parent $PSScriptRoot
$projDir = Join-Path $root "src\Tsgen"
$outDir = Join-Path $projDir "Bin\Release"

& $EBuild (Join-Path $projDir "Tsgen.elements") /Configuration:Release
if ($LASTEXITCODE -ne 0) { throw "EBuild failed with exit code $LASTEXITCODE" }

Copy-Item (Join-Path $ElementsBin "RemObjects.Elements.dll") $outDir -Force
Copy-Item (Join-Path $ElementsBin "RemObjects.Elements.Code.dll") $outDir -Force
Copy-Item (Join-Path $ElementsBin "RemObjects.Elements.Oxygene.dll") $outDir -Force

$mlcPkgRoot = "$env:LOCALAPPDATA\RemObjects Software\EBuild\Packages\NuGet\system.reflection.metadataloadcontext"
$mlcPkgDir = Get-ChildItem $mlcPkgRoot | Sort-Object Name -Descending | Select-Object -First 1
$mlcVersion = $mlcPkgDir.Name
$mlcDll = Get-ChildItem -Recurse (Join-Path $mlcPkgDir.FullName "lib") -Filter "System.Reflection.MetadataLoadContext.dll" |
    Where-Object { $_.DirectoryName -match "net10\.0$" } | Select-Object -First 1
if (-not $mlcDll) {
    $mlcDll = Get-ChildItem -Recurse (Join-Path $mlcPkgDir.FullName "lib") -Filter "System.Reflection.MetadataLoadContext.dll" | Select-Object -First 1
}
Copy-Item $mlcDll.FullName $outDir -Force

$depsPath = Join-Path $outDir "tsgen.deps.json"
$deps = Get-Content $depsPath -Raw | ConvertFrom-Json
$tfm = $deps.runtimeTarget.name
$target = $deps.targets.$tfm
$projectEntry = $target.'tsgen/1.0.0'

function Add-RuntimeLibrary {
    param($Name, $Version, $DllFileName)

    $key = "$Name/$Version"
    $runtimeEntry = [PSCustomObject]@{ runtime = [PSCustomObject]@{} }
    $runtimeEntry.runtime | Add-Member -NotePropertyName $DllFileName -NotePropertyValue ([PSCustomObject]@{})
    $target | Add-Member -NotePropertyName $key -NotePropertyValue $runtimeEntry -Force

    $deps.libraries | Add-Member -NotePropertyName $key -NotePropertyValue ([PSCustomObject]@{
        type = "reference"; serviceable = $false; sha512 = ""
    }) -Force

    $projectEntry.dependencies | Add-Member -NotePropertyName $Name -NotePropertyValue $Version -Force
}

Add-RuntimeLibrary -Name "System.Reflection.MetadataLoadContext" -Version $mlcVersion -DllFileName "System.Reflection.MetadataLoadContext.dll"
Add-RuntimeLibrary -Name "RemObjects.Elements" -Version $RemObjectsElementsVersion -DllFileName "RemObjects.Elements.dll"
Add-RuntimeLibrary -Name "RemObjects.Elements.Code" -Version $RemObjectsElementsVersion -DllFileName "RemObjects.Elements.Code.dll"
Add-RuntimeLibrary -Name "RemObjects.Elements.Oxygene" -Version $RemObjectsElementsVersion -DllFileName "RemObjects.Elements.Oxygene.dll"

$deps | ConvertTo-Json -Depth 10 | Set-Content $depsPath -Encoding utf8

Write-Host "Build + deps.json patch complete: $outDir\tsgen.exe"
