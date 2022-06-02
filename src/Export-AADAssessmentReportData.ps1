
function Export-AADAssessmentReportData {
    [CmdletBinding()]
    param
    (
        # Full path of the directory where the source xml files are located.
        [Parameter(Mandatory = $true)]
        [string] $SourceDirectory,
        # Full path of the directory where the output files will be generated.
        [Parameter(Mandatory = $false)]
        [string] $OutputDirectory,
        # Force report generation even if target is already present
        [Parameter(Mandatory = $false)]
        [switch] $Force
    )

    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory = $SourceDirectory
    }

    $LookupCache = New-LookupCache

    if (!(Test-Path -Path (Join-Path $OutputDirectory "applications.json")) -or $Force) {
        Import-Clixml -Path (Join-Path $SourceDirectory "applicationData.xml") `
        | Use-Progress -Activity 'Exporting applications' -Property displayName -PassThru -WriteSummary `
        | Export-JsonArray (Join-Path $OutputDirectory "applications.json") -Depth 5 -Compress
    }

    # Import-Clixml -Path (Join-Path $SourceDirectory "directoryRoleData.xml") `
    # | Use-Progress -Activity 'Exporting directoryRoles' -Property displayName -PassThru -WriteSummary `
    # | Export-JsonArray (Join-Path $OutputDirectory "directoryRoles.json") -Depth 5 -Compress

    if (!(Test-Path -Path (Join-Path $OutputDirectory "appRoleAssignments.csv")) -or $Force) {
        Set-Content -Path (Join-Path $OutputDirectory "appRoleAssignments.csv") -Value 'id,appRoleId,createdDateTime,principalDisplayName,principalId,principalType,resourceDisplayName,resourceId'
        Import-Clixml -Path (Join-Path $SourceDirectory "appRoleAssignmentData.xml") `
        | Use-Progress -Activity 'Exporting appRoleAssignments' -Property id -PassThru -WriteSummary `
        | Format-Csv `
        | Export-Csv (Join-Path $OutputDirectory "appRoleAssignments.csv") -NoTypeInformation
    }

    if (!(Test-Path -Path (Join-Path $OutputDirectory "oauth2PermissionGrants.csv")) -or $Force) {
        Set-Content -Path (Join-Path $OutputDirectory "oauth2PermissionGrants.csv") -Value 'id,consentType,clientId,principalId,resourceId,scope'
        Import-Clixml -Path (Join-Path $SourceDirectory "oauth2PermissionGrantData.xml") `
        | Use-Progress -Activity 'Exporting oauth2PermissionGrants' -Property id -PassThru -WriteSummary `
        | Export-Csv (Join-Path $OutputDirectory "oauth2PermissionGrants.csv") -NoTypeInformation
    }

    if (!(Test-Path -Path (Join-Path $OutputDirectory "servicePrincipals.json")) -or $Force) {
        Import-Clixml -Path (Join-Path $SourceDirectory "servicePrincipalData.xml") `
        | Use-Progress -Activity 'Exporting servicePrincipals (JSON)' -Property displayName -PassThru -WriteSummary `
        | Export-JsonArray (Join-Path $OutputDirectory "servicePrincipals.json") -Depth 5 -Compress
    }

    if (!(Test-Path -Path (Join-Path $OutputDirectory "servicePrincipals.csv")) -or $Force) {
        Set-Content -Path (Join-Path $OutputDirectory "servicePrincipals.csv") -Value 'id,appId,servicePrincipalType,displayName,accountEnabled,appOwnerOrganizationId,appRoles,oauth2PermissionScopes,keyCredentials,passwordCredentials'
        Import-Clixml -Path (Join-Path $SourceDirectory "servicePrincipalData.xml") `
        | Use-Progress -Activity 'Exporting servicePrincipals (CSV)' -Property displayName -PassThru -WriteSummary `
        | Select-Object -Property id, appId, servicePrincipalType, displayName, accountEnabled, appOwnerOrganizationId `
        | Export-Csv (Join-Path $OutputDirectory "servicePrincipals.csv") -NoTypeInformation
    }

    # Import-Clixml -Path (Join-Path $SourceDirectory "userData.xml") `
    # | Use-Progress -Activity 'Exporting users' -Property displayName -PassThru -WriteSummary `
    # | Export-JsonArray (Join-Path $OutputDirectory "users.json") -Depth 5 -Compress

    ## Comment out to generate user data via report
    #Set-Content -Path (Join-Path $OutputDirectory "users.csv") -Value 'id,userPrincipalName,userType,displayName,accountEnabled,onPremisesSyncEnabled,onPremisesImmutableId,mail,otherMails,AADLicense,lastSigninDateTime'
    #Import-Clixml -Path (Join-Path $SourceDirectory "userData.xml") `
    #| Use-Progress -Activity 'Exporting users' -Property displayName -PassThru -WriteSummary `
    #| Select-Object -Property id, userPrincipalName, userType, displayName, accountEnabled,
    #    @{ Name = "onPremisesSyncEnabled"; Expression = { [bool]$_.onPremisesSyncEnabled } },
    #    @{ Name = "onPremisesImmutableId"; Expression = {![string]::IsNullOrWhiteSpace($_.onPremisesImmutableId)}},
    #    mail,
    #    @{ Name = "otherMails"; Expression = { $_.otherMails -join ';' } },
    #    @{ Name = "AADLicense"; Expression = {$plans = $_.assignedPlans | foreach-object { $_.servicePlanId }; if ($plans -contains "eec0eb4f-6444-4f95-aba0-50c24d67f998") { "AADP2" } elseif ($plans -contains "41781fb2-bc02-4b7c-bd55-b576c07bb09d") { "AADP1" } else { "None" }}} `
    #| Export-Csv (Join-Path $OutputDirectory "users.csv") -NoTypeInformation

    # Import-Clixml -Path (Join-Path $SourceDirectory "groupData.xml") `
    # | Use-Progress -Activity 'Exporting groups' -Property displayName -PassThru -WriteSummary `
    # | Export-JsonArray (Join-Path $OutputDirectory "groups.json") -Depth 5 -Compress

    if (!(Test-Path -Path (Join-Path $OutputDirectory "groups.csv")) -or $Force) {
        Set-Content -Path (Join-Path $OutputDirectory "groups.csv") -Value 'id,groupTypes,mailEnabled,securityEnabled,groupType,displayName,onPremisesSyncEnabled,mail'
        Import-Clixml -Path (Join-Path $SourceDirectory "groupData.xml") `
        | Use-Progress -Activity 'Exporting groups' -Property displayName -PassThru -WriteSummary `
        | Select-Object -Property id, groupTypes, mailEnabled, securityEnabled,
            @{ Name = "groupType"; Expression = {
                if ($_.groupTypes -contains "Unified") { "Microsoft 365" }
                elseif ($_.securityEnabled) {
                    if ($_.mailEnabled) { "Mail-enabled Security" }
                    else { "Security" }
                }
                elseif ($_.mailEnabled) { "Distribution" }
                else { "Unknown" } # not mail enabled neither security enabled
            }},
            displayName,
            @{ Name = "onPremisesSyncEnabled"; Expression = { [bool]$_.onPremisesSyncEnabled } },
            mail `
        | Export-Csv (Join-Path $OutputDirectory "groups.csv") -NoTypeInformation
    }

    ## Option 1 from Data Collection: Expand Group Membership to get transitiveMembers.
    # Import-Clixml -Path (Join-Path $SourceDirectory "groupData.xml") | Add-AadObjectToLookupCache -Type group -LookupCache $LookupCache
    # Set-Content -Path (Join-Path $OutputDirectory "groupTransitiveMembers.csv") -Value 'id,memberId,memberType'
    # $LookupCache.group.Values `
    # | Use-Progress -Activity 'Exporting group memberships' -Property displayName -Total $LookupCache.group.Count -PassThru -WriteSummary `
    # | ForEach-Object {
    #         $group = $_
    #         Expand-GroupTransitiveMembership $group.id -LookupCache $LookupCache | ForEach-Object {
    #             [PSCustomObject]@{
    #                 id         = $group.id
    #                 #'@odata.type' = $group.'@odata.type'
    #                 memberId   = $_.id
    #                 memberType = $_.'@odata.type' -replace '#microsoft.graph.', ''
    #                 #direct     = $group.members.id.Contains($_.id)
    #             }
    #         }
    #     } `
    # | Export-Csv (Join-Path $OutputDirectory "groupTransitiveMembers.csv") -NoTypeInformation

    # Set-Content -Path (Join-Path $OutputDirectory "administrativeUnits.csv") -Value 'id,displayName,visibility,users,groups'
    # Import-Clixml -Path (Join-Path $SourceDirectory "administrativeUnitsData.xml") `
    # | Use-Progress -Activity 'Exporting Administrative Units' -Property displayName -PassThru -WriteSummary `
    # | Select-Object id, displayName, visibility, `
    # @{Name = "users"; Expression = { ($_.members | Where-Object { $_."@odata.type" -like "*.user" }).count } }, `
    # @{Name = "groups"; Expression = { ($_.members | Where-Object { $_."@odata.type" -like "*.group" }).count } }`
    # | Export-Csv -Path (Join-Path $OutputDirectory "administrativeUnits.csv") -NoTypeInformation


    ### Execute Report Commands

    # user report
    if (!(Test-Path -Path (Join-Path $OutputDirectory "users.csv")) -or $Force) {
        # load data if cache empty
        if ($LookupCache.user.Count -eq 0) {
            Write-Output "Loading users in lookup cache"
            Import-Clixml -Path (Join-Path $SourceDirectory "userData.xml") | Add-AadObjectToLookupCache -Type user -LookupCache $LookupCache
        }
        if ($LookupCache.userRegistrationDetails.Count -eq 0) {
            Write-Output "Loading users registration details in lookup cache"
            # In PS5 loading directly from ConvertFrom-Json fails
            $userRegistrationDetails = Get-Content -Path (Join-Path $SourceDirectory "userRegistrationDetails.json") -Raw | ConvertFrom-Json
            $userRegistrationDetails | Add-AadObjectToLookupCache -Type userRegistrationDetails -LookupCache $LookupCache
        }

        # generate the report
        Get-AADAssessUserReport -Offline -UserData $LookupCache.user -RegistrationDetailsData  $LookupCache.userRegistrationDetails`
        | Use-Progress -Activity 'Exporting UserReport' -Property id -PassThru -WriteSummary `
        | Format-Csv `
        | Export-Csv -Path (Join-Path $OutputDirectory "users.csv") -NoTypeInformation

        # clean what is not used by other reports
        $LookupCache.userRegistrationDetails.Clear()
    }

    # notificaiton emails report
    if (!(Test-Path -Path (Join-Path $OutputDirectory "NotificationsEmailsReport.csv")) -or $Force) {
        # load unique data
        $OrganizationData = Get-Content -Path (Join-Path $SourceDirectory "organization.json") -Raw | ConvertFrom-Json
        [array] $DirectoryRoleData = Import-Clixml -Path (Join-Path $SourceDirectory "directoryRoleData.xml")
        # load data if cache empty
        if ($LookupCache.user.Count -eq 0) {
            Write-Output "Loading users in lookup cache"
            Import-Clixml -Path (Join-Path $SourceDirectory "userData.xml") | Add-AadObjectToLookupCache -Type user -LookupCache $LookupCache
        }
        if ($LookupCache.group.Count -eq 0) {
            Write-Output "Loading groups in lookup cache"
            Import-Clixml -Path (Join-Path $SourceDirectory "groupData.xml") | Add-AadObjectToLookupCache -Type group -LookupCache $LookupCache
        }

        # generate the report
        Get-AADAssessNotificationEmailsReport -Offline -OrganizationData $OrganizationData -UserData $LookupCache.user -GroupData $LookupCache.group -DirectoryRoleData $DirectoryRoleData `
        | Use-Progress -Activity 'Exporting NotificationsEmailsReport' -Property recipientEmail -PassThru -WriteSummary `
        | Export-Csv -Path (Join-Path $OutputDirectory "NotificationsEmailsReport.csv") -NoTypeInformation

        # clean unique data
        Remove-Variable DirectoryRoleData
    }

    # role assignment report
    if (!(Test-Path -Path (Join-Path $OutputDirectory "RoleAssignmentReport.csv")) -or $Force) {
        # load unique data
        [array] $roleAssignmentSchedulesData = Import-Clixml -Path (Join-Path $SourceDirectory "roleAssignmentSchedulesData.xml")
        [array] $roleEligibilitySchedulesData = Import-Clixml -Path (Join-Path $SourceDirectory "roleEligibilitySchedulesData.xml")
        # load data if cache empty
        if ($LookupCache.user.Count -eq 0) {
            Write-Output "Loading users in lookup cache"
            Import-Clixml -Path (Join-Path $SourceDirectory "userData.xml") | Add-AadObjectToLookupCache -Type user -LookupCache $LookupCache
        }
        if ($LookupCache.group.Count -eq 0) {
            Write-Output "Loading groups in lookup cache"
            Import-Clixml -Path (Join-Path $SourceDirectory "groupData.xml") | Add-AadObjectToLookupCache -Type group -LookupCache $LookupCache
        }
        if ($LookupCache.administrativeUnit.Count -eq 0) {
            Write-Output "Loading administrative units in lookup cache"
            Import-Csv -Path (Join-Path $SourceDirectory "administrativeUnits.csv") | Add-AadObjectToLookupCache -Type administrativeUnit -LookupCache $LookupCache
        }
        if ($LookupCache.application.Count -eq 0) {
            Write-Output "Loading applications in lookup cache"
            Import-Clixml -Path (Join-Path $SourceDirectory "applicationData.xml") | Add-AadObjectToLookupCache -Type application -LookupCache $LookupCache
        }
        if ($LookupCache.servicePrincipal.Count -eq 0) {
            Write-Output "Loading service principals in lookup cache"
            Import-Clixml -Path (Join-Path $SourceDirectory "servicePrincipalData.xml") | Add-AadObjectToLookupCache -Type servicePrincipal -LookupCache $LookupCache
        }

        # generate the report
        <#
        Get-AADAssessRoleAssignmentReport -Offline -RoleAssignmentSchedulesData $roleAssignmentSchedulesData -RoleEligibilitySchedulesData $roleEligibilitySchedulesData -OrganizationData $OrganizationData -AdministrativeUnitsData $LookupCache.administrativeUnit -UsersData $LookupCache.user -GroupsData $LookupCache.group -ApplicationsData $LookupCache.application -ServicePrincipalsData $LookupCache.servicePrincipal `
        | Use-Progress -Activity 'Exporting RoleAssignmentReport' -Property id -PassThru -WriteSummary `
        | Format-Csv `
        | Export-Csv -Path (Join-Path $OutputDirectory "RoleAssignmentReport.csv") -NoTypeInformation
#>
        Get-AADAssessRoleAssignmentReport -RoleAssignmentSchedulesData $roleAssignmentSchedulesData -RoleEligibilitySchedulesData $roleEligibilitySchedulesData -OrganizationData $OrganizationData -AdministrativeUnitsData $LookupCache.administrativeUnit -UsersData $LookupCache.user -GroupsData $LookupCache.group -ApplicationsData $LookupCache.application -ServicePrincipalsData $LookupCache.servicePrincipal `
        | Use-Progress -Activity 'Exporting RoleAssignmentReport' -Property id -PassThru -WriteSummary `
        | Format-Csv `
        | Export-Csv -Path (Join-Path $OutputDirectory "RoleAssignmentReport.csv") -NoTypeInformation

        #PowerBI report requires the file name to roleAssignments.csv, not sure what the impact would be to change above so decided to keep two files.
        Get-AADAssessRoleAssignmentReport -RoleAssignmentSchedulesData $roleAssignmentSchedulesData -RoleEligibilitySchedulesData $roleEligibilitySchedulesData -OrganizationData $OrganizationData -AdministrativeUnitsData $LookupCache.administrativeUnit -UsersData $LookupCache.user -GroupsData $LookupCache.group -ApplicationsData $LookupCache.application -ServicePrincipalsData $LookupCache.servicePrincipal `
        | Use-Progress -Activity 'Exporting RoleAssignmentReport second report' -Property id -PassThru -WriteSummary `
        | Format-Csv `
        | Export-Csv -Path (Join-Path $OutputDirectory "roleAssignments.csv") -NoTypeInformation

        # clear unique data
        Remove-Variable roleAssignmentSchedulesData, roleEligibilitySchedulesData
        # clear cache as data is not further used by other reports
        $LookupCache.group.Clear()
        $LookupCache.administrativeUnit.Clear()
    }

    # app credential report
    if (!(Test-Path -Path (Join-Path $OutputDirectory "AppCredentialsReport.csv")) -or $Force) {
        # load data in cache if empty
        if ($LookupCache.application.Count -eq 0) {
            Write-Output "Loading applications in lookup cache"
            Import-Clixml -Path (Join-Path $SourceDirectory "applicationData.xml") | Add-AadObjectToLookupCache -Type application -LookupCache $LookupCache
        }
        if ($LookupCache.servicePrincipal.Count -eq 0) {
            Write-Output "Loading service principals in lookup cache"
            Import-Clixml -Path (Join-Path $SourceDirectory "servicePrincipalData.xml") | Add-AadObjectToLookupCache -Type servicePrincipal -LookupCache $LookupCache
        }

        # generate the report
        Get-AADAssessAppCredentialExpirationReport -Offline -ApplicationData $LookupCache.application -ServicePrincipalData $LookupCache.servicePrincipal `
        | Use-Progress -Activity 'Exporting AppCredentialsReport' -Property displayName -PassThru -WriteSummary `
        | Format-Csv `
        | Export-Csv -Path (Join-Path $OutputDirectory "AppCredentialsReport.csv") -NoTypeInformation

        # clear cache as data in bot further used by other reports
        $LookupCache.application.Clear()
    }

    # consent grant report
    if (!(Test-Path -Path (Join-Path $OutputDirectory "ConsentGrantReport.csv")) -or $Force) {
        # load unique data
        [array] $AppRoleAssignmentData = Import-Clixml -Path (Join-Path $SourceDirectory "appRoleAssignmentData.xml")
        [array] $OAuth2PermissionGrantData = Import-Clixml -Path (Join-Path $OutputDirectory "oauth2PermissionGrantData.xml")
        # load data if cache empty
        if ($LookupCache.user.Count -eq 0) {
            Write-Output "Loading users in lookup cache"
            Import-Clixml -Path (Join-Path $SourceDirectory "userData.xml") | Add-AadObjectToLookupCache -Type user -LookupCache $LookupCache
        }
        if ($LookupCache.servicePrincipal.Count -eq 0) {
            Write-Output "Loading service principals in lookup cache"
            Import-Clixml -Path (Join-Path $SourceDirectory "servicePrincipalData.xml") | Add-AadObjectToLookupCache -Type servicePrincipal -LookupCache $LookupCache
        }

        # generate the report
        Get-AADAssessConsentGrantReport -Offline -AppRoleAssignmentData $AppRoleAssignmentData -OAuth2PermissionGrantData $OAuth2PermissionGrantData -UserData $LookupCache.user -ServicePrincipalData $LookupCache.servicePrincipal `
        | Use-Progress -Activity 'Exporting ConsentGrantReport' -Property clientDisplayName -PassThru -WriteSummary `
        | Export-Csv -Path (Join-Path $OutputDirectory "ConsentGrantReport.csv") -NoTypeInformation
    }

}

# SIG # Begin signature block
# MIInrAYJKoZIhvcNAQcCoIInnTCCJ5kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC4EywCwh/aM5XR
# bxSZIF9dukTNjy3aOKdnIiDDRIYWd6CCDYEwggX/MIID56ADAgECAhMzAAACUosz
# qviV8znbAAAAAAJSMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjEwOTAyMTgzMjU5WhcNMjIwOTAxMTgzMjU5WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDQ5M+Ps/X7BNuv5B/0I6uoDwj0NJOo1KrVQqO7ggRXccklyTrWL4xMShjIou2I
# sbYnF67wXzVAq5Om4oe+LfzSDOzjcb6ms00gBo0OQaqwQ1BijyJ7NvDf80I1fW9O
# L76Kt0Wpc2zrGhzcHdb7upPrvxvSNNUvxK3sgw7YTt31410vpEp8yfBEl/hd8ZzA
# v47DCgJ5j1zm295s1RVZHNp6MoiQFVOECm4AwK2l28i+YER1JO4IplTH44uvzX9o
# RnJHaMvWzZEpozPy4jNO2DDqbcNs4zh7AWMhE1PWFVA+CHI/En5nASvCvLmuR/t8
# q4bc8XR8QIZJQSp+2U6m2ldNAgMBAAGjggF+MIIBejAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUNZJaEUGL2Guwt7ZOAu4efEYXedEw
# UAYDVR0RBEkwR6RFMEMxKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMRYwFAYDVQQFEw0yMzAwMTIrNDY3NTk3MB8GA1UdIwQYMBaAFEhu
# ZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNpZ1BDQTIwMTFfMjAxMS0w
# Ny0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUFBzAChkVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0NvZFNpZ1BDQTIwMTFfMjAx
# MS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAFkk3
# uSxkTEBh1NtAl7BivIEsAWdgX1qZ+EdZMYbQKasY6IhSLXRMxF1B3OKdR9K/kccp
# kvNcGl8D7YyYS4mhCUMBR+VLrg3f8PUj38A9V5aiY2/Jok7WZFOAmjPRNNGnyeg7
# l0lTiThFqE+2aOs6+heegqAdelGgNJKRHLWRuhGKuLIw5lkgx9Ky+QvZrn/Ddi8u
# TIgWKp+MGG8xY6PBvvjgt9jQShlnPrZ3UY8Bvwy6rynhXBaV0V0TTL0gEx7eh/K1
# o8Miaru6s/7FyqOLeUS4vTHh9TgBL5DtxCYurXbSBVtL1Fj44+Od/6cmC9mmvrti
# yG709Y3Rd3YdJj2f3GJq7Y7KdWq0QYhatKhBeg4fxjhg0yut2g6aM1mxjNPrE48z
# 6HWCNGu9gMK5ZudldRw4a45Z06Aoktof0CqOyTErvq0YjoE4Xpa0+87T/PVUXNqf
# 7Y+qSU7+9LtLQuMYR4w3cSPjuNusvLf9gBnch5RqM7kaDtYWDgLyB42EfsxeMqwK
# WwA+TVi0HrWRqfSx2olbE56hJcEkMjOSKz3sRuupFCX3UroyYf52L+2iVTrda8XW
# esPG62Mnn3T8AuLfzeJFuAbfOSERx7IFZO92UPoXE1uEjL5skl1yTZB3MubgOA4F
# 8KoRNhviFAEST+nG8c8uIsbZeb08SeYQMqjVEmkwggd6MIIFYqADAgECAgphDpDS
# AAAAAAADMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMTAeFw0xMTA3MDgyMDU5MDlaFw0yNjA3MDgyMTA5MDla
# MH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMT
# H01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQCr8PpyEBwurdhuqoIQTTS68rZYIZ9CGypr6VpQqrgG
# OBoESbp/wwwe3TdrxhLYC/A4wpkGsMg51QEUMULTiQ15ZId+lGAkbK+eSZzpaF7S
# 35tTsgosw6/ZqSuuegmv15ZZymAaBelmdugyUiYSL+erCFDPs0S3XdjELgN1q2jz
# y23zOlyhFvRGuuA4ZKxuZDV4pqBjDy3TQJP4494HDdVceaVJKecNvqATd76UPe/7
# 4ytaEB9NViiienLgEjq3SV7Y7e1DkYPZe7J7hhvZPrGMXeiJT4Qa8qEvWeSQOy2u
# M1jFtz7+MtOzAz2xsq+SOH7SnYAs9U5WkSE1JcM5bmR/U7qcD60ZI4TL9LoDho33
# X/DQUr+MlIe8wCF0JV8YKLbMJyg4JZg5SjbPfLGSrhwjp6lm7GEfauEoSZ1fiOIl
# XdMhSz5SxLVXPyQD8NF6Wy/VI+NwXQ9RRnez+ADhvKwCgl/bwBWzvRvUVUvnOaEP
# 6SNJvBi4RHxF5MHDcnrgcuck379GmcXvwhxX24ON7E1JMKerjt/sW5+v/N2wZuLB
# l4F77dbtS+dJKacTKKanfWeA5opieF+yL4TXV5xcv3coKPHtbcMojyyPQDdPweGF
# RInECUzF1KVDL3SV9274eCBYLBNdYJWaPk8zhNqwiBfenk70lrC8RqBsmNLg1oiM
# CwIDAQABo4IB7TCCAekwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFEhuZOVQ
# BdOCqhc3NyK1bajKdQKVMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1Ud
# DwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO
# 4eqnxzHRI4k0MFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwubWljcm9zb2Z0
# LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcmwwXgYIKwYBBQUHAQEEUjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcnQwgZ8GA1UdIASBlzCBlDCBkQYJKwYBBAGCNy4DMIGDMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2RvY3MvcHJpbWFyeWNw
# cy5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AcABvAGwAaQBjAHkA
# XwBzAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAGfyhqWY
# 4FR5Gi7T2HRnIpsLlhHhY5KZQpZ90nkMkMFlXy4sPvjDctFtg/6+P+gKyju/R6mj
# 82nbY78iNaWXXWWEkH2LRlBV2AySfNIaSxzzPEKLUtCw/WvjPgcuKZvmPRul1LUd
# d5Q54ulkyUQ9eHoj8xN9ppB0g430yyYCRirCihC7pKkFDJvtaPpoLpWgKj8qa1hJ
# Yx8JaW5amJbkg/TAj/NGK978O9C9Ne9uJa7lryft0N3zDq+ZKJeYTQ49C/IIidYf
# wzIY4vDFLc5bnrRJOQrGCsLGra7lstnbFYhRRVg4MnEnGn+x9Cf43iw6IGmYslmJ
# aG5vp7d0w0AFBqYBKig+gj8TTWYLwLNN9eGPfxxvFX1Fp3blQCplo8NdUmKGwx1j
# NpeG39rz+PIWoZon4c2ll9DuXWNB41sHnIc+BncG0QaxdR8UvmFhtfDcxhsEvt9B
# xw4o7t5lL+yX9qFcltgA1qFGvVnzl6UJS0gQmYAf0AApxbGbpT9Fdx41xtKiop96
# eiL6SJUfq/tHI4D1nvi/a7dLl+LrdXga7Oo3mXkYS//WsyNodeav+vyL6wuA6mk7
# r/ww7QRMjt/fdW1jkT3RnVZOT7+AVyKheBEyIXrvQQqxP/uozKRdwaGIm1dxVk5I
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZgTCCGX0CAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAlKLM6r4lfM52wAAAAACUjAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQggMzutH2Z
# 9L/TD4lnq0d8bGq5v9cD8SFPD5lDXroGo3gwQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQAOhykIX2pp9a6fYuESmKHkaiR8rLWkte+nPJC73LkJ
# WvfZv3Jhik4wwVrOspx36I8istJRv6Nu5GRiD56HW5FrarscHyXsoCWU+Aa4NY1Z
# KwHuRquWMP/7i6b433IqFM41jIuIiZ+F5Ap7Q1GGrY3H8/NcutJZDBt1lcmj/kEZ
# jj82xG9ccoHHAwl3NiToBzIHu8kFOSUtPYAQZYUhLMtBex3lwT88nr9TTA6Y2gfF
# A0zIbxyoK3/44uNYJmZ4reK9t+lAJi7yFiORNmxZzxVTULVJJblEP4SaFFr/GSTj
# hTId75naB9vg4zaoh5P6f298gk6He1ErCSGVR+p8VpYLoYIXCzCCFwcGCisGAQQB
# gjcDAwExghb3MIIW8wYJKoZIhvcNAQcCoIIW5DCCFuACAQMxDzANBglghkgBZQME
# AgEFADCCAVQGCyqGSIb3DQEJEAEEoIIBQwSCAT8wggE7AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIHeDCnGUbjGY1AzuJpcmqHWZfvMNKlg5YRx8nvcw
# jtTQAgZihNG7VxMYEjIwMjIwNTE5MjEwNDExLjU2WjAEgAIB9KCB1KSB0TCBzjEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEpMCcGA1UECxMgTWlj
# cm9zb2Z0IE9wZXJhdGlvbnMgUHVlcnRvIFJpY28xJjAkBgNVBAsTHVRoYWxlcyBU
# U1MgRVNOOjYwQkMtRTM4My0yNjM1MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1T
# dGFtcCBTZXJ2aWNloIIRXzCCBxAwggT4oAMCAQICEzMAAAGmWUWDOU2e60sAAQAA
# AaYwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAw
# HhcNMjIwMzAyMTg1MTIxWhcNMjMwNTExMTg1MTIxWjCBzjELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEpMCcGA1UECxMgTWljcm9zb2Z0IE9wZXJh
# dGlvbnMgUHVlcnRvIFJpY28xJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOjYwQkMt
# RTM4My0yNjM1MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA2Zi/e1Ij58n81AmePPsm
# 8Kdz5ebSsqh71goPgy8xgK6Xt6B2tP/O/m8VtCCM1DvjrvZ83B5rO2RHrlXzLb27
# k8vax/TWn65yF7Rm7i1KKD4axDplCX22M9EBj/chMEcN4hjK+rxad737s2g8uHEN
# I7p21ftgK5DjNxM/dIToy8Hhvk2KCF22+hlVpiTWVemNRN92YqhfUAGrWwltQtKd
# KLRB3i++XeZn2PHC/11H+eVk/raWtlhmrss+0cPoGWZyUHk9Pz0OdKbWyNpmcUes
# rM6yarkaWYvlIW6AIJk6grPXfcUl5BoUxxcFlIJCM0AFYFschEITXKwccbzcN2id
# GacLwQ6Vh5HBNbP9ALPqrSuI4htjIL8DYGBQSm73/0TKatOzIyvb/NLwZ0TJtDlb
# t/RatyuYoH9jrb6DpOZ85Lw21T4vWMago0bpDlGV8nBm7wn9D12Xg7HIcq7Lvz7C
# boewXu4CLOmxaHrdRRqgr84ZCIEbc0n6R5/l5ame9rhkl+ECephMBkPW4eB/xV9C
# OeXQEHZhfMr1ZpOp17x37yoLFUqvmEli9s75ff7aTk8KKtQr9Juit5f7FSFVpASF
# UNiqVq3I+20jtnYiuSEzPAW9z6nRB7IyI2ajZwFl6PHyJwM5xSJ3DKYNRioY8Tsw
# Dy+0pbd955JJgmwISS5Q7+8CAwEAAaOCATYwggEyMB0GA1UdDgQWBBQ6VCE7/MaW
# or31SQ0v8a78CvI32DAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBf
# BgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3Bz
# L2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmww
# bAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0El
# MjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsGAQUFBwMI
# MA0GCSqGSIb3DQEBCwUAA4ICAQCAwPFYNOkaoucWg+Gb+IN/AcYXzGvY1usmXx6A
# SDZOFMmxN/TAET5lCydh+tGZcFt7qwJctU3vSo+4j44Rs3kw5qLsG57X/iPlVORa
# q4fkZl5Vq3Y350PuVJRanR1TyP64GEEvkYVKagNVWb7NbYZHaO48jW/bngAlNvaX
# jnxqeWQmMa+ZifYG1FLXeH/ANHuGtBojsGB3IdYBXn4cSPlSGsiuu+3AmKK9JpQQ
# Deorpkr+tkhC/+45EOQ43D7akccgTVJeb9YiWGtVLYciiB+vcmOq9mKifoslIPvj
# WPzFUMuIKXABuykehUWPG3EFwyOo/HppYIlLy+NKhOeGRXg87nmaqwztDxdBEZCE
# DvDjM1A4m72QPjEV1ik9SYs391ohwQSWh8GMbP6wR3UHjKqoiTe7YbhXKBNcWa2E
# vxyFKjuv4Yi9OpYqFID+xqdLg3eMKAIJ7cVNImyniDmfBq8u9YC3Nw4i9JGisaYB
# 43SbbCDMEr3lP+qCsYYNdKizUk0NZFUGc/SqzDVCirkbQPyHG9A+zdfjcoG/UYmX
# TCjmtwL704xbEmUHreC1OhCwDUIStihgsxm1TMkvviPBmT+CukcRCEiEHeyd4LzD
# MYom5+3tg78dYKm7B0KEiPKdOcGH7IUYx2DfBGshs5zD+IqZdmikxNAw5yYh4jAk
# B7MDsDCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcN
# AQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAw
# BgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEw
# MB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk
# 4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9c
# T8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWG
# UNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6Gnsz
# rYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2
# LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLV
# wIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTd
# EonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0
# gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFph
# AXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJ
# YfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXb
# GjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJ
# KwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnP
# EP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMw
# UQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggr
# BgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYw
# DwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoY
# xDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtp
# L2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYB
# BQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20v
# cGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0B
# AQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U5
# 18JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgAD
# sAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo
# 32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZ
# iefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZK
# PmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RI
# LLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgk
# ujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9
# af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzba
# ukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/
# OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggLSMIIC
# OwIBATCB/KGB1KSB0TCBzjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEpMCcGA1UECxMgTWljcm9zb2Z0IE9wZXJhdGlvbnMgUHVlcnRvIFJpY28x
# JjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOjYwQkMtRTM4My0yNjM1MSUwIwYDVQQD
# ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQBq
# dDOtlb1MH3dV7s9rhQ9qjZ98raCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwMA0GCSqGSIb3DQEBBQUAAgUA5jChszAiGA8yMDIyMDUxOTE1MDAw
# M1oYDzIwMjIwNTIwMTUwMDAzWjB3MD0GCisGAQQBhFkKBAExLzAtMAoCBQDmMKGz
# AgEAMAoCAQACAhNGAgH/MAcCAQACAhEhMAoCBQDmMfMzAgEAMDYGCisGAQQBhFkK
# BAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJ
# KoZIhvcNAQEFBQADgYEABSL6HDWs9isoaM9k9SAtAc+nGTe+XBXjuODtxAdLp8zO
# x0fNVNWD3kF6lLiGpfYXNZAEbn7mXfxsr0tOAI+ELqwyf95oDCjzCHwAGXIWpiXq
# TYjTB8zhTDWMwtpoazzsawxldaa8GitJ5cSg0+UpGqpWCWZEuxeUut/5ThgtMuAx
# ggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAA
# AaZZRYM5TZ7rSwABAAABpjANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkD
# MQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCD/0aBVHXW/gMUQol3JYpEM
# qOjQ5fnKVePzwFR3ZEWhXzCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIIML
# GYvDP3R9a+EwpslMBBoq3cOhd6ICF+nxMP22BKsNMIGYMIGApH4wfDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGmWUWDOU2e60sAAQAAAaYwIgQgr/mw
# uQeqV8B0gipFxPd8LMDFiakQNIiaXRggGnOaX78wDQYJKoZIhvcNAQELBQAEggIA
# awvw1umqM8VmzEIwj3scEViJPFCTauPud2HEZPpwLMu2Y5o85f2iwZMsO7IuI8rY
# GC3z1y9l7WyoxEBNaiP+0iG7Vs2aEiG3E9WzNKwmQVvgVHxUmqoBGt/G0Sj8fiY1
# j8RRfqac6hxMkdIcPtP1Pycq5gDa7Ey9ymY3LChtF9atD0YfwyxzkOpFwCvs+2/x
# GlmJ7XW1GTfZ0NpgGytEYkZM24uPph3dXbAouFUv+s6rlsUEEWiYuUTItfA+wwl3
# OU0hj2e/dJDghEndwMI4YGxsu2m+L9lEg5VnLNpPD6eVOlT01oig1s4LJ3CXkU6P
# Or62HS+xQyRDXtnpkJLSVu4B2qx/YeTQnqxIzrvlER6pxjksvzJOs3KO+1Ob7zcm
# k33+MrzfivRDxaJHaqpChXN+DKgFUAPY0RjzZK0TjrlUNCm4xWAf4ugR9LgxL10U
# f8KFVHkVAnLlckZZ8JzZNIR8G0HeAyOK85MEoqLo2ItnanLC7nQqbS/NKWLFhtpH
# BOhVXuZe8BCk2GByLNLy8HxKytWgti4AM9w4ql3mv0abSavGRZC9vNlgSVkPgPJ5
# WuTsvaHOZ3uHAZHuHx0fpuYpoc3ZYs3oVxY/tfZVQhxQgExlqXWOeFND4EalN8bw
# t2qpO/vS9xgTiNrLMRkx51dRm6OvvmdQ7O2RiShI/CE=
# SIG # End signature block
