targetScope = 'subscription'

/**
 * @module Entra ID Setup
 * @description Deploys Entra ID App Registration, Service Principal, and stores client secret
 *              in Key Vault for JWT authentication with the AI Hub Gateway.
 *
 * This is an independent deployment that should be run BEFORE the main gateway deployment
 * when entraAuth is enabled. It uses a PowerShell setup script to call Microsoft Graph API
 * using the deployer's authenticated Azure CLI session.
 *
 * Usage:
 *   1. Run the setup script:
 *      pwsh ./setup.ps1 -EnvironmentName <env> -KeyVaultName <kv> [-Location <loc>]
 *
 *   2. The script creates (or reuses) the Entra App Registration, Service Principal,
 *      and client secret, storing the secret in Key Vault and outputting values as
 *      azd environment variables for the main deployment.
 *
 *   3. Run the main gateway deployment (azd up) — it picks up the Entra values
 *      from the environment variables set by this script.
 */

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Name of the environment (used in app registration naming)')
param environmentName string

@description('Key Vault resource coordinates for storing the client secret')
param keyVault object

// ============================================================================
// RESOURCES
// ============================================================================

// This module is intentionally a no-op Bicep file.
// The actual Entra ID operations are performed by the setup.ps1 PowerShell script
// because Microsoft Graph API calls (app registration, service principal, addPassword)
// require the deployer's authenticated session and cannot run inside Bicep
// deployment scripts without a pre-configured managed identity with Graph permissions.
//
// See setup.ps1 for the implementation and README.md for usage instructions.

// ============================================================================
// OUTPUTS
// ============================================================================

output instructions string = 'Run setup.ps1 to create the Entra ID App Registration. See README.md for details.'
