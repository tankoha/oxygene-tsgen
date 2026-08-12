# Snapshot test runner for oxygene-tsgen (HANDOFF.md §4 item 4 / §13
# deferred item 2). Builds the CLI and every fixture under tests/fixtures,
# then for each fixture's cases.json runs tsgen with the given flags and
# diffs the result against a committed expected/*.d.ts snapshot.
#
# Dev-support script, not product code -- PowerShell is fine here, same
# rationale as tools/dev-build.ps1.
#
# Usage:
#   tools\run-tests.ps1                 # run all snapshot tests
#   tools\run-tests.ps1 -UpdateSnapshots # regenerate expected/*.d.ts from current output

param(
    [switch]$UpdateSnapshots
)

$ErrorActionPreference = "Stop"

$RemObjectsElementsVersion = "13.0.0.3101"
$ElementsBin = "C:\Program Files (x86)\RemObjects Software\Elements\Bin"
$EBuild = Join-Path $ElementsBin "EBuild.exe"

$root = Split-Path -Parent $PSScriptRoot
$fixturesRoot = Join-Path $root "tests\fixtures"

# 1. Build the CLI itself (uses the deps.json-patching workaround, since
#    tsgen.exe actually runs; fixtures below only need to compile, since
#    they're loaded as metadata by tsgen, never executed).
Write-Host "==> Building tsgen CLI"
& (Join-Path $PSScriptRoot "dev-build.ps1")
if ($LASTEXITCODE -ne 0) { throw "Building tsgen failed" }
$tsgenExe = Join-Path $root "src\Tsgen\Bin\Release\tsgen.exe"
if (-not (Test-Path $tsgenExe)) { throw "tsgen.exe not found at $tsgenExe after build" }

function Normalize-Text {
    param([string]$Text)
    return ($Text -replace "`r`n", "`n").TrimEnd("`n")
}

$totalCases = 0
$failedCases = 0
$skippedFixtures = 0

Get-ChildItem $fixturesRoot -Directory | ForEach-Object {
    $fixtureDir = $_
    $elementsFile = Get-ChildItem $fixtureDir.FullName -Filter "*.elements" | Select-Object -First 1
    $casesFile = Join-Path $fixtureDir.FullName "cases.json"

    if (-not $elementsFile -or -not (Test-Path $casesFile)) {
        Write-Host "==> Skipping $($fixtureDir.Name) (no .elements project or cases.json)" -ForegroundColor DarkGray
        $script:skippedFixtures++
        return
    }

    # Some fixtures need a real second assembly to exist alongside their
    # own DLL (e.g. ExternalDependency, which regression-tests
    # AssemblyLoader.Load resolving a same-folder dependency DLL --
    # HANDOFF.md §31 / M3-dts-validation.md §3.1). Such a fixture's own
    # .elements project references that dependency by prebuilt-DLL
    # HintPath rather than EBuild's ProjectReference (which didn't resolve
    # standalone outside a .sln when tried), so its "Vendor" subproject
    # must be built first, here, every run -- its DLL is gitignored build
    # output like every other fixture DLL, never committed.
    $vendorElementsFiles = Get-ChildItem (Join-Path $fixtureDir.FullName "Vendor") -Filter "*.elements" -ErrorAction SilentlyContinue
    foreach ($vendorFile in $vendorElementsFiles) {
        Write-Host "==> Building $($fixtureDir.Name)'s dependency project $($vendorFile.Name)"
        & $EBuild $vendorFile.FullName /Configuration:Release | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Building $($fixtureDir.Name)'s dependency project $($vendorFile.Name) failed" }
    }

    Write-Host "==> Building fixture $($fixtureDir.Name)"
    & $EBuild $elementsFile.FullName /Configuration:Release | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Building fixture $($fixtureDir.Name) failed" }

    $dll = Get-ChildItem (Join-Path $fixtureDir.FullName "Bin\Release") -Filter "$($fixtureDir.Name).dll" | Select-Object -First 1
    if (-not $dll) { throw "Could not find $($fixtureDir.Name).dll after build" }

    $cases = Get-Content $casesFile -Raw | ConvertFrom-Json
    $actualRoot = Join-Path $fixtureDir.FullName "_actual"
    if (Test-Path $actualRoot) { Remove-Item -Recurse -Force $actualRoot }

    foreach ($case in $cases) {
        $script:totalCases++
        $outDir = Join-Path $actualRoot $case.name
        $tsgenArgs = @("generate", "--assembly", $dll.FullName, "--source", $fixtureDir.FullName, "--out", $outDir) + $case.args
        & $tsgenExe @tsgenArgs | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [FAIL] $($fixtureDir.Name)/$($case.name): tsgen exited with code $LASTEXITCODE" -ForegroundColor Red
            $script:failedCases++
            continue
        }

        $actualPath = Join-Path $outDir "index.d.ts"
        $expectedPath = Join-Path $fixtureDir.FullName $case.expected

        if ($UpdateSnapshots) {
            Copy-Item $actualPath $expectedPath -Force
            Write-Host "  [UPDATED] $($fixtureDir.Name)/$($case.name) -> $($case.expected)" -ForegroundColor Yellow
            continue
        }

        if (-not (Test-Path $expectedPath)) {
            Write-Host "  [FAIL] $($fixtureDir.Name)/$($case.name): no expected snapshot at $($case.expected) (run with -UpdateSnapshots to create it)" -ForegroundColor Red
            $script:failedCases++
            continue
        }

        $actual = Normalize-Text (Get-Content $actualPath -Raw)
        $expected = Normalize-Text (Get-Content $expectedPath -Raw)

        # PowerShell's -eq is case-INSENSITIVE for strings by default (a
        # well-known gotcha) -- this silently meant the whole snapshot
        # suite could never catch a case-only regression, discovered
        # while verifying the --naming-policy fix for issue #55 (see
        # HANDOFF.md §28): "Id" and "id" compared equal here. -ceq forces
        # ordinal/case-sensitive comparison, matching what "diff the
        # actual .d.ts against the expected one" should actually mean.
        if ($actual -ceq $expected) {
            Write-Host "  [PASS] $($fixtureDir.Name)/$($case.name)" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] $($fixtureDir.Name)/$($case.name): output does not match $($case.expected)" -ForegroundColor Red
            $script:failedCases++
            $diff = Compare-Object -ReferenceObject ($expected -split "`n") -DifferenceObject ($actual -split "`n")
            foreach ($line in $diff) {
                $marker = if ($line.SideIndicator -eq "<=") { "expected:" } else { "actual:  " }
                Write-Host "    $marker $($line.InputObject)"
            }
        }
    }

    if (Test-Path $actualRoot) { Remove-Item -Recurse -Force $actualRoot }
}

Write-Host ""
if ($UpdateSnapshots) {
    Write-Host "==> Snapshots updated ($totalCases case(s) across $((Get-ChildItem $fixturesRoot -Directory).Count - $skippedFixtures) fixture(s))." -ForegroundColor Yellow
    exit 0
}

$passedCases = $totalCases - $failedCases
Write-Host "==> $passedCases/$totalCases case(s) passed$(if ($skippedFixtures -gt 0) { " ($skippedFixtures fixture(s) skipped: no cases.json)" })"
if ($failedCases -gt 0) {
    Write-Host "==> $failedCases case(s) FAILED" -ForegroundColor Red
    exit 1
}
exit 0
