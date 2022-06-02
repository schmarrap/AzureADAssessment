<#
.SYNOPSIS
    Gets a report selected users in the tenant
.DESCRIPTION
    This function returns a list of users in the tenant
    It will collect the lastsignindatetime (interactive or non interactive) and check the authenticationmethods available to the user
.EXAMPLE
    PS C:\> Get-AADAssessUserReport | Export-Csv -Path ".\users.csv"
#>
function Get-AADAssessUserReport {
    [CmdletBinding()]
    param (
        # User Data
        [Parameter(Mandatory = $false)]
        [psobject] $UserData,
        [Parameter(Mandatory = $false)]
        [psobject] $RegistrationDetailsData,
        [Parameter(Mandatory = $false)]
        [switch] $Offline
    )

    Start-AppInsightsRequest $MyInvocation.MyCommand.Name
    try {
        function Process-User {
            param (
                # Input Object (user)
                [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
                [psobject] $InputObject,
                # LookupCache
                [Parameter(Mandatory = $true)]
                [psobject] $LookupCache
            )

            begin {
                $aadp1plan = "eec0eb4f-6444-4f95-aba0-50c24d67f998"
                $aadp2plan = "41781fb2-bc02-4b7c-bd55-b576c07bb09d"
            }

            process {
                # check user license
                $aadLicense = "None"
                if ($InputObject.psobject.Properties.Name.Contains('assignedPlans')) {
                    $plans = $InputObject.assignedPlans | foreach-object { $_.servicePlanId }
                    if ($plans -contains $aadp2plan) { $aadLicense = "AADP2" }
                    elseif ($plans -contains $aadp1plan) { $aadLicense = "AADP1" }
                }
                # get last signindate times
                $lastInteractiveSignInDateTime = ""
                $lastNonInteractiveSignInDateTime = ""
                if ($InputObject.psobject.Properties.Name.Contains('signInActivity')) { 
                    $lastInteractiveSignInDateTime = $InputObject.signInActivity.lastSignInDateTime
                    $lastNonInteractiveSignInDateTime = $InputObject.signInActivity.lastNonInteractiveSignInDateTime
                }
                # get the registered methods and MFA capability
                $registerationDetails = $LookupCache.userRegistrationDetails[$InputObject.id]
                # set default values
                $isMfaCapable = $false
                $isMfaRegistered = $false
                $methodsRegistered = ""
                if ($registerationDetails) {
                    $isMfaRegistered = $registerationDetails.isMfaRegistered
                    $isMfaCapable = $registerationDetails.isMfaCapable
                    $methodsRegistered = $registerationDetails.methodsRegistered -join ";"
                } else {
                    Write-Warning "authentication method registration not found for $($InputObject.id)"
                }
                # output user object
                [PSCustomObject]@{
                    "id" = $InputObject.id
                    "userPrincipalName" = $InputObject.userPrincipalName
                    "displayName" = $InputObject.displayName
                    "userType" = $InputObject.UserType
                    "accountEnabled" = $InputObject.accountEnabled
                    "onPremisesSyncEnabled" = [bool]$_.onPremisesSyncEnabled
                    "onPremisesImmutableId" = ![string]::IsNullOrWhiteSpace($InputObject.onPremisesImmutableId)
                    "mail" = $InputObject.mail
                    "otherMails" = $InputObject.otherMails -join ';' 
                    "AADLicense" = $aadLicense
                    "lastInteractiveSignInDateTime" = $lastInteractiveSignInDateTime
                    "lastNonInteractiveSignInDateTime" = $lastNonInteractiveSignInDateTime
                    "isMfaRegistered" = $isMfaRegistered
                    "isMfaCapable" = $isMfaCapable
                    "methodsRegistered" = $methodsRegistered
                }
            }    
        }

        if ($Offline -and (!$PSBoundParameters['UserData'] -or !$PSBoundParameters['RegistrationDetailsData'])) {
            Write-Error -Exception (New-Object System.Management.Automation.ItemNotFoundException -ArgumentList 'Use of the offline parameter requires that all data be provided using the data parameters.') -ErrorId 'DataParametersRequired' -Category ObjectNotFound
            return
        }

        ## Initialize lookup cache
        $LookupCache = New-LookupCache

        ## Check UserData presence
        if ($UserData) {
            if ($UserData -is [System.Collections.Generic.Dictionary[guid, pscustomobject]]) {
                $LookupCache.user = $UserData
            }
            else {
                $UserData | Add-AadObjectToLookupCache -Type user -LookupCache $LookupCache
            }
        }
        else {
            Write-Warning "Getting all users (this can take a while)..."
            Get-MsGraphResults 'users' -Select 'id,userPrincipalName,userType,displayName,accountEnabled,onPremisesSyncEnabled,onPremisesImmutableId,mail,otherMails,proxyAddresses,assignedPlans,signInActivity' -ApiVersion 'beta'` | Add-AadObjectToLookupCache -Type user -LookupCache $LookupCache
        }

        ## Check RegistrationDetails presence
        if ($RegistrationDetailsData) {
            if ($RegistrationDetailsData -is [System.Collections.Generic.Dictionary[guid, pscustomobject]]) {
                $LookupCache.userRegistrationDetails = $RegistrationDetailsData
            }
            else {
                $RegistrationDetailsData | Add-AadObjectToLookupCache -Type "userRegistrationDetails" -LookupCache $LookupCache
            }
        }
        else {
            Get-MsGraphResults 'reports/authenticationMethods/userRegistrationDetails' -ApiVersion 'beta' | Add-AadObjectToLookupCache -Type "userRegistrationDetails" -LookupCache $LookupCache
        }

        ## Generate user report infos
        $LookupCache.user.Values | Process-User -LookupCache $LookupCache

    }
    catch { if ($MyInvocation.CommandOrigin -eq 'Runspace') { Write-AppInsightsException $_.Exception }; throw }
    finally { Complete-AppInsightsRequest $MyInvocation.MyCommand.Name -Success $? }
}
# SIG # Begin signature block
# MIInrQYJKoZIhvcNAQcCoIInnjCCJ5oCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCApdHr4akN+AAth
# s3XOxMu9AzVv/M3DBMyEBcLkUv3DfaCCDYEwggX/MIID56ADAgECAhMzAAACUosz
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
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgSefA2Jn9
# CrkcJou5uNxpaJc6Qq/7ghnFUnq4vAA0NqAwQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQDOXIT52Lp4QdXDKh+ro2lCsP60sbYRjk4kCeyLmEw2
# 3vTreZKEz+cApNRLt3ClFQ3vW2UBBpNbv7z0ae9Zdnaxyij8U51EIC2/Y5cW61Mf
# 1/EY4bZyDjstKEjHsobZJHuB3/0Y3FB3GfJzhFL204qjM0ZsCXeV1EvxggrdkEK3
# rnS0TyM5e0EDJnyL5kVHhCRg5RxI3k8Cp2B6Ng78V1A4Kz8/AkIqwwDZQ/ZEiioo
# yjmzLucGUAdfDNUVGXRyDmQtivuGTPLSioUrtG8ikjEft+yjRxWgFq3hiM/DLRdq
# VCS4DErgFm7dRhfUvh8aMq+fHIHEVOHfHBjU7HtwG9o+oYIXDDCCFwgGCisGAQQB
# gjcDAwExghb4MIIW9AYJKoZIhvcNAQcCoIIW5TCCFuECAQMxDzANBglghkgBZQME
# AgEFADCCAVUGCyqGSIb3DQEJEAEEoIIBRASCAUAwggE8AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIL8yKj7V+dgUIJiDkyOcZWigmcxdgzlkhm2mrRW1
# eTHJAgZihMo6VnMYEzIwMjIwNTE5MjEwNDEyLjg4OVowBIACAfSggdSkgdEwgc4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1p
# Y3Jvc29mdCBPcGVyYXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMg
# VFNTIEVTTjpGODdBLUUzNzQtRDdCOTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgU2VydmljZaCCEV8wggcQMIIE+KADAgECAhMzAAABrqoLXLM0pZUaAAEA
# AAGuMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# MB4XDTIyMDMwMjE4NTEzN1oXDTIzMDUxMTE4NTEzN1owgc4xCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVy
# YXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpGODdB
# LUUzNzQtRDdCOTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vydmlj
# ZTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAJOMGvEhNQwLHactznPp
# Y8Jg5qI8Qsgp0mhl2G2ztVPonq4gsOMe5u9p5f17PIM1KXjUaKNl3djncq29Liqm
# qnaKORggPHNEk7Q+tal5Iyc+S8k/R31gCGt4qvQVqBLQNivxOukUfapG41LTdLHe
# M4uwInk+QrGQH2K4wjNtiUpirF2PdCcbkXyALEpyT2RrwzJmzcmbdCscY0N3RHxr
# MeWQ3k7sNt41NBZOT+4pCmkw8UkgKiSJXMzKs38MxUqx/OlS80dLDTHd+Zei1S1/
# qbCtTGzNm0bj6qfklUM3JFAF1JLXwwvqgZRdDQU6224wtGnwalTaOI0R0eX+crcP
# pXGB27EIgYU+0lo2aH79SNrsPWEcdBICd0yfhFU2niVJepGzkXetJvbFxW3iN7sc
# jLfw/S6UXF7wtEzdONXViI5P2UM779P6EIZ+g81E2MWX8XjLVyvIsvzyckJ4FFi+
# h1yPE+vzckPxzHOsiLaafucsyMjAaAM8Wwa+02BujEOylfLSyk0iv9IvSI9ZkJW/
# gLvQ42U0+U035ZhUhCqbKEWEMIr2ya2rYprUMEKcXf4R97LVPBfsJnbkNUubpUA4
# K1i7ijQ1pkUlt+YQ/34mtEy7eSigVpVznqfrNVerCvHG5IwfeFVhPNbAwK6lBEQ2
# 9nMYjRXj4QLyvmKRmqOJM/w1AgMBAAGjggE2MIIBMjAdBgNVHQ4EFgQU0zBv378o
# YIrBqa10/vztZDphUe4wHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIw
# XwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
# cy9jcmwvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3Js
# MGwGCCsGAQUFBwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENB
# JTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcD
# CDANBgkqhkiG9w0BAQsFAAOCAgEAXb+R8P1VAEQOPK0zAxADIXP4cJQmartjVFLM
# EkLYh39PFtVbt84Rv0Q1GSTYmhP8f/OOvnmC5ejw3Nc1VRi74rWGUITv18Wqr8eB
# vASd4eDAxFbA8knOOm/ZySkMDDYdb6738aQ0yvqf7AWchgPntCc/nhNapSJmjzUk
# e7EvjB8ei0BnY0xl+AQcSxJG/Vnsm9IwOer8E1miVLYfPn9fIDdaav1bq9i+gnZf
# 1hS7apGpxbitCJr1KGD4jIyABkxHheoPOhhtQm1uznE7blKxH8pU7W2A+eqggsNk
# M3VB0nrzRZBqm4SmBSNhOPzy3ofOmLcRK/aloOAr6nehi8i5lhmTg1LkOAxChLwH
# vluiCY9K+2vIpt48ioK/h+tz5RgVdb+S8xwn728lN8KPkkB2Ra5iicrvtgA55wSU
# dh6FFxXxeS+bsgBayn7ZyafTpDM7BQOBYwaodsuVf5XgGryGx84k4R58mPwB3Q09
# CRAGs35NOt6TrPXqcylNu6Zz8xTQDcaJp54pKyOoW5iIDFjpLneXTEjtWCFCgAo4
# zbp9CNITp97KPnc3gZVaMvEpU8Sp7VZwN9ckR2WDKyOjDghIcfuFJTLOdkOuMLGs
# WPdnY6idtWc2bUDQa2QbzmNSZyFthEprwQ2GmgaGbGKuYVVqUj/Yt21HD0PBeDI5
# Mal8ScwwggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3
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
# MSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpGODdBLUUzNzQtRDdCOTElMCMGA1UE
# AxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUA
# vJqwk/xnycgV5Gdy5b4IwE/TWuOggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMDANBgkqhkiG9w0BAQUFAAIFAOYwmjEwIhgPMjAyMjA1MTkxNDI4
# MDFaGA8yMDIyMDUyMDE0MjgwMVowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA5jCa
# MQIBADAKAgEAAgIeawIB/zAHAgEAAgITmzAKAgUA5jHrsQIBADA2BgorBgEEAYRZ
# CgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0G
# CSqGSIb3DQEBBQUAA4GBALa1SoDLE7seujjXcIA1xt2ElexQUK657m8lefoE/l6v
# /W4RvZtTJ117+arzK/BibNB+KEGaJzFThko2S8Sn/wK6N+TjxUpTFIMIiM03/I/l
# FMH9qHp/wyUpTtaOP7r2GFVJoyNyUaHoAwofQiGh46/8fuOls3G0ndvJeJpCPReJ
# MYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMA
# AAGuqgtcszSllRoAAQAAAa4wDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJ
# AzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgCz1WaV4goXo71vCGVjfv
# WPldgNX9qq3b/83ONKXSqV0wgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCBJ
# KB0+uIzDWqHun09mqTU8uOg6tew0yu1uQ0iU/FJvaDCBmDCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABrqoLXLM0pZUaAAEAAAGuMCIEILFf
# WsLzZaxscKrCWoCwdeGKewwyOgofc0GNYHnxprD+MA0GCSqGSIb3DQEBCwUABIIC
# ACCO0rGVJL3/FlDF0dATTT6IsDj2ixa+6hiEJAQUCoQe+UAL5m8xU9/qpWhvMiJZ
# SRrdyBQPoCR2gfYhtJ34mjjBd0DXOlcrlvh4H8elaESre60SBIwU3gklm9vAD0c7
# +bwxFRE0pfdBBxRt3Pj1Snt2RGAr3d54Rm0hfAVNVwnubS/DvSdC4VrxfmUM2NYm
# N2cizv1pjr5yYgadJy1DaaSm9JCLnofgexTXfhcyGOlIDXuE8XJHiyrzwOMVqKIK
# LgK9PX+iFyTHpB9yT5LeAkt3yyc4Qxco3r7ITcWSdRBNdbhocAfIuZhSVb2iY0ry
# 7IqmKUrarHO6RS6/olVBpWkAuChTcO3sDdrU1T1r17xuCk9uj2CMFzw34bFVFMwC
# TI2oKLyZP4zaZtRKn/XGWmSzh95mGxirfivhKgsyjHGMrnXMaEy+8dXBFpj6oxD2
# n2AePm4gVZqzfOaSlJN4XhPE1xtVlivi/PNDer5fruGDX9vVnPqZ+GgjYsXrcvSg
# nxtI/lj2lYgfns8KSJBAkty2/Uy5qs7eLyh7AtCbdeOEqM1XIXBlDxDGoV8Q4pEN
# xVDNLujnvhA9EQfpORZEkANT2zaWJ+q+MxDNoMMPrMVRUHCkqon+/MJb0VApPiVs
# lCBoby9PNk8HYY2r1AaSFUIq9EFQ50gGOfNAa+VECUs5
# SIG # End signature block
