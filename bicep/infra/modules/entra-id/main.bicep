/**
 * @module entra-id
 * @description Creates an Entra ID (Azure AD) App Registration for JWT authentication.
 *              Uses a deployment script with Microsoft Graph REST API for full idempotency.
 *
 * Equivalent to the Terraform Entra-Id module in APIM-Unified-AI-Gateway-Sample:
 *   - App Registration with sign_in_audience = AzureADMyOrg
 *   - OAuth2 permission scope (access_as_user)
 *   - App role (Task.ReadWrite)
 *   - Service Principal
 *   - Client Secret (generated via Graph addPassword, stored in Key Vault)
 *
 * The deployment script handles create-or-update semantics so re-running
 * the deployment after a partial failure does not produce errors.
 *
 * Prerequisites:
 *   - Deploying user must have Application.ReadWrite.All permission
 */

// ------------------
//    PARAMETERS
// ------------------

@description('Prefix for resource naming (used in app registration display name)')
param namingPrefix string

@description('Name of the Key Vault to store the client secret')
param keyVaultName string

@description('Location for deployment script resources')
param location string = resourceGroup().location

// ------------------
//    RESOURCES
// ------------------

// Single idempotent deployment script that creates or updates the full Entra ID
// app registration, service principal, and client secret via Microsoft Graph REST API.
// This avoids the "uniqueName already exists" error that occurs when Microsoft.Graph
// Bicep resources are re-deployed after a partial failure.
resource entraAppScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: '${namingPrefix}-entra-app'
  location: location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '12.3'
    retentionInterval: 'PT1H'
    timeout: 'PT15M'
    arguments: '-AppDisplayName "${namingPrefix}-unified-ai-app" -KeyVaultName "${keyVaultName}"'
    scriptContent: '''
      param(
        [string]$AppDisplayName,
        [string]$KeyVaultName
      )

      $ErrorActionPreference = "Stop"
      $token = (Get-AzAccessToken -ResourceTypeName MSGraph).Token
      $headers = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }
      $graphBase = "https://graph.microsoft.com/v1.0"

      # ── 1. Create or get existing App Registration ──
      $existingApps = Invoke-RestMethod -Method GET `
        -Uri "$graphBase/applications?`$filter=displayName eq '$AppDisplayName'" `
        -Headers $headers

      if ($existingApps.value.Count -gt 0) {
        $app = $existingApps.value[0]
        Write-Output "Found existing app registration: $($app.appId)"
      } else {
        Write-Output "Creating new app registration..."
        $appBody = @{
          displayName     = $AppDisplayName
          signInAudience  = "AzureADMyOrg"
          api = @{
            requestedAccessTokenVersion = 2
            oauth2PermissionScopes = @(
              @{
                adminConsentDescription  = "Allow access to AI Hub Gateway API"
                adminConsentDisplayName  = "Access AI Hub Gateway API"
                isEnabled                = $true
                id                       = "00000000-0000-0000-0000-000000000001"
                type                     = "User"
                userConsentDescription   = "Allow access to AI Hub Gateway API"
                userConsentDisplayName   = "Access AI Hub Gateway API"
                value                    = "access_as_user"
              }
            )
          }
          appRoles = @(
            @{
              allowedMemberTypes = @("User", "Application")
              description        = "ReadWrite roles have read and write access to the application data"
              displayName        = "ReadWrite"
              isEnabled          = $true
              id                 = "00000000-0000-0000-0000-000000000002"
              value              = "Task.ReadWrite"
            }
          )
          requiredResourceAccess = @(
            @{
              resourceAppId  = "00000003-0000-0000-c000-000000000000"
              resourceAccess = @(
                @{
                  id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"
                  type = "Scope"
                }
              )
            }
          )
        } | ConvertTo-Json -Depth 10

        $app = Invoke-RestMethod -Method POST `
          -Uri "$graphBase/applications" `
          -Headers $headers `
          -Body $appBody

        Write-Output "Created app registration: $($app.appId)"
      }

      $appId = $app.appId
      $appObjectId = $app.id

      # ── 2. Ensure Service Principal exists ──
      $existingSPs = Invoke-RestMethod -Method GET `
        -Uri "$graphBase/servicePrincipals?`$filter=appId eq '$appId'" `
        -Headers $headers

      if ($existingSPs.value.Count -gt 0) {
        $sp = $existingSPs.value[0]
        Write-Output "Service principal already exists: $($sp.id)"
      } else {
        Write-Output "Creating service principal..."
        $spBody = @{ appId = $appId } | ConvertTo-Json
        $sp = Invoke-RestMethod -Method POST `
          -Uri "$graphBase/servicePrincipals" `
          -Headers $headers `
          -Body $spBody
        Write-Output "Created service principal: $($sp.id)"
      }

      # ── 3. Add password credential (always creates a new one) ──
      Write-Output "Generating client secret..."
      $pwBody = @{
        passwordCredential = @{
          displayName = "Generated by Bicep"
        }
      } | ConvertTo-Json -Depth 3

      $pwResponse = Invoke-RestMethod -Method POST `
        -Uri "$graphBase/applications/$appObjectId/addPassword" `
        -Headers $headers `
        -Body $pwBody

      $clientSecret = $pwResponse.secretText
      if ([string]::IsNullOrWhiteSpace($clientSecret)) {
        throw "Failed to generate client secret for application $appId"
      }
      Write-Output "Client secret generated successfully."

      # ── 4. Store in Key Vault ──
      $secretValue = ConvertTo-SecureString -String $clientSecret -AsPlainText -Force
      Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "ENTRA-APP-CLIENT-SECRET" -SecretValue $secretValue | Out-Null
      Write-Output "Client secret stored in Key Vault: $KeyVaultName"

      # ── 5. Output results ──
      $tenantId = (Get-AzContext).Tenant.Id
      $DeploymentScriptOutputs = @{
        appClientId                   = $appId
        appObjectId                   = $appObjectId
        tenantId                      = $tenantId
        servicePrincipalObjectId      = $sp.id
        audience                      = "api://$appId"
        clientSecretKeyVaultSecretName = "ENTRA-APP-CLIENT-SECRET"
      }
    '''
  }
}

// ------------------
//    OUTPUTS
// ------------------

@description('Entra ID App Registration Client ID')
output appClientId string = entraAppScript.properties.outputs.appClientId

@description('Entra ID App Registration Object ID')
output appObjectId string = entraAppScript.properties.outputs.appObjectId

@description('Azure AD Tenant ID')
output tenantId string = entraAppScript.properties.outputs.tenantId

@description('Service Principal Object ID for RBAC assignments')
output servicePrincipalObjectId string = entraAppScript.properties.outputs.servicePrincipalObjectId

@description('Name of the Key Vault secret containing the client secret')
output clientSecretKeyVaultSecretName string = entraAppScript.properties.outputs.clientSecretKeyVaultSecretName

@description('Audience URI for JWT validation (use appId as audience)')
output audience string = entraAppScript.properties.outputs.audience
