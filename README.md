# Helpers for Running the Swagger Code Gen Tool

This repo has PowerShell scripts for invoking the [swagger-codegen](https://github.com/swagger-api/swagger-codegen/tree/3.0.0) or [OpenAPI](https://github.com/OpenAPITools/openapi-generator) Java tool that takes an OAS file and creates C# code.

## Running It

The entry point is `Invoke-SwaggerGen.ps1`, which has many parameter to tweak the output. Use `help .\Invoke-SwaggerGen.ps1` for details. Here's a minimal run.

```PowerShell
.\Invoke-SwaggerGen.ps1 .\my-openapi.yaml -OutputFolder C:\code\generated\myapp\ -Namespace MyAppNamespace
```

This has been run on Windows, and Ubuntu (WSL2), and macOS.

## The Jar File

If the jar file doesn't exist the first time you run the script, it will prompt and download it. Currently it downloads 3.0.34 for swagger-gen and 7.0.0 for OpenAPI.

If you are interested, you can dump out the help for the Jar with these command (after it is downloaded)

```powershell
# swagger-gen
java -jar ./swagger-codegen-cli-3.0.34.jar generate --help
java -jar ./swagger-codegen-cli-3.0.34.jar config-help -l aspnetcore

# OpenAPI
java -jar ./openapi-generator-cli-7.0.0.jar help generate
java -jar ./openapi-generator-cli-7.0.0.jar config-help -g aspnetcore
```
