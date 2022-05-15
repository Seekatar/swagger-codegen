<#
.SYNOPSIS
Run swagger-gen on an OAS file

.DESCRIPTION
Calls the swagger gen jar and formats the model and controller for newer .NET features.

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

.PARAMETER Force
Don't ask to wipe output folder

.PARAMETER JarVersion
Download and run a different Jar than the 3.0.34 version

.EXAMPLE
./Invoke-SwaggerGen.ps1 -OASFile ./oas.yaml -OutputFolder /temp/swagger-gen

.EXAMPLE
./Invoke-SwaggerGen.ps1 -OASFile ./oas.yaml -namespace MyNamespace -OutputFolder /temp/swagger-gen

.NOTES
Java must be in the path
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
    [string] $JarVersion = "3.0.34",
    [switch] $Force
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

    $jarPath = "swagger-codegen-cli-${JarVersion}.jar"
    Write-Verbose "Checking $jarPath"

    if (!(Test-Path $jarPath)) {
        if ((Read-Host -Prompt "The swagger-gen jar file does not exist. Do you want to download it now (Y/n)?").StartsWith('n')) {
            Write-Warning "You must download the jar file and put it in $PSScriptRoot"
            return
        } else {
            Invoke-WebRequest "https://repo1.maven.org/maven2/io/swagger/codegen/v3/swagger-codegen-cli/$JarVersion/swagger-codegen-cli-$JarVersion.jar" -OutFile $jarPath
        }
    }

    # these change filenames and usage of model in controller, but not model themselves
    # --model-name-prefix="pre" --model-name-suffix="suff"
    Remove-Item $OutputFolder/*.* -Force -Recurse

    # added --add-opens to fix isEmpty accessible error as described here
    # https://github.com/swagger-api/swagger-codegen/issues/10966

    java --add-opens=java.base/java.util=ALL-UNNAMED -jar $jarPath generate -i $OASFile -o $OutputFolder -l aspnetcore --api-package="shoot.test.cond" --model-package=$Namespace

    if ($LASTEXITCODE -eq 0) {
        Get-ChildItem (Join-Path $OutputFolder "src/IO.Swagger/Models/*Inner.cs") | ForEach-Object {
            Write-Warning "Found inner class $_. You may rework the model the OAS file to avoid that."
        }

        Get-ChildItem (Join-Path $OutputFolder "src/IO.Swagger/Models" ) |
                Select-Object -ExpandProperty fullname |
                Format-Model -Namespace $Namespace -NoNullGuid:$NoNullGuid -RemoveEnumSuffix:$RemoveEnumSuffix -NoToString:$NoToString

        Get-ChildItem (Join-Path $OutputFolder "src/IO.Swagger/Controllers" ) |
                Select-Object -ExpandProperty fullname |
                Format-Controller -Namespace $Namespace -ControllerNamespace $ControllerNamespace

        if ($RenameController) {
            Get-ChildItem (Join-Path $OutputFolder "src/IO.Swagger/Controllers" ) |
                    ForEach-Object { Rename-Item $_ ($_.Name -replace 'Api', 'Controller') }
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