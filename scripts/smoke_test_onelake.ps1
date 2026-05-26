#requires -Version 5.1
# ============================================================================
# OneLake smoke test - Fabric-RegionalDataPortal-Prod
# ============================================================================
# Validates the credential chain BEFORE we invest in the Power Automate flow:
#   - Token acquisition from Entra (client_credentials grant)
#   - SP has workspace Contributor on Regional_Data_Portal
#   - OneLake ADLS Gen2 REST API accepts the token + path
#   - File create / append / flush / read / delete all succeed
#
# Secret is prompted at runtime via Read-Host -AsSecureString. Never written
# to disk, never echoed, plaintext held only between the token POST and the
# explicit $null assignment that follows it.
# ============================================================================

$ErrorActionPreference = 'Stop'

$TenantId  = '0320ef6f-7349-4acf-b62a-e780da155b7e'
$ClientId  = '7433888d-1d8b-4ae2-acbf-17d3c45dd23e'
$Workspace = 'Regional_Data_Portal'
$Lakehouse = 'Assessment_Landing'
$TestPath  = 'Files/imports/_smoke-test/hello.txt'

$BaseUrl = "https://onelake.dfs.fabric.microsoft.com/$Workspace/$Lakehouse.Lakehouse/$TestPath"

$SecureSecret = Read-Host -AsSecureString "Client secret for Fabric-RegionalDataPortal-Prod"
$Bstr         = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureSecret)
$ClientSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($Bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Bstr)

try {
    Write-Host "[1/6] Acquiring token..." -NoNewline
    $TokenResponse = Invoke-RestMethod `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -Method POST `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body @{
            grant_type    = 'client_credentials'
            client_id     = $ClientId
            client_secret = $ClientSecret
            scope         = 'https://storage.azure.com/.default'
        }
    $ClientSecret = $null
    $Headers = @{ Authorization = "Bearer $($TokenResponse.access_token)" }
    Write-Host " OK (expires in $($TokenResponse.expires_in)s)" -ForegroundColor Green

    $TestContent  = "OneLake smoke test - $(Get-Date -Format o)"
    $ContentBytes = [System.Text.Encoding]::UTF8.GetBytes($TestContent)

    Write-Host "[2/6] PUT create empty file..." -NoNewline
    Invoke-RestMethod -Uri "${BaseUrl}?resource=file" -Method PUT -Headers $Headers | Out-Null
    Write-Host " OK" -ForegroundColor Green

    Write-Host "[3/6] PATCH append $($ContentBytes.Length) bytes..." -NoNewline
    Invoke-RestMethod -Uri "${BaseUrl}?action=append&position=0" `
        -Method PATCH -Headers $Headers `
        -Body $ContentBytes -ContentType 'application/octet-stream' | Out-Null
    Write-Host " OK" -ForegroundColor Green

    Write-Host "[4/6] PATCH flush..." -NoNewline
    Invoke-RestMethod -Uri "${BaseUrl}?action=flush&position=$($ContentBytes.Length)" `
        -Method PATCH -Headers $Headers | Out-Null
    Write-Host " OK" -ForegroundColor Green

    Write-Host "[5/6] GET verify content..." -NoNewline
    $ReadBack = Invoke-RestMethod -Uri $BaseUrl -Method GET -Headers $Headers
    if ($ReadBack -ne $TestContent) {
        throw "Content mismatch. Expected '$TestContent', got '$ReadBack'"
    }
    Write-Host " OK ('$ReadBack')" -ForegroundColor Green

    Write-Host "[6/6] DELETE cleanup..." -NoNewline
    Invoke-RestMethod -Uri $BaseUrl -Method DELETE -Headers $Headers | Out-Null
    Write-Host " OK" -ForegroundColor Green

    Write-Host ""
    Write-Host "SMOKE TEST PASSED" -ForegroundColor Green
    Write-Host "Credential chain validated. Ready to build the Power Automate flow." -ForegroundColor Green
}
catch {
    Write-Host " FAIL" -ForegroundColor Red
    Write-Host ""
    Write-Host "SMOKE TEST FAILED" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red

    $errResp = $_.Exception.Response
    if ($errResp) {
        try {
            $code = $errResp.StatusCode.value__
            Write-Host "HTTP $code - $($errResp.StatusDescription)" -ForegroundColor Red
            $stream = $errResp.GetResponseStream()
            $stream.Position = 0
            $body = (New-Object System.IO.StreamReader($stream)).ReadToEnd()
            if ($body) { Write-Host "Response body: $body" -ForegroundColor Red }
        } catch { }
    }
    throw
}
