<#
.SYNOPSIS
    Produces the Azure AD Configuration reports required by the Azure AD assesment
.DESCRIPTION
    This cmdlet reads the configuration information from the target Azure AD Tenant and produces the output files in a target directory
.EXAMPLE
    PS C:\> Invoke-AADAssessmentDataCollection
    Collect and package assessment data to "C:\AzureADAssessment".
.EXAMPLE
    PS C:\> Invoke-AADAssessmentDataCollection -OutputDirectory "C:\Temp"
    Collect and package assessment data to "C:\Temp".
#>
function Invoke-AADAssessmentDataCollection {
    [CmdletBinding()]
    param (
        # Full path of the directory where the output files will be generated.
        [Parameter(Mandatory = $false)]
        [string] $OutputDirectory = (Join-Path $env:SystemDrive 'AzureADAssessment'),
        # Generate Reports
        [Parameter(Mandatory = $false)]
        [switch] $SkipReportOutput,
        # Skip Packaging
        [Parameter(Mandatory = $false)]
        [switch] $SkipPackaging,
        [Parameter(Mandatory = $false)]
        # Skip getting user assigned plans
        [switch] $NoAssignedPlans
    )

    Start-AppInsightsRequest $MyInvocation.MyCommand.Name
    try {

        $ReferencedIdCache = New-AadReferencedIdCache
        #$ReferencedIdCacheCA = New-AadReferencedIdCache

        function Extract-AppRoleAssignments {
            param (
                #
                [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
                [psobject] $InputObject,
                #
                [Parameter(Mandatory = $true)]
                [psobject] $ListVariable,
                #
                [Parameter(Mandatory = $false)]
                [switch] $PassThru
            )

            process {
                [PSCustomObject[]] $AppRoleAssignment = $InputObject.appRoleAssignedTo
                $ListVariable.AddRange($AppRoleAssignment)
                if ($PassThru) { return $InputObject }
            }
        }

        if ($MyInvocation.CommandOrigin -eq 'Runspace') {
            ## Reset Parent Progress Bar
            New-Variable -Name stackProgressId -Scope Script -Value (New-Object 'System.Collections.Generic.Stack[int]') -ErrorAction SilentlyContinue
            $stackProgressId.Clear()
            $stackProgressId.Push(0)
        }

        ### Initalize Directory Paths
        #$OutputDirectory = Join-Path $OutputDirectory "AzureADAssessment"
        $OutputDirectoryData = Join-Path $OutputDirectory "AzureADAssessmentData"
        $AssessmentDetailPath = Join-Path $OutputDirectoryData "AzureADAssessment.json"
        $PackagePath = Join-Path $OutputDirectory "AzureADAssessmentData.zip"

        ### Organization Data - 0
        Write-Progress -Id 0 -Activity 'Microsoft Azure AD Assessment Data Collection' -Status 'Organization Details' -PercentComplete 0
        $OrganizationData = Get-MsGraphResults 'organization?$select=id,displayName,verifiedDomains,technicalNotificationMails' -ErrorAction Stop
        $InitialTenantDomain = $OrganizationData.verifiedDomains | Where-Object isInitial -EQ $true | Select-Object -ExpandProperty name -First 1
        $PackagePath = $PackagePath.Replace("AzureADAssessmentData.zip", "AzureADAssessmentData-$InitialTenantDomain.zip")
        $OutputDirectoryAAD = Join-Path $OutputDirectoryData "AAD-$InitialTenantDomain"
        Assert-DirectoryExists $OutputDirectoryAAD

        ConvertTo-Json -InputObject $OrganizationData -Depth 10 | Set-Content (Join-Path $OutputDirectoryAAD "organization.json")

        ### Generate Assessment Data
        $AssessmentData = [PSCustomObject]@{
            AssessmentDateTime     = Get-Date
            AssessmentId           = if ($script:AppInsightsRuntimeState.OperationStack.Count -gt 0) { $script:AppInsightsRuntimeState.OperationStack.Peek().Id.ToString() } else { (New-Guid).ToString() }
            AssessmentVersion      = $MyInvocation.MyCommand.Module.Version.ToString()
            AssessmentTenantId     = $OrganizationData.id
            AssessmentTenantDomain = $InitialTenantDomain
        }
        Assert-DirectoryExists $OutputDirectoryData
        ConvertTo-Json -InputObject $AssessmentData | Set-Content $AssessmentDetailPath

        ### Licenses - 1
        Write-Progress -Id 0 -Activity ('Microsoft Azure AD Assessment Data Collection - {0}' -f $InitialTenantDomain) -Status 'Subscribed SKU' -PercentComplete 5
        Get-MsGraphResults "subscribedSkus" -Select "prepaidunits", "consumedunits", "skuPartNumber", "servicePlans" `
        | Export-JsonArray (Join-Path $OutputDirectoryAAD "subscribedSkus.json") -Depth 5 -Compress

        ### Conditional Access policies - 2
        Write-Progress -Id 0 -Activity ('Microsoft Azure AD Assessment Data Collection - {0}' -f $InitialTenantDomain) -Status 'Conditional Access Policies' -PercentComplete 10
        #Get-MsGraphResults "identity/conditionalAccess/policies" -ErrorAction Stop `
        Get-MsGraphResults "identity/conditionalAccess/policies" `
        | Add-AadReferencesToCache -Type conditionalAccessPolicy -ReferencedIdCache $ReferencedIdCache -PassThru `
        | Export-JsonArray (Join-Path $OutputDirectoryAAD "conditionalAccessPolicies.json") -Depth 5 -Compress

        ### Named location - 3
        Write-Progress -Id 0 -Activity ('Microsoft Azure AD Assessment Data Collection - {0}' -f $InitialTenantDomain) -Status 'Conditional Access Named locations' -PercentComplete 15
        Get-MsGraphResults "identity/conditionalAccess/namedLocations" `
        | Export-JsonArray (Join-Path $OutputDirectoryAAD "namedLocations.json") -Depth 5 -Compress

        ### EOTP Policy - 4
        Write-Progress -Id 0 -Activity ('Microsoft Azure AD Assessment Data Collection - {0}' -f $InitialTenantDomain) -Status 'Email Auth Method Policy' -PercentComplete 20
        Get-MsGraphResults "policies/authenticationMethodsPolicy/authenticationMethodConfigurations/email" `
        | ConvertTo-Json -Depth 5 -Compress | Set-Content -Path (Join-Path $OutputDirectoryAAD "emailOTPMethodPolicy.json")
        ### Directory Role Data - 5
        Write-Progress -Id 0 -Activity ('Microsoft Azure AD Assessment Data Collection - {0}' -f $InitialTenantDomain) -Status 'Directory Roles' -PercentComplete 21
        ## $expand on directoryRole members caps results at 20 members with no NextLink so call members endpoint for each.
        Get-MsGraphResults 'directoryRoles?$select=id,displayName,roleTemplateId' -DisableUniqueIdDeduplication `
        | Expand-MsGraphRelationship -ObjectType directoryRoles -PropertyName members -References `
        | Add-AadReferencesToCache -Type directoryRole -ReferencedIdCache $ReferencedIdCache -PassThru `
        | Export-Clixml -Path (Join-Path $OutputDirectoryAAD "directoryRoleData.xml")

        ### Directory Role Definitions - 6
        Write-Progress -Id 0 -Activity ('Microsoft Azure AD Assessment Data Collection - {0}' -f $InitialTenantDomain) -Status 'Directory Role Definitions' -PercentComplete 25
        Get-MsGraphResults 'roleManagement/directory/roleDefinitions' -Select 'id,templateId,displayName,isBuiltIn,isEnabled' -ApiVersion 'v1.0' -OutVariable roleDefinitions `
        | Where-Object { $_.isEnabled } `
        | Select-Object id, templateId, displayName, isBuiltIn, isEnabled `
        | Export-Csv (Join-Path $OutputDirectoryAAD "roleDefinitions.csv") -NoTypeInformation

        ### Directory Role Assignments - 7
        Write-Progress -Id 0 -Activity ('Microsoft Azure AD Assessment Data Collection - {0}' -f $InitialTenantDomain) -Status 'Directory Role Assignments' -PercentComplete 30
        ## Getting role assignments via unified role API
        # Get-MsGraphResults 'roleManagement/directory/roleAssignmentSchedules' -Select 'id,directoryScopeId,memberType,scheduleInfo,status,assignmentType' -Filter "status eq 'Provisioned' and assignmentType eq 'Assigned'" -QueryParameters @{ '$expand' = 'principal($select=id),roleDefinition($select=id,templateId,displayName)' } -ApiVersion 'beta' `
        # | Add-AadReferencesToCache -Type roleAssignmentSchedules -ReferencedIdCache $ReferencedIdCache -PassThru `
        # | Export-Clixml -Path (Join-Path $OutputDirectoryAAD "roleAssignmentSchedulesData.xml")

        # List roleAssignmentSchedules above is not returning non-root scoped assignments.
        # Working around with one query of all root assignments including custom roles and 
        # another query of all non-root assignments for build-in roles.
        # Because roleDefinitions are not returning the correct id, it is not possible to get custom roles assigned to non-root scopes.
        
        $roleAssignmentSchedules = Get-MsGraphResults 'roleManagement/directory/roleAssignmentSchedules' -Select 'id,directoryScopeId,memberType,scheduleInfo,status,assignmentType,roleDefinitionId' -Filter "status eq 'Provisioned' and assignmentType eq 'Assigned' and directoryScopeId eq '/'" -QueryParameters @{ '$expand' = 'principal($select=id),roleDefinition($select=id,templateId,displayName)' } -ApiVersion 'beta'
        $roleAssignmentSchedulesAdditional = $roleDefinitions | Where-Object isBuiltIn -EQ $true | Get-MsGraphResults 'roleManagement/directory/roleAssignmentSchedules' -Select 'id,directoryScopeId,memberType,scheduleInfo,status,assignmentType' -Filter "status eq 'Provisioned' and assignmentType eq 'Assigned' and roleDefinitionId eq '{0}' and directoryScopeId ne '/'" -QueryParameters @{ '$expand' = 'principal($select=id),roleDefinition($select=id,templateId,displayName)' } -ApiVersion 'beta'
        $roleAssignmentSchedules + $roleAssignmentSchedulesAdditional `
        | Add-AadReferencesToCache -Type roleAssignmentSchedules -ReferencedIdCache $ReferencedIdCache -PassThru `
        | Export-Clixml -Path (Join-Path $OutputDirectoryAAD "roleAssignmentSchedulesData.xml")
        Remove-Variable roleDefinitions, roleAssignmentSchedules, roleAssignmentSchedulesAdditional

        ### Directory Role Eligibility - 8
        Write-Progress -Id 0 -Activity ('Microsoft Azure AD Assessment Data Collection - {0}' -f $InitialTenantDomain) -Status 'Directory Role Eligibility' -PercentComplete 35
        # Getting role eligibility via unified role API
        Get-MsGraphResults 'roleManagement/directory/roleEligibilitySchedules' -Select 'id,directoryScopeId,memberType,scheduleInfo,status' -Filter "status eq 'Provisioned'" -QueryParameters @{ '$expand' = 'principal($select=id),roleDefinition($select=id,templateId,displayName)' } -ApiVersion 'beta' `
        | Add-AadReferencesToCache -Type roleAssignmentSchedules -ReferencedIdCache $ReferencedIdCache -PassThru `
        | Export-Clixml -Path (Join-Path $OutputDirectoryAAD "roleEligibilitySchedulesData.xml")
        #| Export-JsonArray (Join-Path $OutputDirectoryAAD "roleEligibilitySchedules.json") -Depth 5 -Compress

        # Lookup ObjectIds with Unknown Types
        $ReferencedIdCache.unknownType | Get-MsGraphResults 'directoryObjects' -Select 'id' `
        | ForEach-Object {
            $ObjectType = $_.'@odata.type' -replace '#microsoft.graph.', ''
            [void] $ReferencedIdCache.$ObjectType.Add($_.id)
        }
        $ReferencedIdCache.unknownType.Clear()

        ### Application Data - 9
        Write-Progress -Id 0 -Activity ('Microsoft Azure AD Assessment Data Collection - {0}' -f $InitialTenantDomain) -Status 'Applications' -PercentComplete 40
        Get-MsGraphResults 'applications?$select=id,appId,displayName,appRoles,keyCredentials,passwordCredentials' -Top 999 -ApiVersion 'beta' `
        | Where-Object { $_.keyCredentials.Count -or $_.passwordCredentials.Count -or $ReferencedIdCache.application.Contains($_.id) -or $ReferencedIdCache.appId.Contains($_.appId) } `
        | Export-Clixml -Path (Join-Path $OutputDirectoryAAD "applicationData.xml")

        ### Service Principal Data - 10
        Write-Progress -Id 0 -Activity ('Microsoft Azure AD Assessment Data Collection - {0}' -f $InitialTenantDomain) -Status 'Service Principals' -PercentComplete 45
        ## Option 1: Get servicePrincipal objects without appRoleAssignments. Get appRoleAssignments
        # $servicePrincipalsCount = Get-MsGraphResults 'servicePrincipals/$count' `
        # ## Although much more performant, $expand on servicePrincipal appRoleAssignedTo appears to miss certain appRoleAssignments.
        # Get-MsGraphResults 'servicePrincipals?$select=id,appId,servicePrincipalType,displayName,accountEnabled,appOwnerOrganizationId,appRoles,oauth2PermissionScopes,keyCredentials,passwordCredentials' -Top 999 `
        # | Export-Clixml -Path (Join-Path $OutputDirectoryAAD "servicePrincipalData.xml")
        ## Option 2: Expand appRoleAssignedTo when retrieving servicePrincipal object. This is at least 50x faster but appears to miss some appRoleAssignments.
        $listAppRoleAssignments = New-Object 'System.Collections.Generic.List[psobject]'
        Get-MsGraphResults 'servicePrincipals?$select=id,appId,servicePrincipalType,displayName,accountEnabled,appOwnerOrganizationId,appRoles,oauth2PermissionScopes,keyCredentials,passwordCredentials&$expand=appRoleAssignedTo' -Top 999 -ApiVersion 'beta' `
        | Extract-AppRoleAssignments -ListVariable $listAppRoleAssignments -PassThru `
        | Select-Object -Property "*" -ExcludeProperty 'appRoleAssignedTo', 'appRoleAssignedTo@odata.context' `
        | Export-Clixml -Path (Join-Path $OutputDirectoryAAD "servicePrincipalData.xml")

        ### App Role Assignments Data - 11
        Write-Progress -Id 0 -Activity ('Microsoft Azure AD Assessment Data Collection - {0}' -f $InitialTenantDomain) -Status 'App Role Assignments' -PercentComplete 50
        ## Option 1: Loop through all servicePrincipals to get appRoleAssignments
        # Import-Clixml -Path (Join-Path $OutputDirectoryAAD "servicePrincipalData.xml") `
        # | Get-MsGraphResults 'servicePrincipals/{0}/appRoleAssignedTo' -Top 999 -TotalRequests $servicePrincipalsCount -DisableUniqueIdDeduplication `
        # | Add-AadReferencesToCache -Type appRoleAssignment -ReferencedIdCache $ReferencedIdCache -PassThru `
        # | Export-Clixml -Path (Join-Path $OutputDirectoryAAD "appRoleAssignmentData.xml")
        ## Option 2: Use expanded appRoleAssignedTo from servicePrincipals. This is at least 50x faster but appears to miss some appRoleAssignments.
        $listAppRoleAssignments `
        | Add-AadReferencesToCache -Type appRoleAssignment -ReferencedIdCache $ReferencedIdCache -PassThru `
        | Export-Clixml -Path (Join-Path $OutputDirectoryAAD "appRoleAssignmentData.xml")
        Remove-Variable listAppRoleAssignments

        ### OAuth2 Permission Grants Data - 12
        Write-Progress -Id 0 -Activity ('Microsoft Azure AD Assessment Data Collection - {0}' -f $InitialTenantDomain) -Status 'OAuth2 Permission Grants' -PercentComplete 55
        ## https://graph.microsoft.com/v1.0/oauth2PermissionGrants fails with "Service is temorarily unavailable" if too much data is returned in a single request. 600 works on microsoft.onmicrosoft.com.
        Get-MsGraphResults 'oauth2PermissionGrants' -Top 600 `
        | Add-AadReferencesToCache -Type oauth2PermissionGrant -ReferencedIdCache $ReferencedIdCache -PassThru `
        | Export-Clixml -Path (Join-Path $OutputDirectoryAAD "oauth2PermissionGrantData.xml")

        ### Filter Service Principals - 13
        Write-Progress -Id 0 -Activity ('Microsoft Azure AD Assessment Data Collection - {0}' -f $InitialTenantDomain) -Status 'Filtering Service Principals' -PercentComplete 60
        Remove-Item (Join-Path $OutputDirectoryAAD "servicePrincipalData-Unfiltered.xml") -ErrorAction Ignore
        Rename-Item (Join-Path $OutputDirectoryAAD "servicePrincipalData.xml") -NewName "servicePrincipalData-Unfiltered.xml"
        Import-Clixml -Path (Join-Path $OutputDirectoryAAD "servicePrincipalData-Unfiltered.xml") `
        | Where-Object { $_.keyCredentials.Count -or $_.passwordCredentials.Count -or $ReferencedIdCache.servicePrincipal.Contains($_.id) -or $ReferencedIdCache.appId.Contains($_.appId) } `
        | Export-Clixml -Path (Join-Path $OutputDirectoryAAD "servicePrincipalData.xml")
        Remove-Item (Join-Path $OutputDirectoryAAD "servicePrincipalData-Unfiltered.xml") -Force
        $ReferencedIdCache.servicePrincipal.Clear()

        ### Administrative units data - 14
        Write-Progress -Id 0 -Activity ('Microsoft Azure AD Assessment Data Collection - {0}' -f $InitialTenantDomain) -Status 'Administrative Units' -PercentComplete 65
        Get-MsGraphResults 'directory/administrativeUnits' -Select 'id,displayName,visibility' `
        | Export-Csv (Join-Path $OutputDirectoryAAD "administrativeUnits.csv")

        ### Registration details data - 15
        Write-Progress -Id 0 -Activity ('Microsoft Azure AD Assessment Data Collection - {0}' -f $InitialTenantDomain) -Status 'Registration Details' -PercentComplete 70
        Get-MsGraphResults 'reports/authenticationMethods/userRegistrationDetails' -ApiVersion 'beta' `
        | Export-JsonArray (Join-Path $OutputDirectoryAAD "userRegistrationDetails.json") -Depth 5 -Compress

        ### Group Data - 16
        Write-Progress -Id 0 -Activity ('Microsoft Azure AD Assessment Data Collection - {0}' -f $InitialTenantDomain) -Status 'Groups' -PercentComplete 75
        # add technical notifications groups
        if ($OrganizationData) {
            $OrganizationData.technicalNotificationMails | Get-MsGraphResults 'groups?$select=id' -Filter "proxyAddresses/any(c:c eq 'smtp:{0}')" `
            | ForEach-Object { [void]$ReferencedIdCache.group.Add($_.id) }
        }
        # Add nested groups
        if (($ReferencedIdCache.PSobject.Properties | ForEach-Object {$_.Name}) -contains 'roleGroup.guid'){

            $ReferencedIdCache.roleGroup.guid | Get-MsGraphResults 'groups/{0}/transitiveMembers/microsoft.graph.group?$count=true&$select=id' -Top 999 -TotalRequests $ReferencedIdCache.roleGroup.Count -DisableUniqueIdDeduplication `
            | ForEach-Object { [void]$ReferencedIdCache.group.Add($_.id) }

        }
        
        ## Option 1: Populate direct members on groups (including nested groups) and calculate transitiveMembers later.
        ## $expand on group members caps results at 20 members with no NextLink so call members endpoint for each.
        $ReferencedIdCache.group | Get-MsGraphResults 'groups?$select=id,groupTypes,displayName,mail,proxyAddresses,mailEnabled,securityEnabled,onPremisesSyncEnabled' -TotalRequests $ReferencedIdCache.group.Count -DisableUniqueIdDeduplication -BatchSize 1 -GetByIdsBatchSize 20 `
        | Expand-MsGraphRelationship -ObjectType groups -PropertyName members -References -Top 999 `
        | Add-AadReferencesToCache -Type group -ReferencedIdCache $ReferencedIdCache -ReferencedTypes '#microsoft.graph.user', '#microsoft.graph.servicePrincipal' -PassThru `
        | Select-Object -Property "*" -ExcludeProperty '@odata.type' `
        | Export-Clixml -Path (Join-Path $OutputDirectoryAAD "groupData.xml")

        # | ForEach-Object {
        #     foreach ($Object in $_.member) {
        #         if ($Object.'@odata.type' -in ('#microsoft.graph.user', '#microsoft.graph.servicePrincipal')) {
        #             $ObjectType = $Object.'@odata.type' -replace '#microsoft.graph.', ''
        #             [void] $ReferencedIdCache.$ObjectType.Add($Object.id)
        #         }
        #     }
        # }

        ## Option 2: Get groups without member data and let Azure AD calculate transitiveMembers.
        # $ReferencedIdCache.group | Get-MsGraphResults 'groups?$select=id,groupTypes,displayName,mail,proxyAddresses,mailEnabled,securityEnabled' -TotalRequests $ReferencedIdCache.group.Count -DisableUniqueIdDeduplication `
        # | Select-Object -Property "*" -ExcludeProperty '@odata.type' `
        # | Export-Clixml -Path (Join-Path $OutputDirectoryAAD "groupData.xml")

        # ### Group Transitive members - 16
        # Write-Progress -Id 0 -Activity ('Microsoft Azure AD Assessment Data Collection - {0}' -f $InitialTenantDomain) -Status 'Group Transitive Membership' -PercentComplete 75
        # $ReferencedIdCache.group | Get-MsGraphResults 'groups/{0}/transitiveMembers/$ref' -Top 999 -TotalRequests $ReferencedIdCache.group.Count -IncapsulateReferenceListInParentObject -DisableUniqueIdDeduplication `
        # | ForEach-Object {
        #     $group = $_
        #     #[array] $directMembers = Get-MsGraphResults 'groups/{0}/members/$ref' -UniqueId $_.id -Top 999 -DisableUniqueIdDeduplication | Expand-ODataId | Select-Object -ExpandProperty id
        #     $group.transitiveMembers | Expand-ODataId | ForEach-Object {
        #         if ($_.'@odata.type' -eq '#microsoft.graph.user') { [void]$ReferencedIdCache.user.Add($_.id) }
        #         [PSCustomObject]@{
        #             id         = $group.id
        #             #'@odata.type' = $group.'@odata.type'
        #             memberId   = $_.id
        #             memberType = $_.'@odata.type' -replace '#microsoft.graph.', ''
        #             #direct     = $directMembers -and $directMembers.Contains($_.id)
        #         }
        #     }
        # } `
        # | Export-Csv (Join-Path $OutputDirectoryAAD "groupTransitiveMembers.csv") -NoTypeInformation
        $ReferencedIdCache.group.Clear()

        ### User Data - 17
        Write-Progress -Id 0 -Activity ('Microsoft Azure AD Assessment Data Collection - {0}' -f $InitialTenantDomain) -Status 'Users' -PercentComplete 80
        # add technical notifications users
        if ($OrganizationData) {
            $OrganizationData.technicalNotificationMails | Get-MsGraphResults 'users?$select=id' -Filter "proxyAddresses/any(c:c eq 'smtp:{0}') or otherMails/any(c:c eq '{0}')" `
            | ForEach-Object { [void]$ReferencedIdCache.user.Add($_.id) }
        }
        # get user information
        #$ReferencedIdCache.user | Get-MsGraphResults 'users/{0}?$select=id,userPrincipalName,userType,displayName,accountEnabled,onPremisesSyncEnabled,onPremisesImmutableId,mail,otherMails,proxyAddresses,assignedPlans,signInActivity' -TotalRequests $ReferencedIdCache.user.Count -DisableUniqueIdDeduplication -ApiVersion 'beta' `
        $userQuery = 'users/{0}?$select=id,userPrincipalName,userType,displayName,accountEnabled,onPremisesSyncEnabled,onPremisesImmutableId,mail,otherMails,proxyAddresses'
        if (!$NoAssignedPlans) {
            $userQuery += ",assignedPlans"
        }
        $ReferencedIdCache.user | Get-MsGraphResults $userQuery -TotalRequests $ReferencedIdCache.user.Count -DisableUniqueIdDeduplication -ApiVersion 'beta' `
        | Select-Object -Property "*" -ExcludeProperty '@odata.type' `
        | Export-Clixml -Path (Join-Path $OutputDirectoryAAD "userData.xml")
        $ReferencedIdCache.user.Clear()

        ### Generate Reports
        if (!$SkipReportOutput) {
            Write-Progress -Id 0 -Activity ('Microsoft Azure AD Assessment Data Collection - {0}' -f $InitialTenantDomain) -Status 'Output Report Data' -PercentComplete 85
            Export-AADAssessmentReportData -SourceDirectory $OutputDirectoryAAD -Force

            ## Remove Raw Data Output
            Remove-Item -Path (Join-Path $OutputDirectoryAAD "*") -Include "*Data.xml" -ErrorAction Ignore
            Remove-Item -Path (Join-Path $OutputDirectoryAAD "*") -Include "*Data.csv" -ErrorAction Ignore
        }

        ### Complete
        Write-Progress -Id 0 -Activity ('Microsoft Azure AD Assessment Data Collection - {0}' -f $InitialTenantDomain) -Completed

        ### Write Custom Event
        Write-AppInsightsEvent 'AAD Assessment Data Collection Complete' -OverrideProperties -Properties @{
            AssessmentId       = $AssessmentData.AssessmentId
            AssessmentVersion  = $MyInvocation.MyCommand.Module.Version.ToString()
            AssessmentTenantId = $OrganizationData.id
        }

        if (!$SkipPackaging) {
            ### Package Output
            Compress-Archive (Join-Path $OutputDirectoryData '\*') -DestinationPath $PackagePath -Force -ErrorAction Stop

            ### Clean-Up Data Files
            Remove-Item $OutputDirectoryData -Recurse -Force
        }

        ### Open Directory
        Invoke-Item $OutputDirectory

    }
    catch { if ($MyInvocation.CommandOrigin -eq 'Runspace') { Write-AppInsightsException $_.Exception }; throw }
    finally { Complete-AppInsightsRequest $MyInvocation.MyCommand.Name -Success $? }
}

# SIG # Begin signature block
# MIInrQYJKoZIhvcNAQcCoIInnjCCJ5oCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAUsqvAas0Yhkxg
# Xfh8V1Osfu993bv2F+NxH2+T3rqO7KCCDYEwggX/MIID56ADAgECAhMzAAACUosz
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
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZgjCCGX4CAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAlKLM6r4lfM52wAAAAACUjAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgxg903UbH
# 9A1GWxkr1AesheVjjXdwYPh/iMZrDyt69LIwQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQAeEWr5I9+91pAEiCLTFCFEZMTJW45PF+ccgtCXrrhD
# Nn648qJGy/+kWJKUr3hgY8bRN1adUuK5aG7zw2oCM6R0apLqTD4VFAoq4Kk0z4vn
# AQ58yfN0zL6n1P2YxqkdSvMKQbCU2wH1RnJx2b38OWC/OMaiVl1xzUbThPiph9s2
# uoxQf22ONDg0NJ0/fjnoImC12XwaY1v9yqfArV/zoCsXmL8eeOWkUvNdDvE4++CM
# fCvOVQx8Z0cmlY6/cDMcY1h0dthEz7kMYGfrdO0WFEzxvcJW/1fubO1wlXIe6krf
# uRUWN4how6tegv0LHYwOOp2gqDr6mPdQj6TUXxV1KnFdoYIXDDCCFwgGCisGAQQB
# gjcDAwExghb4MIIW9AYJKoZIhvcNAQcCoIIW5TCCFuECAQMxDzANBglghkgBZQME
# AgEFADCCAVUGCyqGSIb3DQEJEAEEoIIBRASCAUAwggE8AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEINwjl5SpFJN+P/zTv7i5cVRi3v7fzXft+si2Nsvp
# 48SlAgZihNyWOowYEzIwMjIwNTE5MjEwNDMwLjE1OFowBIACAfSggdSkgdEwgc4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1p
# Y3Jvc29mdCBPcGVyYXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMg
# VFNTIEVTTjo3ODgwLUUzOTAtODAxNDElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgU2VydmljZaCCEV8wggcQMIIE+KADAgECAhMzAAABqFXwYanMMBhcAAEA
# AAGoMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# MB4XDTIyMDMwMjE4NTEyM1oXDTIzMDUxMTE4NTEyM1owgc4xCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVy
# YXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjo3ODgw
# LUUzOTAtODAxNDElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vydmlj
# ZTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAKPabcrALiXX8pjyXpcM
# N89KTvcmlAiDw4pU+HejZhibUeo/HUy+P9VxWhCX7ogeeKPJ677+LeVdPdG5hTvG
# DgSuo3w+AcmzcXZ2QCGUgUReLUKbmrr06bB0xhvtZwoelhxtPkjJFsbTGtSt+V7E
# 4VCjPdYqQZ/iN0ArXXmgbEfVyCwS+h2uooBhM5UcbPogtr5VpgdzbUM4/rWupmFV
# jPB1asn3+wv7aBCK8j9QUJroY4y1pmZSf0SuGMWY7cm2cvrbdm7XldljqRdHW+CQ
# AB4EqiOqgumfR+aSpo5T75KG0+nsBkjlGSsU1Bi15p4rP88pZnSop73Gem9GWO2G
# RLwP15YEnKsczxhGY+Z8NEa0QwMMiVlksdPU7J5qK9gxAQjOJzqISJzhIwQWtELq
# gJoHwkqTxem3grY7B7DOzQTnQpKWoL0HWR9KqIvaC7i9XlPv+ue89j9e7fmB4nh1
# hulzEJzX6RMU9THJMlbO6OrP3NNEKJW8jipCny8H1fuvSuFfuB7t++KK9g2c2NKu
# 5EzSs1nKNqtl4KO3UzyXLWvTRDO4D5PVQOda0tqjS/AWoUrxKC5ZPlkLE+YPsS5G
# +E/VCgCaghPyBZsHNK7wHlSf/26uhLnKp6XRAIroiEYl/5yW0mShjvnARPr0GIlS
# m0KrqSwCjR5ckWT1sKaEb8w3AgMBAAGjggE2MIIBMjAdBgNVHQ4EFgQUNsfb4+L4
# UutlNh/MxjGkj0kLItUwHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIw
# XwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
# cy9jcmwvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3Js
# MGwGCCsGAQUFBwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENB
# JTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcD
# CDANBgkqhkiG9w0BAQsFAAOCAgEAcTuCS2Rqqmf2mPr6OUydhmUx+m6vpEPszWio
# JXbnsRbny62nF9YXTKuSNWH1QFfyc/2N3YTEp4hE8YthYKgDM/HUhUREX3WTwGse
# YuuDeSxWRJWCorAHF1kwQzIKgrUc3G+uVwAmG/EI1ELRExA4ftx0Ehrf59aJm7On
# gn0lTSSiKUeuGA+My6oCi/V8ETxz+eblvQANaltJgGfppuWXYT4jisQKETvoJjBv
# 5x+BA0oEFu7gGaeMDkZjnO5vdf6HeKneILs9ZvwIWkgYQi2ZeozbxglG5YwExoix
# ekxrRTDZwMokIYxXmccscQ0xXmh+I3vo7hV9ZMKTa9Paz5ne4cc8Odw1T+624mB0
# WaW9HAE1hojB6CbfundtV/jwxmdKh15plJXnN1yM7OL924HqAiJisHanpOEJ4Um9
# b3hFUXE2uEJL9aYuIgksVYIq1P29rR4X7lz3uEJH6COkoE6+UcauN6JYFghN9I8J
# RBWAhHX4GQHlngsdftWLLiDZMynlgRCZzkYI24N9cx+D367YwclqNY6CZuAgzwy1
# 2uRYFQasYHYK1hpzyTtuI/A2B8cG+HM6X1jf2d9uARwH6+hLkPtt3/5NBlLXpOl5
# iZyRlBi7iDXkWNa3juGfLAJ3ISDyNh7yu+H4yQYyRs/MVrCkWUJs9EivLKsNJ2B/
# IjNrStYwggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3
# DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIw
# MAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAx
# MDAeFw0yMTA5MzAxODIyMjVaFw0zMDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
# 5OGmTOe0ciELeaLL1yR5vQ7VgtP97pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/
# XE/HZveVU3Fa4n5KWv64NmeFRiMMtY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1
# hlDcwUTIcVxRMTegCjhuje3XD9gmU3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7
# M62AW36MEBydUv626GIl3GoPz130/o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3K
# Ni1wjjHINSi947SHJMPgyY9+tVSP3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy
# 1cCGMFxPLOJiss254o2I5JasAUq7vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF80
# 3RKJ1v2lIH1+/NmeRd+2ci/bfV+AutuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQc
# NIIP8BDyt0cY7afomXw/TNuvXsLz1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahha
# YQFzymeiXtcodgLiMxhy16cg8ML6EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkL
# iWHzNgY1GIRH29wb0f2y1BzFa/ZcUlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV
# 2xo3xwgVGD94q0W29R6HXtqPnhZyacaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIG
# CSsGAQQBgjcVAQQFAgMBAAEwIwYJKwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUp
# zxD/LwTuMB0GA1UdDgQWBBSfpxVdAF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBT
# MFEGDCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYI
# KwYBBQUHAwgwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGG
# MA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186a
# GMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3Br
# aS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsG
# AQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcN
# AQELBQADggIBAJ1VffwqreEsH2cBMSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1
# OdfCcTY/2mRsfNB1OW27DzHkwo/7bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYA
# A7AFvonoaeC6Ce5732pvvinLbtg/SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbz
# aN9l9qRWqveVtihVJ9AkvUCgvxm2EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6L
# GYnn8AtqgcKBGUIZUnWKNsIdw2FzLixre24/LAl4FOmRsqlb30mjdAy87JGA0j3m
# Sj5mO0+7hvoyGtmW9I/2kQH2zsZ0/fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0
# SCyxTkctwRQEcb9k+SS+c23Kjgm9swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxko
# JLo4S5pu+yFUa2pFEUep8beuyOiJXk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFm
# PWn9y8FBSX5+k77L+DvktxW/tM4+pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC482
# 2rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7
# vzhwRNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIC0jCC
# AjsCAQEwgfyhgdSkgdEwgc4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1ZXJ0byBSaWNv
# MSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjo3ODgwLUUzOTAtODAxNDElMCMGA1UE
# AxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUA
# bLr8xJ9BB4rL4Yg58X1LZ5iQdyyggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMDANBgkqhkiG9w0BAQUFAAIFAOYwrIwwIhgPMjAyMjA1MTkxNTQ2
# MjBaGA8yMDIyMDUyMDE1NDYyMFowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA5jCs
# jAIBADAKAgEAAgIOBgIB/zAHAgEAAgIRnDAKAgUA5jH+DAIBADA2BgorBgEEAYRZ
# CgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0G
# CSqGSIb3DQEBBQUAA4GBALuCtScTJ7kjRw8fM0afmES0RINe+MMWRh2pNjArjHi+
# OGl1NIlOnEMCLwKoQeeP+SihsMLkeJJYiEayOYy98FzI7+wsrluF9jibbXqkRQ01
# q9iV4TCVdiuvC1XQ55cpNOLKsdSzDtYXr9epe6MDZ5YI4tG2nj0XXzfOt1WdmhrT
# MYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMA
# AAGoVfBhqcwwGFwAAQAAAagwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJ
# AzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgIYNxI/9sRSN/b9cYClbu
# 8DUU8X5GIHVqPZkcgpneBlIwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCB0
# /ssdAMsHwnNwhfFBXPlFnRvWhHqSX9YLUxBDl1xlpjCBmDCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABqFXwYanMMBhcAAEAAAGoMCIEIMCC
# L4k/gQdSyD+LMxBCyZ9GP5UBS2nMN0DBWVgDpAjSMA0GCSqGSIb3DQEBCwUABIIC
# ADsXZbjV1ou71+cMZYcrWNMMjBOd3fGFnooESAMPolmDM6B83ICTtJpURc90G2S8
# 9ChX4G46RRJCZMK+bX8+hf60mVDNJ5cfiK/+kSrE0UBdeTB/YvZeOWJtDVXFwZRT
# MMtiKKxQpEozLRIklyFE9Cm+I0OG/PGAKzwQKHDKLrY86VymMNkmwAVSj4e+tFN+
# 9aF2Z3mj8smIgrAXZq+mdoqywl6zrxs4sO04E6aUdMKQ6t0jj5xw/QrEpWAgfaI1
# sA5MACBFqr5iRsVyKO0OY5kvpEutdB8wnyPFnttbsbmeSuKW5Ui0dsEAQQWSfW4X
# 1aGe+9bHfzYhJu5zi/VdLhhQXSLBvkVT5PA4t8qj0FsIwRaG7gytbeXlVQnrrmwa
# EzQZIU44iuV8RLaMsqrtum4HvZsmDJOxlTQasjgo43U3nsM5vV2a53bpkZBqf6UZ
# 23nOo+fkLs+wzLqdKVQ8uBh3Vh/pexXu4X2s4h9px8xiKgf7Nkk/ApEoS/xDn6HJ
# eQu3TXEZLQ4LBIIiu7ls2FjiMvBhCpg3fu7lN29iVD1qlR4Lgv28P+jiFSxDIEo8
# rzfeMIpdFxy73PPGbljqxdp1O4GGkqlfsbS8ozl2dmUYmiviWxMbSv35p2PxglwX
# bOFC4CYnLmbaUQtAxvMPvSJx24f7xhXwfvC8zYcSde9q
# SIG # End signature block
