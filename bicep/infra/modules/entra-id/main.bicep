/**
 * @module entra-id
 * @description Creates an Entra ID (Azure AD) App Registration for JWT authentication
 *              with the Unified AI API. Includes service principal, client secret,
 *              and Key Vault storage.
 *
 * This module is equivalent to the Terraform Entra-Id module in APIM-Unified-AI-Gateway-Sample,
 * implemented in Bicep using deployment scripts for Microsoft Graph operations.
 *
 * Gated by enableJwtAuth parameter in the parent module.
 */

// ------------------
//    PARAMETERS
// ------------------

@description('Prefix for resource naming (used in app registration display name)')
param namingPrefix string

@description('Name of the Key Vault to store the client secret')
param keyVaultName string

@description('User-assigned managed identity resource ID for deployment script execution')
param deploymentScriptIdentityId string = ''

@description('Location for deployment script resources')
param location string = resourceGroup().location

// ------------------
//    RESOURCES
// ------------------

// Use a deployment script to create the Entra ID App Registration
// This is needed because Bicep does not natively support Microsoft.Graph resources in all environments
resource appRegistrationScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: '${namingPrefix}-entra-app-script'
  location: location
  kind: 'AzurePowerShell'
  identity: !empty(deploymentScriptIdentityId) ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${deploymentScriptIdentityId}': {}
    }
  } : null
  properties: {
    azPowerShellVersion: '11.0'
    retentionInterval: 'PT1H'
    timeout: 'PT30M'
    arguments: '-AppDisplayName "${namingPrefix}-unified-ai-app" -KeyVaultName "${keyVaultName}"'
    scriptContent: '''
      param(
        [string]$AppDisplayName,
        [string]$KeyVaultName
      )

      # Check if app already exists
      $existingApp = Get-AzADApplication -DisplayName $AppDisplayName -ErrorAction SilentlyContinue

      if ($existingApp) {
        Write-Output "App registration '$AppDisplayName' already exists with ID: $($existingApp.AppId)"
        $app = $existingApp
      } else {
        # Create the App Registration
        $app = New-AzADApplication -DisplayName $AppDisplayName -SignInAudience "AzureADMyOrg"
        Write-Output "Created app registration '$AppDisplayName' with ID: $($app.AppId)"

        # Set identifier URI
        Update-AzADApplication -ObjectId $app.Id -IdentifierUri "api://$($app.AppId)"
      }

      # Create Service Principal if not exists
      $sp = Get-AzADServicePrincipal -ApplicationId $app.AppId -ErrorAction SilentlyContinue
      if (-not $sp) {
        $sp = New-AzADServicePrincipal -ApplicationId $app.AppId
        Write-Output "Created service principal for app"
      }

      # Create client secret
      $secret = New-AzADAppCredential -ObjectId $app.Id -EndDate (Get-Date).AddYears(2)

      # Store in Key Vault
      $secretValue = ConvertTo-SecureString -String $secret.SecretText -AsPlainText -Force
      Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "UNIFIED-AI-ENTRA-APP-CLIENT-SECRET" -SecretValue $secretValue

      # Get tenant ID
      $tenantId = (Get-AzContext).Tenant.Id

      # Output results
      $DeploymentScriptOutputs = @{
        appClientId = $app.AppId
        tenantId = $tenantId
        servicePrincipalObjectId = $sp.Id
        clientSecretKeyVaultSecretName = "UNIFIED-AI-ENTRA-APP-CLIENT-SECRET"
      }
    '''
  }
}

// ------------------
//    OUTPUTS
// ------------------

@description('Entra ID App Registration Client ID')
output appClientId string = appRegistrationScript.properties.outputs.appClientId

@description('Azure AD Tenant ID')
output tenantId string = appRegistrationScript.properties.outputs.tenantId

@description('Service Principal Object ID for RBAC assignments')
output servicePrincipalObjectId string = appRegistrationScript.properties.outputs.servicePrincipalObjectId

@description('Name of the Key Vault secret containing the client secret')
output clientSecretKeyVaultSecretName string = appRegistrationScript.properties.outputs.clientSecretKeyVaultSecretName
