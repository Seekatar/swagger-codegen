<#
.SYNOPSIS
Run swagger-gen or OpenAPI generator on an OAS file

.DESCRIPTION
Calls the generator's jar and formats the model and controller for newer .NET features.

.PARAMETER OASFile
OASFile file

.PARAMETER OutputFolder
Folder where to write the output. Will be created if doesn't exist and will prompt for cleaning out

.PARAMETER Namespace
Model namespace

.PARAMETER ControllerNamespace
Controller namespace, if not supplied uses up to first two levels of Namespace+.Controllers

.PARAMETER NoNullGuid
Don't make Guid's nullable

.PARAMETER RenameController
Change generated controller name to use Controller instead of Api

.PARAMETER RemoveEnumSuffix
Remove model's 'Enum' suffixes

.PARAMETER NoToString
Remove model ToString() methods since makes some debuggers show ugly output

.PARAMETER NoValidateModel
Do not include the [ValidateModel] attribute on the controller's methods

.PARAMETER Force
Don't ask to wipe output folder

.PARAMETER JarVersion
Download and run a different Jar than default. 3.0.34 for SwaggerGen, 7.0.0 for OpenApi

.PARAMETER SkipPostProcessing
Skip post processing of the controller and model files

.PARAMETER SkipConfig
For OpenApi, skip using the aspnetcore-config.json file

.PARAMETER Generator
The generator to use, swaggergen or openapi (default swaggergen)

.EXAMPLE
./Invoke-SwaggerGen.ps1 -OASFile ./oas.yaml -OutputFolder /temp/swagger-gen

.EXAMPLE
./Invoke-SwaggerGen.ps1 -OASFile ./oas.yaml -namespace MyNamespace -OutputFolder /temp/swagger-gen

.NOTES
Java must be in the path

.LINK
https://github.com/OpenAPITools/openapi-generator/tree/v7.0.0?tab=readme-ov-file

.LINK
https://github.com/swagger-api/swagger-codegen
#>
[CmdletBinding()]
param(
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [Parameter(Mandatory)]
    [string] $OASFile,
    [Parameter(Mandatory)]
    [string] $Namespace,
    [string] $OutputFolder = "C:/temp/swagger-gen",
    [string] $ControllerNamespace,
    [switch] $NoNullGuid,
    [switch] $RenameController,
    [switch] $RemoveEnumSuffix,
    [switch] $NoToString,
    [switch] $NoValidateModel,
    [string] $JarVersion,
    [switch] $Force,
    [switch] $SkipPostProcessing,
    [switch] $SkipConfig,
    [ValidateSet("swaggergen","openapi")]
    [string] $Generator = "swaggergen"
)

Set-StrictMode -Version Latest
$PrevErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Warning "Only testing on PowerShell v7".
    return
}

$OASFile = Convert-Path $OASFile
Push-Location $PSScriptRoot
. ./formatters.ps1

"Generating $Generator from $OASFile to $OutputFolder"

try {

    if (!(Get-Command java -ErrorAction Ignore)) {
        throw "Java not installed or in path"
    }


    if (!(Test-Path $OutputFolder)) {
        $null = New-Item $OutputFolder -ItemType Directory
        Write-Warning "Created $OutputFolder"
    } else {
        if ($Force -or (Read-Host -Prompt "Output folder '$OutputFolder' exists, do you want to wipe all files first (y/N)?").StartsWith('y')) {
            Get-ChildItem $OutputFolder/*.* -Recurse | Remove-Item -Force -Recurse
        }
    }

    $params = @()
    if ($Generator -eq "swaggergen") {
        if (!$JarVersion) { $JarVersion = "3.0.34" }
        $jarPath = "swagger-codegen-cli-${JarVersion}.jar"
        $srcFolder = "IO.Swagger"
        $params += "-l", "aspnetcore"
        $url = "https://repo1.maven.org/maven2/io/swagger/codegen/v3/swagger-codegen-cli/$JarVersion/openapi-generator-cli-$JarVersion.jar"
    } else {
        if (!$JarVersion) { $JarVersion = "7.0.0" }
        $jarPath = "openapi-generator-cli-${JarVersion}.jar"
        $srcFolder = "Org.OpenAPITools"
        $params += "-g", "aspnetcore"
        $url = "https://repo1.maven.org/maven2/org/openapitools/openapi-generator-cli/$JarVersion/openapi-generator-cli-$JarVersion.jar"
    }
    Write-Verbose "JarPath: $jarPath"
    Write-Verbose "Url: $url"
    Write-Verbose "Params: $($params -join ', ')"

    if (!(Test-Path $jarPath)) {
        if ((Read-Host -Prompt "The jar file for $Generator does not exist. Do you want to download it now (Y/n)?").StartsWith('n')) {
            Write-Warning "You must download the jar file and put it in $PSScriptRoot"
            return
        } else {
            Invoke-WebRequest $url -OutFile $jarPath
        }
    }

    # these change filenames and usage of model in controller, but not model themselves
    # --model-name-prefix="pre" --model-name-suffix="suff"
    Remove-Item $OutputFolder/*.* -Force -Recurse

    if ($Generator -eq "openapi" -and !$SkipConfig) {
        @"
{
    "aspnetCoreVersion": "6.0",
    "operationIsAsync" : true,
    "nullableReferenceTypes" : true,
    "useNewtonsoft": false,
    "pocoModels": true,
    "swashbuckleVersion": "6.4.0"
}
"@ | Out-File (Join-Path $PSScriptRoot "aspnetcore-config.json")
        $params += "-c", "./aspnetcore-config.json"
    }
    Write-Verbose "Params: $($params -join ', ')"
    if (!$ControllerNamespace) {
        $ControllerNamespace = $Namespace+".Controllers"
    }

    # added --add-opens to fix isEmpty accessible error as described here
    # https://github.com/swagger-api/swagger-codegen/issues/10966
    java --add-opens=java.base/java.util=ALL-UNNAMED -jar $jarPath generate -i $OASFile -o $OutputFolder `
            --api-package=$ControllerNamespace `
            --model-package=$Namespace `
            @params | Select-String -NotMatch "( INFO |^#)"

    if ($Generator -eq "openapi" -and !$SkipConfig) {
        Remove-Item (Join-Path $PSScriptRoot "aspnetcore-config.json") -Force -ErrorAction Ignore
    }

    if ($LASTEXITCODE -eq 0) {
        if (!$SkipPostProcessing) {
            Get-ChildItem (Join-Path $OutputFolder "src/$srcFolder/Models/*Inner.cs") | ForEach-Object {
                Write-Warning "Found inner class $_. You may rework the model the OAS file to avoid that."
            }

            Get-ChildItem (Join-Path $OutputFolder "src/$srcFolder/Models" ) |
                    Select-Object -ExpandProperty fullname |
                    Format-Model -Namespace $Namespace -NoNullGuid:$NoNullGuid -RemoveEnumSuffix:$RemoveEnumSuffix -NoToString:$NoToString -Generator $Generator

            Get-ChildItem (Join-Path $OutputFolder "src/$srcFolder/Controllers" ) |
                    Select-Object -ExpandProperty fullname |
                    Format-Controller -Namespace $Namespace -ControllerNamespace $ControllerNamespace -RenameController:$RenameController -NoValidateModel:$NoValidateModel

            if ($RenameController) {
                Get-ChildItem (Join-Path $OutputFolder "src/$srcFolder/Controllers" ) |
                        ForEach-Object { Rename-Item $_ ($_.Name -replace 'Api', 'Controller') }
                }
        }
    } else {
        Write-Warning "LastExitCode is $LASTEXITCODE"
    }

    Write-Information "`nSwagger-gen output was written to $OutputFolder" -InformationAction Continue
    Write-Information "Compare files from there with your source code." -InformationAction Continue

} catch {
    Write-Error "Error! $_`n$($_.ScriptStackTrace)"
    throw $_
} finally {
    Pop-Location
    $ErrorActionPreference = $PrevErrorActionPreference
}