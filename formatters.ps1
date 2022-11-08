function Format-Controller {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [string] $FileName,
        [Parameter(Mandatory)]
        [string] $Namespace,
        [string] $ControllerNamespace,
        [switch] $RenameController,
        [switch] $NoValidateModel
    )

    process {
        if (!$ControllerNamespace) {
            $parts = $Namespace -split '\.'
            $controllerNamespace = (($parts)[0..($parts.Length-1)] -join '.') + '.Controllers'
        }

        Write-Verbose "Formatting $FileName"

        # format the generated a bit for System.Text.Json, warning fixes, etc.
        $c = Get-Content $FileName -raw
        if ($RenameController -and ($FileName -match "(\w+)Api\.cs$")) {
            $c = $c -replace "$($matches[1])Api", $matches[1]
        }
        if ($NoValidateModel) {
            $c = $c -replace "\s+\[ValidateModelState\]", ""
            $c = $c -replace "using IO\.Swagger\.Attributes;\s*`n", ""
        }
        Set-Content ((((((
                            $c.Replace("using $Namespace;", "using $Namespace;`nusing System.Threading.Tasks;")) `
                            -replace ' exampleJson = null;\s+', ' ') `
                            -replace 'virtual IActionResult ', 'virtual async Task<IActionResult> ' ) `
                            -replace 'using IO\.Swagger.Security;\s*', '') `
                            -replace 'IO\.Swagger\.Controllers', $controllerNamespace ) `
                            -replace 'return new ObjectResult\(example\);', 'return await Task.FromResult(new ObjectResult(example)).ConfigureAwait(false);') `
                -Path $FileName -Encoding ascii -NoNewline
    }
}

function Format-Model {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [string] $FileName,
        [Parameter(Mandatory)]
        [string] $Namespace,
        [switch] $RemoveEnumSuffix,
        [switch] $NoNullGuid,
        [switch] $NoToString
    )

    process {
        function Repair-Null {
            param (
                [string] $Code
            )
            while ($Code -match "(\[Required\]\s+\[DataMember.*\]\s+public\s+\w+\?\s+(?<name>\w+))") {
                Write-Verbose "    $($matches['name'])"
                $count += 1
                $Code = (($Code -replace "\?\s+$($matches['name'])", " $($matches['name'])") `
                        -replace " $($matches['name']) != null[\s&]+", '') `
                    -replace "if \($($matches['name']) != null\)", ''

                if ($count -gt 20) {
                    Write-Error "Infinite loop?"
                    break
                }
            }
            $Code
        }

        Write-Verbose "Formatting $FileName"

        $content = ""
        $skipping = $false
        if ($NoToString) {
            $lines = Get-Content $FileName -ReadCount 0
            foreach ($l in $lines) {
                if ($l -like '*Returns the string presentation of the object*') {
                    $skipping = $true
                } elseif ($skipping -and $l -like '*<summary>*') {
                    $skipping = $false
                } elseif (!$skipping) {
                    $content += "$l`n"
                }
            }
        } else {
            $content = Get-Content $FileName -Raw
        }

        if ($RemoveEnumSuffix) {
            $content = $content -replace '(\[EnumMember\(Value = "\w+"\)\]\s+\w+)Enum( = \d+)', '$1$2'
        }

        $content = $content -replace '( +)\[DataMember\(Name="(.*)"\)\]', ('$1[DataMember(Name="$2")]'+"`n"+'$1[JsonPropertyName("$2")]')

        if ($NoNullGuid) {
            $content = ($content `
                            -replace "public Guid? (\w*Id)", "public Guid `$1") `
                            -replace "if \(\w*Id != null\)", ""
        }
        #  try remove trailing works in almost all cases $content = $content -replace "[\t ]+`n","`n"

        Set-Content (
            "#pragma warning disable CA1834 // Consider using 'StringBuilder.Append(char)' when applicable`n" +
            "#pragma warning disable CA1307 // Specify StringComparison`n" +
            "// ReSharper disable RedundantUsingDirective`n" +
            "// ReSharper disable CheckNamespace`n" +
             ($(Repair-Null $content).Replace(`
                    'using Newtonsoft.Json;',
                    "using System.Text.Json;`nusing System.Text.Json.Serialization;").Replace( `
                    'return JsonConvert.SerializeObject(this, Formatting.Indented);', `
                    'return JsonSerializer.Serialize(this, new JsonSerializerOptions() { WriteIndented = true });').Replace(`
                    'namespace IO.Swagger.Models',
                    "namespace $Namespace").Replace(`
                    '[JsonConverter(typeof(Newtonsoft.Json.Converters.StringEnumConverter))]',
                ''
            ) -replace "^/\*", "#nullable disable`n/*") +
            "`n#pragma warning restore CA1834 // Consider using 'StringBuilder.Append(char)' when applicable`n" +
            "#pragma warning disable CA1307 // Specify StringComparison`n" )`
            -Path $FileName -Encoding ascii -NoNewline
    }
}