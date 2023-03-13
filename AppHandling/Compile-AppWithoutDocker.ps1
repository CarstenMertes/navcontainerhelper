﻿<# 
 .Synopsis
  Compile app without docker (used by Run-AlPipeline to compile apps without docker)
 .Description
 .Parameter containerName
  Name of the directory (under [hosthelpderfolder]\extensions) in which compiler and dlls can be found
 .Parameter appProjectFolder
  Location of the project. This folder (or any of its parents) needs to be shared with the container.
 .Parameter appOutputFolder
  Folder in which the output will be placed. This folder (or any of its parents) needs to be shared with the container. Default is $appProjectFolder\output.
 .Parameter appSymbolsFolder
  Folder in which the symbols of dependent apps will be placed. This folder (or any of its parents) needs to be shared with the container. Default is $appProjectFolder\symbols.
 .Parameter appName
  File name of the app. Default is to compose the file name from publisher_appname_version from app.json.
 .Parameter UpdateDependencies
  Update the dependency version numbers to the actual version number used during compilation
 .Parameter CopyAppToSymbolsFolder
  Add this switch to copy the compiled app to the appSymbolsFolder.
 .Parameter GenerateReportLayout
  Add this switch to invoke report layout generation during compile. Default is default alc.exe behavior, which is to generate report layout
 .Parameter AzureDevOps
  Add this switch to convert the output to Azure DevOps Build Pipeline compatible output
 .Parameter gitHubActions
  Include this switch to convert the output to GitHub Actions compatible output
 .Parameter EnableCodeCop
  Add this switch to Enable CodeCop to run
 .Parameter EnableAppSourceCop
  Add this switch to Enable AppSourceCop to run
 .Parameter EnablePerTenantExtensionCop
  Add this switch to Enable PerTenantExtensionCop to run
 .Parameter EnableUICop
  Add this switch to Enable UICop to run
 .Parameter RulesetFile
  Specify a ruleset file for the compiler
 .Parameter CustomCodeCops
  Add custom AL code Cops when compiling apps.
 .Parameter Failon
  Specify if you want Compilation to fail on Error or Warning
 .Parameter nowarn
  Specify a nowarn parameter for the compiler
 .Parameter preProcessorSymbols
  PreProcessorSymbols to set when compiling the app.
 .Parameter generatecrossreferences
  Include this flag to generate cross references when compiling
 .Parameter reportSuppressedDiagnostics
  Set reportSuppressedDiagnostics flag on ALC when compiling to ignore pragma warning disables
 .Parameter assemblyProbingPaths
  Specify a comma separated list of paths to include in the search for dotnet assemblies for the compiler
 .Parameter OutputTo
  Compiler output is sent to this scriptblock for output. Default value for the scriptblock is: { Param($line) Write-Host $line }
 .Example
  Compile-AppWithoutDocker -containerName test -credential $credential -appProjectFolder "C:\Users\freddyk\Documents\AL\Project1\Test"
 .Example
  Compile-AppWithoutDocker -containerName test -appProjectFolder "C:\Users\freddyk\Documents\AL\Test"
 .Example
  Compile-AppWithoutDocker -containerName test -appProjectFolder "C:\Users\freddyk\Documents\AL\Test" -outputTo { Param($line) if ($line -notlike "*sourcepath=C:\Users\freddyk\Documents\AL\Test\Org\*") { Write-Host $line } }
#>
function Compile-AppWithoutDocker {
    Param (
        [string] $containerName = $bcContainerHelperConfig.defaultContainerName,
        [Parameter(Mandatory=$true)]
        [string] $appProjectFolder,
        [Parameter(Mandatory=$false)]
        [string] $appOutputFolder = (Join-Path $appProjectFolder "output"),
        [Parameter(Mandatory=$false)]
        [string] $appSymbolsFolder = (Join-Path $appProjectFolder ".alpackages"),
        [Parameter(Mandatory=$false)]
        [string] $appName = "",
        [switch] $UpdateDependencies,
        [switch] $CopyAppToSymbolsFolder,
        [ValidateSet('Yes','No','NotSpecified')]
        [string] $GenerateReportLayout = 'NotSpecified',
        [switch] $AzureDevOps,
        [switch] $gitHubActions,
        [switch] $EnableCodeCop,
        [switch] $EnableAppSourceCop,
        [switch] $EnablePerTenantExtensionCop,
        [switch] $EnableUICop,
        [ValidateSet('none','error','warning')]
        [string] $FailOn = 'none',
        [Parameter(Mandatory=$false)]
        [string] $rulesetFile,
        [string[]] $CustomCodeCops = @(),
        [Parameter(Mandatory=$false)]
        [string] $nowarn,
        [string[]] $preProcessorSymbols = @(),
        [switch] $GenerateCrossReferences,
        [switch] $ReportSuppressedDiagnostics,
        [Parameter(Mandatory=$false)]
        [string] $assemblyProbingPaths,
        [Parameter(Mandatory=$false)]
        [ValidateSet('ExcludeGeneratedTranslations','GenerateCaptions','GenerateLockedTranslations','NoImplicitWith','TranslationFile','LcgTranslationFile')]
        [string[]] $features = @(),
        [string[]] $treatWarningsAsErrors = $bcContainerHelperConfig.TreatWarningsAsErrors,
        [scriptblock] $outputTo = { Param($line) Write-Host $line }
    )

$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @()
try {

    $startTime = [DateTime]::Now

    $containerFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\$containerName"
    if (!(Test-Path $containerFolder)) {
        throw "Build container doesn't exist"
    }

    $vsixPath = Join-Path $containerFolder 'compiler'
    $dllsPath = Join-Path $containerFolder 'dlls'
    $binPath = Join-Path $vsixPath 'extension/bin'
    if ($isLinux) {
        $alcPath = Join-Path $binPath 'linux'
        $alcExe = 'alc'
    }
    else {
        $alcPath = Join-Path $binPath 'win32'
        $alcExe = 'alc.exe'
    }
    if (-not (Test-Path $alcPath)) {
        $alcPath = $binPath
    }
    $alcDllPath = $alcPath
    if (!$isLinux -and !$isPsCore) {
        $alcDllPath = $binPath
    }

    $appJsonFile = Join-Path $appProjectFolder 'app.json'
    $appJsonObject = [System.IO.File]::ReadAllLines($appJsonFile) | ConvertFrom-Json
    if ("$appName" -eq "") {
        $appName = "$($appJsonObject.Publisher)_$($appJsonObject.Name)_$($appJsonObject.Version).app".Split([System.IO.Path]::GetInvalidFileNameChars()) -join ''
    }
    if ([bool]($appJsonObject.PSobject.Properties.name -eq "id")) {
        AddTelemetryProperty -telemetryScope $telemetryScope -key "id" -value $appJsonObject.id
    }
    elseif ([bool]($appJsonObject.PSobject.Properties.name -eq "appid")) {
        AddTelemetryProperty -telemetryScope $telemetryScope -key "id" -value $appJsonObject.appid
    }
    AddTelemetryProperty -telemetryScope $telemetryScope -key "publisher" -value $appJsonObject.Publisher
    AddTelemetryProperty -telemetryScope $telemetryScope -key "name" -value $appJsonObject.Name
    AddTelemetryProperty -telemetryScope $telemetryScope -key "version" -value $appJsonObject.Version
    AddTelemetryProperty -telemetryScope $telemetryScope -key "appname" -value $appName
    
    if (!(Test-Path $appOutputFolder -PathType Container)) {
        New-Item $appOutputFolder -ItemType Directory | Out-Null
    }

    Write-Host "Using Symbols Folder: $appSymbolsFolder"
    if (!(Test-Path -Path $appSymbolsFolder -PathType Container)) {
        New-Item -Path $appSymbolsFolder -ItemType Directory | Out-Null
    }

    $GenerateReportLayoutParam = ""
    if (($GenerateReportLayout -ne "NotSpecified") -and ($platformversion.Major -ge 14)) {
        if ($GenerateReportLayout -eq "Yes") {
            $GenerateReportLayoutParam = "/GenerateReportLayout+"
        }
        else {
            $GenerateReportLayoutParam = "/GenerateReportLayout-"
        }
    }

    $dependencies = @()

    if (([bool]($appJsonObject.PSobject.Properties.name -eq "application")) -and $appJsonObject.application)
    {
        AddTelemetryProperty -telemetryScope $telemetryScope -key "application" -value $appJsonObject.application
        $dependencies += @{"publisher" = "Microsoft"; "name" = "Application"; "appId" = ''; "version" = $appJsonObject.application }
    }

    if (([bool]($appJsonObject.PSobject.Properties.name -eq "platform")) -and $appJsonObject.platform)
    {
        AddTelemetryProperty -telemetryScope $telemetryScope -key "platform" -value $appJsonObject.platform
        $dependencies += @{"publisher" = "Microsoft"; "name" = "System"; "appId" = ''; "version" = $appJsonObject.platform }
    }

    if (([bool]($appJsonObject.PSobject.Properties.name -eq "dependencies")) -and $appJsonObject.dependencies)
    {
        $appJsonObject.dependencies | ForEach-Object {
            $dep = $_
            try { $appId = $dep.id } catch { $appId = $dep.appId }
            $dependencies += @{ "publisher" = $dep.publisher; "name" = $dep.name; "appId" = $appId; "version" = $dep.version }
        }
    }

    $existingAppFiles = @(Get-ChildItem -Path (Join-Path $appSymbolsFolder '*.app'))
    Write-Host "Enumerating Existing Apps"
    $existingApps = GetAppInfo -AppFiles $existingAppFiles -alcDllPath $alcDllPath -cacheAppInfo

    $depidx = 0
    while ($depidx -lt $dependencies.Count) {
        $dependency = $dependencies[$depidx]
        Write-Host "Processing dependency $($dependency.Publisher)_$($dependency.Name)_$($dependency.Version) ($($dependency.AppId))"
        $existingApp = $existingApps | Where-Object {
            ($_.AppId -eq $dependency.appId -and ([System.Version]$_.Version -ge [System.Version]$dependency.version))
        }
        if ($existingApp) {
            Write-Host "Dependency App exists"
        }
        $depidx++
    }

    $systemSymbolsApp = @($existingApps | Where-Object { $_.Name -eq "System" })
    if ($systemSymbolApp.Count -ne 1) {
        throw "Unable to locate system symbols"
    }
    $platformversion = $systemSymbolsApp.Version
    Write-Host "Platform version: $platformversion"
 
    if ($updateDependencies) {
        $appJsonFile = Join-Path $appProjectFolder 'app.json'
        $appJsonObject = [System.IO.File]::ReadAllLines($appJsonFile) | ConvertFrom-Json
        $changes = $false
        Write-Host "Modifying Dependencies"
        if (([bool]($appJsonObject.PSobject.Properties.name -eq "dependencies")) -and $appJsonObject.dependencies) {
            $appJsonObject.dependencies = @($appJsonObject.dependencies | ForEach-Object {
                $dependency = $_
                $dependencyAppId = "$(if ($dependency.PSObject.Properties.name -eq 'AppId') { $dependency.AppId } else { $dependency.Id })"
                Write-Host "Dependency: Id=$dependencyAppId, Publisher=$($dependency.Publisher), Name=$($dependency.Name), Version=$($dependency.Version)"
                $existingApps | Where-Object { $_.AppId -eq [System.Guid]$dependencyAppId -and $_.Version -gt [System.Version]$dependency.Version } | ForEach-Object {
                    $dependency.Version = "$($_.Version)"
                    Write-Host "- Set dependency version to $($_.Version)"
                    $changes = $true
                }
                $dependency
            })
        }
        if (([bool]($appJsonObject.PSobject.Properties.name -eq "application")) -and $appJsonObject.application) {
            Write-Host "Application Dependency $($appJsonObject.application)"
            $existingApps | Where-Object { $_.Name -eq "Application" -and $_.Version -gt [System.Version]$appJsonObject.application } | ForEach-Object {
                $appJsonObject.Application = "$($_.Version)"
                Write-Host "- Set Application dependency to $($_.Version)"
                $changes = $true
            }
        }
        if (([bool]($appJsonObject.PSobject.Properties.name -eq "platform")) -and $appJsonObject.platform) {
            Write-Host "Platform Dependency $($appJsonObject.platform)"
            $existingApps | Where-Object { $_.Name -eq "System" -and $_.Version -gt [System.Version]$appJsonObject.platform } | ForEach-Object {
                $appJsonObject.platform = "$($_.Version)"
                Write-Host "- Set Platform dependency to $($_.Version)"
                $changes = $true
            }
        }
        if ($changes) {
            Write-Host "Updating app.json"
            $appJsonObject | ConvertTo-Json -depth 99 | Set-Content $appJsonFile -encoding UTF8
        }
    }

    $probingPaths = @()
    if ($assemblyProbingPaths) {
        $probingPaths += @($assemblyProbingPaths)
    }
    $netpackagesPath = Join-Path $appProjectFolder ".netpackages"
    if (Test-Path $netpackagesPath) {
        $probingPaths += @($netpackagesPath)
    }
    if (Test-Path $dllsPath) {
        $probingPaths += @($dllsPath)
    }
    if ($platformversion.Major -ge 22) {
        $probingPaths += @('C:\Program Files\dotnet\shared')
    }
    else {
        $probingPaths += @('c:\Windows\Microsoft.NET\Assembly')
    }
    $assemblyProbingPaths = $probingPaths -join ','

    $appOutputFile = Join-Path $appOutputFolder $appName
    if (Test-Path -Path $appOutputFile -PathType Leaf) {
        Remove-Item -Path $appOutputFile -Force
    }

    Write-Host "Compiling..."

    $alcItem = Get-Item -Path (Join-Path $alcPath 'alc.exe')
    [System.Version]$alcVersion = $alcItem.VersionInfo.FileVersion

    $alcParameters = @("/project:""$($appProjectFolder.TrimEnd('/\'))""", "/packagecachepath:""$($appSymbolsFolder.TrimEnd('/\'))""", "/out:""$appOutputFile""")
    if ($GenerateReportLayoutParam) {
        $alcParameters += @($GenerateReportLayoutParam)
    }
    if ($EnableCodeCop) {
        $alcParameters += @("/analyzer:$(Join-Path $binPath 'Analyzers\Microsoft.Dynamics.Nav.CodeCop.dll')")
    }
    if ($EnableAppSourceCop) {
        $alcParameters += @("/analyzer:$(Join-Path $binPath 'Analyzers\Microsoft.Dynamics.Nav.AppSourceCop.dll')")
    }
    if ($EnablePerTenantExtensionCop) {
        $alcParameters += @("/analyzer:$(Join-Path $binPath 'Analyzers\Microsoft.Dynamics.Nav.PerTenantExtensionCop.dll')")
    }
    if ($EnableUICop) {
        $alcParameters += @("/analyzer:$(Join-Path $binPath 'Analyzers\Microsoft.Dynamics.Nav.UICop.dll')")
    }

    if ($CustomCodeCops.Count -gt 0) {
        $CustomCodeCops | ForEach-Object { $alcParameters += @("/analyzer:$_") }
    }

    if ($rulesetFile) {
        $alcParameters += @("/ruleset:$rulesetfile")
    }

    if ($nowarn) {
        $alcParameters += @("/nowarn:$nowarn")
    }

    if ($GenerateCrossReferences -and $platformversion.Major -ge 18) {
        $alcParameters += @("/generatecrossreferences")
    }

    if ($ReportSuppressedDiagnostics) {
        if ($alcVersion -ge [System.Version]"9.1.0.0") {
            $alcParameters += @("/reportsuppresseddiagnostics")
        }
        else {
            Write-Host -ForegroundColor Yellow "ReportSuppressedDiagnostics was specified, but the version of the AL Language Extension does not support this. Get-LatestAlLanguageExtensionUrl returns a location for the latest AL Language Extension"
        }
    }

    if ($assemblyProbingPaths) {
        $alcParameters += @("/assemblyprobingpaths:$assemblyProbingPaths")
    }

    if ($features) {
        $alcParameters +=@("/features:$($features -join ',')")
    }

    $preprocessorSymbols | where-Object { $_ } | ForEach-Object { $alcParameters += @("/D:$_") }

    Push-Location -Path $alcPath
    try {
        Write-Host ".\$alcExe $([string]::Join(' ', $alcParameters))"
        $result = & ".\$alcExe" $alcParameters | Out-String
    }
    finally {
        Pop-Location
    }
        
    if ($lastexitcode -ne 0 -and $lastexitcode -ne -1073740791) {
        "App generation failed with exit code $lastexitcode"
    }
    
    if ($treatWarningsAsErrors) {
        $regexp = ($treatWarningsAsErrors | ForEach-Object { if ($_ -eq '*') { ".*" } else { $_ } }) -join '|'
        $result = $result | ForEach-Object { $_ -replace "^(.*)warning ($regexp):(.*)`$", '$1error $2:$3' }
    }

    $devOpsResult = ""
    if ($result) {
        if ($gitHubActions) {
            $devOpsResult = Convert-ALCOutputToAzureDevOps -FailOn $FailOn -AlcOutput $result -DoNotWriteToHost -gitHubActions -basePath $ENV:GITHUB_WORKSPACE
        }
        else {
            $devOpsResult = Convert-ALCOutputToAzureDevOps -FailOn $FailOn -AlcOutput $result -DoNotWriteToHost
        }
    }
    if ($AzureDevOps -or $gitHubActions) {
        $devOpsResult | ForEach-Object { $outputTo.Invoke($_) }
    }
    else {
        $result | ForEach-Object { $outputTo.Invoke($_) }
        if ($devOpsResult -like "*task.complete result=Failed*") {
            throw "App generation failed"
        }
    }

    $result | Where-Object { $_ -like "App generation failed*" } | ForEach-Object { throw $_ }

    $timespend = [Math]::Round([DateTime]::Now.Subtract($startTime).Totalseconds)
    $appFile = Join-Path $appOutputFolder $appName

    if (Test-Path -Path $appFile) {
        Write-Host "$appFile successfully created in $timespend seconds"
        if ($CopyAppToSymbolsFolder) {
            Copy-Item -Path $appFile -Destination $appSymbolsFolder -ErrorAction SilentlyContinue
        }
    }
    else {
        throw "App generation failed"
    }
    $appFile
}
catch {
    TrackException -telemetryScope $telemetryScope -errorRecord $_
    throw
}
finally {
    TrackTrace -telemetryScope $telemetryScope
}
}
Export-ModuleMember -Function Compile-AppWithoutDocker
