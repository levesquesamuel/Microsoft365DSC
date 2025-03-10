
#region Session Objects
$Global:SessionSecurityCompliance = $null
#endregion

#region Extraction Modes
$Global:DefaultComponents = @('SPOApp', 'SPOSiteDesign')

$Global:FullComponents = @('AADGroup', 'AADServicePrincipal', 'EXOCalendarProcessing', 'EXODistributionGroup', 'EXOMailboxAutoReplyConfiguration', `
        'EXOMailboxPermission','EXOMailboxCalendarFolder','EXOMailboxSettings', 'EXOManagementRole', 'O365Group', 'AADUser', `
        'PlannerPlan', 'PlannerBucket', 'PlannerTask', 'PPPowerAppsEnvironment', 'PPTenantSettings', `
        'SPOSiteAuditSettings', 'SPOSiteGroup', 'SPOSite', 'SPOUserProfileProperty', 'SPOPropertyBag', 'TeamsTeam', 'TeamsChannel', `
        'TeamsUser', 'TeamsChannelTab', 'TeamsOnlineVoicemailUserSettings', 'TeamsUserCallingSettings', 'TeamsUserPolicyAssignment')
#endregion

<#
.Description
This function cleans up an EXO parameter hashtable

.Functionality
Internal, Hidden
#>
function Format-EXOParams
{
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [System.Collections.Hashtable]
        $InputEXOParams,

        [Parameter()]
        [ValidateSet('New', 'Set')]
        [System.String]
        $Operation
    )

    $EXOParams = $InputEXOParams
    $EXOParams.Remove('Credential') | Out-Null
    $EXOParams.Remove('Ensure') | Out-Null
    $EXOParams.Remove('Verbose') | Out-Null
    $EXOParams.Remove('ApplicationId') | Out-Null
    $EXOParams.Remove('TenantId') | Out-Null
    $EXOParams.Remove('CertificateThumbprint') | Out-Null
    $EXOParams.Remove('CertificatePath') | Out-Null
    $EXOParams.Remove('CertificatePassword') | Out-Null
    if ('New' -eq $Operation)
    {
        $EXOParams += @{
            Name = $EXOParams.Identity
        }
        $EXOParams.Remove('Identity') | Out-Null
        $EXOParams.Remove('MakeDefault') | Out-Null
        return $EXOParams
    }
    if ('Set' -eq $Operation)
    {
        $EXOParams.Remove('Enabled') | Out-Null
        return $EXOParams
    }
}

<#
.Description
This function retrieves a Teams team by its name

.Functionality
Internal
#>
function Get-TeamByName
{
    [CmdletBinding()]
    [OutputType([Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $TeamName
    )

    try
    {
        $loopCounter = 0
        do
        {
            $team = Get-Team -DisplayName $TeamName | Where-Object -FilterScript { $_.DisplayName -eq [System.Net.WebUtility]::UrlDecode($TeamName) }
            if ($null -eq $team)
            {
                Start-Sleep 5
            }
            $loopCounter += 1
            if ($loopCounter -gt 5)
            {
                break
            }
        } while ($null -eq $team)

        if ($null -eq $team)
        {
            throw "Team with Name $TeamName doesn't exist in tenant"
        }
        elseif ($teams.Length -gt 1)
        {
            Write-Warning -Message "More than one Team with name {$TeamName} was found. This could prevent your configuration from compiling properly."
        }
        return $team
    }
    catch
    {
        return $null
    }
}

<#
.Description
This function converts a parameter hashtable to a string, for outputting to screen

.Functionality
Internal
#>
function Convert-M365DscHashtableToString
{
    param
    (
        [Parameter()]
        [System.Collections.Hashtable]
        $Hashtable
    )

    $values = @()
    $parametersToObfuscate = @('ApplicationId', 'ApplicationSecret', 'TenantId', 'CertificateThumbprint', 'CertificatePath', 'CertificatePassword', 'Credential')
    foreach ($pair in $Hashtable.GetEnumerator())
    {
        try
        {
            if ($pair.Value -is [System.Array])
            {
                $str = "$($pair.Key)=$(Convert-M365DSCArrayToString -Array $pair.Value)"
            }
            elseif ($pair.Value -is [System.Collections.Hashtable])
            {
                $str = "$($pair.Key)={$(Convert-M365DscHashtableToString -Hashtable $pair.Value)}"
            }
            elseif ($pair.Value -is [Microsoft.Management.Infrastructure.CimInstance])
            {
                $str = "$($pair.Key)=$(Convert-M365DSCCIMInstanceToString -CIMInstance $pair.Value)"
            }
            else
            {
                if ($null -eq $pair.Value)
                {
                    $str = "$($pair.Key)=`$null"
                }
                else
                {
                    if ($parametersToObfuscate.Contains($pair.Key))
                    {
                        $str = "$($pair.Key)=***"
                    }
                    else
                    {
                        $str = "$($pair.Key)=$($pair.Value)"
                    }
                }
            }
            $values += $str
        }
        catch
        {
            Write-Warning "There was an error converting the Hashtable to a string: $_"
        }
    }

    [array]::Sort($values)
    return ($values -join "`r`n")
}

<#
.Description
This function converts a parameter array to a string, for outputting to screen

.Functionality
Internal
#>
function Convert-M365DscArrayToString
{
    param
    (
        [Parameter()]
        [System.Array]
        $Array
    )

    $str = '('
    for ($i = 0; $i -lt $Array.Count; $i++)
    {
        $item = $Array[$i]
        if ($item -is [System.Collections.Hashtable])
        {
            $str += '{'
            $str += Convert-M365DscHashtableToString -Hashtable $item
            $str += '}'
        }
        elseif ($Array[$i] -is [Microsoft.Management.Infrastructure.CimInstance])
        {
            $str += Convert-M365DSCCIMInstanceToString -CIMInstance $item
        }
        else
        {
            $str += $item
        }

        if ($i -lt ($Array.Count - 1))
        {
            $str += ','
        }
    }
    $str += ')'

    return $str
}

<#
.Description
This function converts a parameter CimInstance to a string, for outputting to screen

.Functionality
Internal
#>
function Convert-M365DscCIMInstanceToString
{
    param
    (
        [Parameter()]
        [Microsoft.Management.Infrastructure.CimInstance]
        $CIMInstance
    )

    $str = '{'
    foreach ($prop in $CIMInstance.CimInstanceProperties)
    {
        if ($str -notmatch '{$')
        {
            $str += '; '
        }
        $str += "$($prop.Name)=$($prop.Value)"
    }
    $str += '}'

    return $str
}


<#
.Description
This function creates a new EXO Safe Attachment rule

.Functionality
Internal
#>
function New-EXOSafeAttachmentRule
{
    param
    (
        [Parameter()]
        [System.Collections.Hashtable]
        $SafeAttachmentRuleParams
    )

    try
    {
        $VerbosePreference = 'Continue'
        $BuiltParams = (Format-EXOParams -InputEXOParams $SafeAttachmentRuleParams -Operation 'New' )
        Write-Verbose -Message "Creating New SafeAttachmentRule $($BuiltParams.Name) with values: $(Convert-M365DscHashtableToString -Hashtable $BuiltParams)"
        New-SafeAttachmentRule @BuiltParams -Confirm:$false
        $VerbosePreference = 'SilentlyContinue'
    }
    catch
    {
        Write-M365DSCLogEvent -Message $_ -EventSource $($MyInvocation.MyCommand.Source) -TenantId $tenantid -Credential $Credential
    }
}

<#
.Description
This function creates a new EXO Safe Links rule

.Functionality
Internal
#>
function New-EXOSafeLinksRule
{
    param
    (
        [Parameter()]
        [System.Collections.Hashtable]
        $SafeLinksRuleParams
    )

    try
    {
        $VerbosePreference = 'Continue'
        $BuiltParams = (Format-EXOParams -InputEXOParams $SafeLinksRuleParams -Operation 'New' )
        Write-Verbose -Message "Creating New SafeLinksRule $($BuiltParams.Name) with values: $(Convert-M365DscHashtableToString -Hashtable $BuiltParams)"
        New-SafeLinksRule @BuiltParams -Confirm:$false
        $VerbosePreference = 'SilentlyContinue'
    }
    catch
    {
        Write-M365DSCLogEvent -Message $_ -EventSource $($MyInvocation.MyCommand.Source) -TenantId $tenantid -Credential $Credential
    }
}

<#
.Description
This function checks if the specified cmdlet is available or not

.Functionality
Internal
#>
function Confirm-ImportedCmdletIsAvailable
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $CmdletName
    )

    try
    {
        $CmdletIsAvailable = (Get-Command -Name $CmdletName -ErrorAction SilentlyContinue)
        if ($CmdletIsAvailable)
        {
            return $true
        }
        else
        {
            return $false
        }
    }
    catch
    {
        return $false
    }
}

<#
.Description
This function updates a new EXO Safe Attachment rule

.Functionality
Internal
#>
function Set-EXOSafeAttachmentRule
{
    param
    (
        [Parameter()]
        [System.Collections.Hashtable]
        $SafeAttachmentRuleParams
    )

    try
    {
        $VerbosePreference = 'Continue'
        $BuiltParams = (Format-EXOParams -InputEXOParams $SafeAttachmentRuleParams -Operation 'Set' )
        if ($BuiltParams.keys -gt 1)
        {
            Write-Verbose -Message "Setting SafeAttachmentRule $($BuiltParams.Identity) with values: $(Convert-M365DscHashtableToString -Hashtable $BuiltParams)"
            Set-SafeAttachmentRule @BuiltParams -Confirm:$false
            $VerbosePreference = 'SilentlyContinue'
        }
        else
        {
            Write-Verbose -Message "No more values to Set on SafeAttachmentRule $($BuiltParams.Identity) using supplied values: $(Convert-M365DscHashtableToString -Hashtable $BuiltParams)"
            $VerbosePreference = 'SilentlyContinue'
        }
    }
    catch
    {
        Write-M365DSCLogEvent -Message $_ -EventSource $($MyInvocation.MyCommand.Source) -TenantId $tenantid -Credential $Credential
    }
}

<#
.Description
This function creates a new EXO Safe Links rule

.Functionality
Internal
#>
function Set-EXOSafeLinksRule
{
    param
    (
        [Parameter()]
        [System.Collections.Hashtable]
        $SafeLinksRuleParams
    )

    try
    {
        $VerbosePreference = 'Continue'
        $BuiltParams = (Format-EXOParams -InputEXOParams $SafeLinksRuleParams -Operation 'Set' )
        if ($BuiltParams.keys -gt 1)
        {
            Write-Verbose -Message "Setting SafeLinksRule $($BuiltParams.Identity) with values: $(Convert-M365DscHashtableToString -Hashtable $BuiltParams)"
            Set-SafeLinksRule @BuiltParams -Confirm:$false
            $VerbosePreference = 'SilentlyContinue'
        }
        else
        {
            Write-Verbose -Message "No more values to Set on SafeLinksRule $($BuiltParams.Identity) using supplied values: $(Convert-M365DscHashtableToString -Hashtable $BuiltParams)"
            $VerbosePreference = 'SilentlyContinue'
        }
    }
    catch
    {
        Write-M365DSCLogEvent -Message $_ -EventSource $($MyInvocation.MyCommand.Source) -TenantId $tenantid -Credential $Credential
    }
}

<#
.Description
This function compares two arrays with PSCustomObject objects

.Functionality
Internal, Hidden
#>
function Compare-PSCustomObjectArrays
{
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object[]]
        $DesiredValues,

        [Parameter(Mandatory = $true)]
        [System.Object[]]
        $CurrentValues
    )
$VerbosePreference = 'Continue'
    $DriftedProperties = @()
    foreach ($DesiredEntry in $DesiredValues)
    {
        $Properties = $DesiredEntry.PSObject.Properties
        $KeyProperty = $Properties.Name[0]

        $EquivalentEntryInCurrent = $CurrentValues | Where-Object -FilterScript { $_.$KeyProperty -eq $DesiredEntry.$KeyProperty }
        if ($null -eq $EquivalentEntryInCurrent)
        {
            $result = @{
                Property     = $DesiredEntry
                PropertyName = $KeyProperty
                Desired      = $DesiredEntry.$KeyProperty
                Current      = $null
            }
            $DriftedProperties += $DesiredEntry
        }
        else
        {
            foreach ($property in $Properties)
            {
                $propertyName = $property.Name

                if ((-not [System.String]::IsNullOrEmpty($DesiredEntry.$PropertyName) -and -not [System.String]::IsNullOrEmpty($EquivalentEntryInCurrent.$PropertyName)) -and `
                    $DesiredEntry.$PropertyName -ne $EquivalentEntryInCurrent.$PropertyName)
                {
                    $drift = $true
                    if ($DesiredEntry.$PropertyName.GetType().Name -eq 'String' -and $DesiredEntry.$PropertyName.Contains('$OrganizationName'))
                    {
                        if ($DesiredEntry.$PropertyName.Split('@')[0] -eq $EquivalentEntryInCurrent.$PropertyName.Split('@')[0])
                        {
                            $drift = $false
                        }
                    }
                    if ($drift)
                    {
                        $result = @{
                            Property     = $DesiredEntry
                            PropertyName = $PropertyName
                            Desired      = $DesiredEntry.$PropertyName
                            Current      = $EquivalentEntryInCurrent.$PropertyName
                        }
                        $DriftedProperties += $result
                    }
                }
            }
        }
    }

    return $DriftedProperties
}


<#
.Description
This function retrieves the current tenant's name based on received authentication parameters.

.Functionality
Internal
#>
function Get-M365DSCTenantNameFromParameterSet
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true, Position = 1)]
        [System.Collections.HashTable]
        $ParameterSet
    )

    if ($ParameterSet.TenantId)
    {
        return $ParameterSet.TenantId
    }
    elseif ($ParameterSet.Credential)
    {
        try
        {
            $tenantName = $ParameterSet.Credential.Username.Split('@')[1]
            return $tenantName
        }
        catch
        {
            return $null
        }
    }
}

<#
.Description
This function tests if the DSC hashtables have the same values

.Functionality
Internal
#>
function Test-M365DSCParameterState
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true, Position = 1)]
        [HashTable]
        $CurrentValues,

        [Parameter(Mandatory = $true, Position = 2)]
        [Object]
        $DesiredValues,

        [Parameter(Position = 3)]
        [Array]
        $ValuesToCheck,

        [Parameter(Position = 4)]
        [System.String]
        $Source = 'Generic',

        [Parameter(Position = 5)]
        [System.String]
        $Tenant,

        [Parameter(Position = 6)]
        [System.Collections.Hashtable]
        $IncludedDrifts
    )
    $VerbosePreference = 'SilentlyContinue'
    #region Telemetry
    $data = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $data.Add('Resource', "$Source")
    $data.Add('Method', 'Test-TargetResource')
    #endregion
    $returnValue = $true

    $DriftedParameters = @{ }
    if ($null -ne $IncludedDrifts -and $IncludedDrifts.Keys.Count -gt 0)
    {
        $DriftedParameters = $IncludedDrifts
        Write-Verbose -Message "@@@@@@@@@@`r`n$($IncludedDrifts | Out-String)"
        $returnValue = $false
    }

    if (($DesiredValues.GetType().Name -ne 'HashTable') `
            -and ($DesiredValues.GetType().Name -ne 'CimInstance') `
            -and ($DesiredValues.GetType().Name -ne 'PSBoundParametersDictionary'))
    {
        throw ("Property 'DesiredValues' in Test-M365DSCParameterState must be either a " + `
                "Hashtable or CimInstance. Type detected was $($DesiredValues.GetType().Name)")
    }

    if (($DesiredValues.GetType().Name -eq 'CimInstance') -and ($null -eq $ValuesToCheck))
    {
        throw ("If 'DesiredValues' is a CimInstance then property 'ValuesToCheck' must contain " + `
                'a value')
    }

    if (($null -eq $ValuesToCheck) -or ($ValuesToCheck.Count -lt 1))
    {
        $KeyList = $DesiredValues.Keys
    }
    else
    {
        $KeyList = $ValuesToCheck
    }

    $KeyList | ForEach-Object -Process {
        if (($_ -ne 'Verbose') -and ($_ -ne 'Credential') `
                -and ($_ -ne 'ApplicationId') -and ($_ -ne 'CertificateThumbprint') `
                -and ($_ -ne 'CertificatePath') -and ($_ -ne 'CertificatePassword') `
                -and ($_ -ne 'TenantId') -and ($_ -ne 'ApplicationSecret') `
                -and ($_ -ne 'ManagedIdentity'))
        {
            if (($CurrentValues.ContainsKey($_) -eq $false) `
                    -or ($CurrentValues.$_ -ne $DesiredValues.$_) `
                    -or (($DesiredValues.ContainsKey($_) -eq $true) -and ($null -ne $DesiredValues.$_ -and $DesiredValues.$_.GetType().IsArray)))
            {
                if ($DesiredValues.GetType().Name -eq 'HashTable' -or `
                        $DesiredValues.GetType().Name -eq 'PSBoundParametersDictionary')
                {
                    $CheckDesiredValue = $DesiredValues.ContainsKey($_)
                }
                else
                {
                    $CheckDesiredValue = Test-M365DSCObjectHasProperty -Object $DesiredValues -PropertyName $_
                }

                if ($CheckDesiredValue)
                {
                    $desiredType = $DesiredValues.$_.GetType()
                    $fieldName = $_
                    if ($desiredType.IsArray -eq $true)
                    {
                        if (($CurrentValues.ContainsKey($fieldName) -eq $false) `
                                -or ($null -eq $CurrentValues.$fieldName))
                        {
                            Write-Verbose -Message ('Expected to find an array value for ' + `
                                    "property $fieldName in the current " + `
                                    'values, but it was either not present or ' + `
                                    'was null. This has caused the test method ' + `
                                    'to return false.')
                            $DriftedParameters.Add($fieldName, '')
                            $returnValue = $false
                        }
                        elseif ($desiredType.Name -eq 'ciminstance[]')
                        {
                            Write-Verbose "The current property {$_} is a CimInstance[]"
                            $AllDesiredValuesAsArray = @()
                            foreach ($item in $DesiredValues.$_)
                            {
                                $currentEntry = @{ }
                                foreach ($prop in $item.CIMInstanceProperties)
                                {
                                    $value = $prop.Value
                                    if ([System.String]::IsNullOrEmpty($value))
                                    {
                                        $value = $null
                                    }
                                    if (-not $currentEntry.ContainsKey($prop.Name))
                                    {
                                        $currentEntry.Add($prop.Name, $value)
                                    }
                                }
                                $AllDesiredValuesAsArray += [PSCustomObject]$currentEntry
                            }
                            $arrayCompare = Compare-PSCustomObjectArrays -CurrentValues $CurrentValues.$fieldName `
                                -DesiredValues $AllDesiredValuesAsArray

                            if ($null -ne $arrayCompare)
                            {
                                foreach ($item in $arrayCompare)
                                {
                                    $EventValue = "<CurrentValue>[$($item.PropertyName)]$($item.CurrentValue)</CurrentValue>"
                                    $EventValue += "<DesiredValue>[$($item.PropertyName)]$($item.DesiredValue)</DesiredValue>"

                                    if (-not $DriftedParameters.ContainsKey($fieldName))
                                    {
                                        $DriftedParameters.Add($fieldName, $EventValue)
                                    }
                                }
                                $returnValue = $false
                            }
                        }
                        else
                        {
                            $arrayCompare = Compare-Object -ReferenceObject $CurrentValues.$fieldName `
                                -DifferenceObject $DesiredValues.$fieldName
                            if ($null -ne $arrayCompare -and
                                -not [System.String]::IsNullOrEmpty($arrayCompare.InputObject))
                            {
                                Write-Verbose -Message ("Found an array for property $fieldName " + `
                                        'in the current values, but this array ' + `
                                        'does not match the desired state. ' + `
                                        'Details of the changes are below.')
                                $arrayCompare | ForEach-Object -Process {
                                    Write-Verbose -Message "$($_.InputObject) - $($_.SideIndicator)"
                                }

                                $EventValue = "<CurrentValue>$($CurrentValues.$fieldName)</CurrentValue>"
                                $EventValue += "<DesiredValue>$($DesiredValues.$fieldName)</DesiredValue>"
                                $DriftedParameters.Add($fieldName, $EventValue)
                                $returnValue = $false
                            }
                        }
                    }
                    else
                    {
                        switch ($desiredType.Name)
                        {
                            'String'
                            {
                                if ([string]::IsNullOrEmpty($CurrentValues.$fieldName) `
                                        -and [string]::IsNullOrEmpty($DesiredValues.$fieldName))
                                {
                                }
                                else
                                {
                                    Write-Verbose -Message ('String value for property ' + `
                                            "$fieldName does not match. " + `
                                            'Current state is ' + `
                                            "'$($CurrentValues.$fieldName)' " + `
                                            'and desired state is ' + `
                                            "'$($DesiredValues.$fieldName)'")
                                    $EventValue = "<CurrentValue>$($CurrentValues.$fieldName)</CurrentValue>"
                                    $EventValue += "<DesiredValue>$($DesiredValues.$fieldName)</DesiredValue>"
                                    $DriftedParameters.Add($fieldName, $EventValue)
                                    $returnValue = $false
                                }
                            }
                            'Int32'
                            {
                                if (($DesiredValues.$fieldName -eq 0) `
                                        -and ($null -eq $CurrentValues.$fieldName))
                                {
                                }
                                else
                                {
                                    Write-Verbose -Message ('Int32 value for property ' + `
                                            "$fieldName does not match. " + `
                                            'Current state is ' + `
                                            "'$($CurrentValues.$fieldName)' " + `
                                            'and desired state is ' + `
                                            "'$($DesiredValues.$fieldName)'")
                                    $EventValue = "<CurrentValue>$($CurrentValues.$fieldName)</CurrentValue>"
                                    $EventValue += "<DesiredValue>$($DesiredValues.$fieldName)</DesiredValue>"
                                    $DriftedParameters.Add($fieldName, $EventValue)
                                    $returnValue = $false
                                }
                            }
                            'Int16'
                            {
                                if (($DesiredValues.$fieldName -eq 0) `
                                        -and ($null -eq $CurrentValues.$fieldName))
                                {
                                }
                                else
                                {
                                    Write-Verbose -Message ('Int16 value for property ' + `
                                            "$fieldName does not match. " + `
                                            'Current state is ' + `
                                            "'$($CurrentValues.$fieldName)' " + `
                                            'and desired state is ' + `
                                            "'$($DesiredValues.$fieldName)'")
                                    $EventValue = "<CurrentValue>$($CurrentValues.$fieldName)</CurrentValue>"
                                    $EventValue += "<DesiredValue>$($DesiredValues.$fieldName)</DesiredValue>"
                                    $DriftedParameters.Add($fieldName, $EventValue)
                                    $returnValue = $false
                                }
                            }
                            'Boolean'
                            {
                                if ($CurrentValues.$fieldName -ne $DesiredValues.$fieldName)
                                {
                                    Write-Verbose -Message ('Boolean value for property ' + `
                                            "$fieldName does not match. " + `
                                            'Current state is ' + `
                                            "'$($CurrentValues.$fieldName)' " + `
                                            'and desired state is ' + `
                                            "'$($DesiredValues.$fieldName)'")
                                    $EventValue = "<CurrentValue>$($CurrentValues.$fieldName)</CurrentValue>"
                                    $EventValue += "<DesiredValue>$($DesiredValues.$fieldName)</DesiredValue>"
                                    $DriftedParameters.Add($fieldName, $EventValue)
                                    $returnValue = $false
                                }
                            }
                            'Single'
                            {
                                if (($DesiredValues.$fieldName -eq 0) `
                                        -and ($null -eq $CurrentValues.$fieldName))
                                {
                                }
                                else
                                {
                                    Write-Verbose -Message ('Single value for property ' + `
                                            "$fieldName does not match. " + `
                                            'Current state is ' + `
                                            "'$($CurrentValues.$fieldName)' " + `
                                            'and desired state is ' + `
                                            "'$($DesiredValues.$fieldName)'")
                                    $EventValue = "<CurrentValue>$($CurrentValues.$fieldName)</CurrentValue>"
                                    $EventValue += "<DesiredValue>$($DesiredValues.$fieldName)</DesiredValue>"
                                    $DriftedParameters.Add($fieldName, $EventValue)
                                    $returnValue = $false
                                }
                            }
                            'Hashtable'
                            {
                                Write-Verbose -Message "The current property {$fieldName} is a Hashtable"
                                $AllDesiredValuesAsArray = @()
                                foreach ($item in $DesiredValues.$fieldName)
                                {
                                    $currentEntry = @{ }
                                    foreach ($key in $item.Keys)
                                    {
                                        $value = $item.$key
                                        if ([System.String]::IsNullOrEmpty($value))
                                        {
                                            $value = $null
                                        }
                                        $currentEntry.Add($key, $value)
                                    }
                                    $AllDesiredValuesAsArray += [PSCustomObject]$currentEntry
                                }

                                if ($null -ne $DesiredValues.$fieldName -and $null -eq $CurrentValues.$fieldName)
                                {
                                    $returnValue = $false
                                }
                                else
                                {
                                    $AllCurrentValuesAsArray = @()
                                    foreach ($item in $CurrentValues.$fieldName)
                                    {
                                        $currentEntry = @{ }
                                        foreach ($key in $item.Keys)
                                        {
                                            $value = $item.$key
                                            if ([System.String]::IsNullOrEmpty($value))
                                            {
                                                $value = $null
                                            }
                                            $currentEntry.Add($key, $value)
                                        }
                                        $AllCurrentValuesAsArray += [PSCustomObject]$currentEntry
                                    }
                                    $arrayCompare = Compare-PSCustomObjectArrays -CurrentValues $AllCurrentValuesAsArray `
                                        -DesiredValues $AllDesiredValuesAsArray
                                    if ($null -ne $arrayCompare)
                                    {
                                        foreach ($item in $arrayCompare)
                                        {
                                            $EventValue = "<CurrentValue>[$($item.PropertyName)]$($item.CurrentValue)</CurrentValue>"
                                            $EventValue += "<DesiredValue>[$($item.PropertyName)]$($item.DesiredValue)</DesiredValue>"
                                            if (-not $DriftedParameters.ContainsKey($fieldName))
                                            {
                                                $DriftedParameters.Add($fieldName, $EventValue)
                                            }
                                        }
                                        $returnValue = $false
                                    }
                                }
                            }
                            default
                            {
                                Write-Verbose -Message ("Unable to compare property $fieldName " + `
                                        "as the type ($($desiredType.Name)) is " + `
                                        'not handled by the ' + `
                                        'Test-M365DSCParameterState cmdlet')
                                $EventValue = "<CurrentValue>$($CurrentValues.$fieldName)</CurrentValue>"
                                $EventValue += "<DesiredValue>$($DesiredValues.$fieldName)</DesiredValue>"
                                $DriftedParameters.Add($fieldName, $EventValue)
                                $returnValue = $false
                            }
                        }
                    }
                }
            }
        }
    }

    $includeNonDriftsInformation = $false
    try
    {
        $includeNonDriftsInformation = [System.Environment]::GetEnvironmentVariable('M365DSCEventLogIncludeNonDrifted', `
                [System.EnvironmentVariableTarget]::Machine)
    }
    catch
    {
        Write-Verbose -Message $_
    }
    if ($returnValue -eq $false -or $DriftedParameters.Keys.Length -gt 0)
    {
        $EventMessage = [System.Text.StringBuilder]::New()
        $EventMessage.Append("<M365DSCEvent>`r`n") | Out-Null
        $EventMessage.Append("    <ConfigurationDrift Source=`"$Source`">`r`n") | Out-Null

        $EventMessage.Append("        <ParametersNotInDesiredState>`r`n") | Out-Null
        foreach ($key in $DriftedParameters.Keys)
        {
            Write-Verbose -Message "Detected Drifted Parameter [$Source]$key"

            #region Telemetry
            $driftedData = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
            $driftedData.Add('Event', 'DriftedParameter')
            $driftedData.Add('Parameter', "[$Source]$key")

            # If custom App Insights is specified, allow for the current and desired values to be captured;
            # ISSUE #1222
            if ($null -ne $env:M365DSCTelemetryInstrumentationKey -and `
                    $env:M365DSCTelemetryInstrumentationKey -ne 'bc5aa204-0b1e-4499-a955-d6a639bdb4fa')
            {
                $driftedData.Add('CurrentValue', [string]($CurrentValues[$key]))
                $driftedData.Add('DesiredValue', [string]($DesiredValues[$key]))
            }
            $TenantName = Get-M365DSCTenantNameFromParameterSet -ParameterSet $DesiredValues
            $driftedData.Add('Tenant', $TenantName)
            Add-M365DSCTelemetryEvent -Type 'DriftInfo' -Data $driftedData
            #endregion
            $EventMessage.Append("            <Param Name=`"$key`">" + $DriftedParameters.$key + "</Param>`r`n") | Out-Null
        }

        #region Telemetry
        $TenantName = Get-M365DSCTenantNameFromParameterSet -ParameterSet $DesiredValues
        $data.Add('Event', 'ConfigurationDrift')
        $data.Add('Tenant', $TenantName)
        #endregion

        $EventMessage.Append("        </ParametersNotInDesiredState>`r`n") | Out-Null
        $EventMessage.Append("    </ConfigurationDrift>`r`n") | Out-Null
        $EventMessage.Append("    <DesiredValues>`r`n") | Out-Null
        foreach ($Key in $DesiredValues.Keys)
        {
            $Value = $DesiredValues.$Key
            if ([System.String]::IsNullOrEmpty($Value))
            {
                $Value = "`$null"
            }
            $EventMessage.Append("        <Param Name =`"$key`">$Value</Param>`r`n") | Out-Null
        }
        $EventMessage.Append("    </DesiredValues>`r`n") | Out-Null
        $EventMessage.Append('</M365DSCEvent>') | Out-Null

        Add-M365DSCEvent -Message $EventMessage.ToString() -EventType 'Drift' -EntryType 'Warning' `
            -EventID 1 -Source $Source
    }
    elseif ($includeNonDriftsInformation -eq $true)
    {
        # Include details about non-drifted resources.
        $EventMessage = [System.Text.StringBuilder]::New()
        $EventMessage.Append("<M365DSCEvent>`r`n") | Out-Null
        $EventMessage.Append("    <ConfigurationDrift Source=`"$Source`" />`r`n") | Out-Null
        $EventMessage.Append("    <DesiredValues>`r`n") | Out-Null
        foreach ($Key in $DesiredValues.Keys)
        {
            $Value = $DesiredValues.$Key
            if ([System.String]::IsNullOrEmpty($Value))
            {
                $Value = "`$null"
            }
            $EventMessage.Append("        <Param Name =`"$key`">$Value</Param>`r`n") | Out-Null
        }
        $EventMessage.Append("    </DesiredValues>`r`n") | Out-Null
        $EventMessage.Append('</M365DSCEvent>') | Out-Null
        Add-M365DSCEvent -Message $EventMessage.ToString() -EventType 'NonDrift' -EntryType 'Information' `
            -EventID 2 -Source $Source
    }

    #region Telemetry
    Add-M365DSCTelemetryEvent -Data $data
    #endregion
    return $returnValue
}

<#
.Description
This is the main Microsoft365DSC.Reverse function that extracts the DSC configuration from an existing Microsoft 365 Tenant.

.Parameter LaunchWebUI
Adding this parameter will open the WebUI in a browser.

.Parameter Path
Specifies the path in which the exported DSC configuration should be stored.

.Parameter FileName
Specifies the name of the file in which the exported DSC configuration should be stored.

.Parameter ConfigurationName
Specifies the name of the configuration that will be generated.

.Parameter Components
Specifies the components for which an export should be created.

.Parameter Workloads
Specifies the workload for which an export should be created for all resources.

.Parameter Mode
Specifies the mode of the export: Lite, Default or Full.

.Parameter MaxProcesses
Specifies the maximum number of processes that should run simultanious.

.Parameter GenerateInfo
Specifies if each exported resource should get a link to the Wiki article of the resource.

.Parameter ApplicationId
Specifies the application id to be used for authentication.

.Parameter ApplicationSecret
Specifies the application secret of the application to be used for authentication.

.Parameter TenantId
Specifies the id of the tenant.

.Parameter CertificateThumbprint
Specifies the thumbprint to be used for authentication.

.Parameter Credential
Specifies the credentials to be used for authentication.

.Parameter CertificatePassword
Specifies the password of the PFX file which is used for authentication.

.Parameter CertificatePath
Specifies the path of the PFX file which is used for authentication.

.Parameter Filters
Specifies resource level filters to apply in order to reduce the number of instances exported.

.Parameter ManagedIdentity
Specifies use of managed identity for authentication.

.Parameter Validate
Specifies that the configuration needs to be validated for conflicts or issues after its extraction is completed.

.Example
Export-M365DSCConfiguration -Components @("AADApplication", "AADConditionalAccessPolicy", "AADGroupsSettings") -Credential $Credential

.Example
Export-M365DSCConfiguration -Mode 'Default' -ApplicationId '2560bb7c-bc85-415f-a799-841e10ec4f9a' -TenantId 'contoso.sharepoint.com' -ApplicationSecret 'abcdefghijkl'

.Example
Export-M365DSCConfiguration -Components @("AADApplication", "AADConditionalAccessPolicy", "AADGroupsSettings") -Credential $Credential -Path 'C:\DSC' -FileName 'MyConfig.ps1'

.Example
Export-M365DSCConfiguration -Credential $Credential -Filters @{AADApplication = "DisplayName eq 'MyApp'"}

.Functionality
Public
#>
function Export-M365DSCConfiguration
{
    [CmdletBinding(DefaultParameterSetName = 'Export')]
    param
    (
        [Parameter(ParameterSetName = 'WebUI')]
        [Switch]
        $LaunchWebUI,

        [Parameter(ParameterSetName = 'Export')]
        [System.String]
        $Path,

        [Parameter(ParameterSetName = 'Export')]
        [System.String]
        $FileName,

        [Parameter(ParameterSetName = 'Export')]
        [System.String]
        $ConfigurationName,

        [Parameter(ParameterSetName = 'Export')]
        [System.String[]]
        $Components,

        [Parameter(ParameterSetName = 'Export')]
        [ValidateSet('AAD', 'SPO', 'EXO', 'INTUNE', 'SC', 'OD', 'O365', 'PLANNER', 'PP', 'TEAMS')]
        [System.String[]]
        $Workloads,

        [Parameter(ParameterSetName = 'Export')]
        [ValidateSet('Lite', 'Default', 'Full')]
        [System.String]
        $Mode = 'Default',

        [Parameter(ParameterSetName = 'Export')]
        [ValidateRange(1, 100)]
        $MaxProcesses,

        [Parameter(ParameterSetName = 'Export')]
        [System.Boolean]
        $GenerateInfo = $false,

        [Parameter(ParameterSetName = 'Export')]
        [System.Collections.Hashtable]
        $Filters,

        [Parameter(ParameterSetName = 'Export')]
        [System.String]
        $ApplicationId,

        [Parameter(ParameterSetName = 'Export')]
        [ValidateScript({
            $invalid = $false
            try
            {
                [System.Guid]::Parse($_) | Out-Null
                $invalid = $true
            }
            catch
            {
                $invalid = $false
            }
            if ($invalid)
            {
                throw "Please provide the tenant name (e.g., contoso.onmicrosoft.com) for TenantId instead of its GUID."
            }
            else
            {
                $invalid = $_ -notmatch ".onmicrosoft."
                if (-not $invalid)
                {
                    return $true
                }
                else
                {
                    Write-Host -Object "[WARNING] We recommend providing the TenantId property in the format of <tenant>.onmicrosoft.*" -ForegroundColor Yellow
                }
            }
            return $true
        })]
        [System.String]
        $TenantId,

        [Parameter(ParameterSetName = 'Export')]
        [System.String]
        $ApplicationSecret,

        [Parameter(ParameterSetName = 'Export')]
        [System.String]
        $CertificateThumbprint,

        [Parameter(ParameterSetName = 'Export')]
        [System.Management.Automation.PSCredential]
        $Credential,

        [Parameter(ParameterSetName = 'Export')]
        [System.Management.Automation.PSCredential]
        $CertificatePassword,

        [Parameter(ParameterSetName = 'Export')]
        [System.String]
        $CertificatePath,

        [Parameter(ParameterSetName = 'Export')]
        [Switch]
        $ManagedIdentity,

        [Parameter(ParameterSetName = 'Export')]
        [Switch]
        $Validate
    )

    $Global:MaximumFunctionCount = 32767

    # Define the exported resource instances' names Global variable
    $Global:M365DSCExportedResourceInstancesNames = @()

    # LaunchWebUI specified, launching that now
    if ($LaunchWebUI)
    {
        Write-Output -InputObject "Launching web page 'https://export.microsoft365dsc.com'"
        explorer 'https://export.microsoft365dsc.com'
        return
    }

    # Suppress Progress overlays
    $Global:ProgressPreference = 'SilentlyContinue'

    # Suppress Warnings
    $Global:WarningPreference = 'SilentlyContinue'

    ##### FIRST CHECK AUTH PARAMETERS
    if ($PSBoundParameters.ContainsKey('Credential') -eq $true -and `
        -not [System.String]::IsNullOrEmpty($Credential))
    {
        if ($Credential.Username -notmatch ".onmicrosoft.")
        {
            Write-Host -Object "[WARNING] We recommend providing the username in the format of <tenant>.onmicrosoft.* for the Credential property." -ForegroundColor Yellow
        }
    }

    if ($PSBoundParameters.ContainsKey('CertificatePath') -eq $true -and `
            $PSBoundParameters.ContainsKey('CertificatePassword') -eq $false)
    {
        Write-Host -Object '[ERROR] You have to specify CertificatePassword when you specify CertificatePath' -ForegroundColor Red
        return
    }

    if ($PSBoundParameters.ContainsKey('CertificatePassword') -eq $true -and `
            $PSBoundParameters.ContainsKey('CertificatePath') -eq $false)
    {
        Write-Host -Object '[ERROR] You have to specify CertificatePath when you specify CertificatePassword' -ForegroundColor Red
        return
    }

    if ($PSBoundParameters.ContainsKey('ApplicationId') -eq $true -and `
            $PSBoundParameters.ContainsKey('Credential') -eq $false -and `
            $PSBoundParameters.ContainsKey('TenantId') -eq $false)
    {
        Write-Host -Object '[ERROR] You have to specify TenantId when you specify ApplicationId' -ForegroundColor Red
        return
    }

    if ($PSBoundParameters.ContainsKey('ApplicationId') -eq $false -and `
            $ManagedIdentity.IsPresent -eq $false -and `
            $PSBoundParameters.ContainsKey('TenantId') -eq $true)
    {
        Write-Host -Object '[ERROR] You have to specify ApplicationId when you specify TenantId' -ForegroundColor Red
        return
    }

    if ($PSBoundParameters.ContainsKey('ApplicationId') -eq $true -and `
            $PSBoundParameters.ContainsKey('TenantId') -eq $true -and `
        ($PSBoundParameters.ContainsKey('CertificateThumbprint') -eq $false -and `
                $PSBoundParameters.ContainsKey('ApplicationSecret') -eq $false -and `
                $PSBoundParameters.ContainsKey('CertificatePath') -eq $false))
    {
        Write-Host -Object '[ERROR] You have to specify ApplicationSecret, CertificateThumbprint or CertificatePath when you specify ApplicationId/TenantId' -ForegroundColor Red
        return
    }

    if (($PSBoundParameters.ContainsKey('ApplicationId') -eq $false -or `
                $PSBoundParameters.ContainsKey('TenantId') -eq $false) -and `
        ($PSBoundParameters.ContainsKey('Credential') -eq $false -and `
                $PSBoundParameters.ContainsKey('CertificateThumbprint') -eq $true -or `
                $PSBoundParameters.ContainsKey('ApplicationSecret') -eq $true -or `
                $PSBoundParameters.ContainsKey('CertificatePath') -eq $true))
    {
        Write-Host -Message '[ERROR] You have to specify ApplicationId and TenantId when you specify ApplicationSecret, CertificateThumbprint or CertificatePath' -ForegroundColor Red
        return
    }

    # Default to Credential if no authentication mechanism were provided
    if ($PSBoundParameters.ContainsKey('Credential') -eq $false -and `
            $ManagedIdentity.IsPresent -eq $false -and `
            $PSBoundParameters.ContainsKey('ApplicationId') -eq $false)
    {
        $Credential = Get-Credential
    }

    #region Telemetry
    $data = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $data.Add('Event', 'Extraction')

    $data.Add('Path', [System.String]::IsNullOrEmpty($Path))
    $data.Add('FileName', $null -ne [System.String]::IsNullOrEmpty($FileName))
    $data.Add('Components', $null -ne $Components)
    $data.Add('Workloads', $null -ne $Workloads)
    $data.Add('MaxProcesses', $null -ne $MaxProcesses)
    #endregion

    if ($null -eq $MaxProcesses)
    {
        $MaxProcesses = 16
    }

    # Make sure we are not connected to Microsoft Graph on another tenant
    try
    {
        Disconnect-MgGraph -ErrorAction Stop | Out-Null
        $global:MsCloudLoginConnectionProfile.MicrosoftGraph.Connected = $false
    }
    catch
    {
        Write-Verbose -Message 'No existing connections to Microsoft Graph'
    }

    if (-not [System.String]::IsNullOrEmpty($TenantId))
    {
        $data.Add('Tenant', $TenantId)
    }
    else
    {
        if ($Credential)
        {
            $tenant = $Credential.UserName.Split('@')[1]
            $data.Add('Tenant', $tenant)
        }
    }

    Add-M365DSCTelemetryEvent -Data $data
    if ($null -ne $Workloads)
    {
        Write-Output -InputObject "Exporting Microsoft 365 configuration for Workloads: $($Workloads -join ', ')"
        Start-M365DSCConfigurationExtract -Credential $Credential `
            -Workloads $Workloads `
            -Mode $Mode `
            -Path $Path -FileName $FileName `
            -MaxProcesses $MaxProcesses `
            -ConfigurationName $ConfigurationName `
            -ApplicationId $ApplicationId `
            -ApplicationSecret $ApplicationSecret `
            -TenantId $TenantId `
            -CertificateThumbprint $CertificateThumbprint `
            -CertificatePath $CertificatePath `
            -CertificatePassword $CertificatePassword `
            -ManagedIdentity:$ManagedIdentity `
            -GenerateInfo $GenerateInfo `
            -Filters $Filters `
            -Validate:$Validate
    }
    elseif ($null -ne $Components)
    {
        Write-Output -InputObject "Exporting Microsoft 365 configuration for Components: $($Components -join ', ')"
        Start-M365DSCConfigurationExtract -Credential $Credential `
            -Components $Components `
            -Path $Path -FileName $FileName `
            -MaxProcesses $MaxProcesses `
            -ConfigurationName $ConfigurationName `
            -ApplicationId $ApplicationId `
            -ApplicationSecret $ApplicationSecret `
            -TenantId $TenantId `
            -CertificateThumbprint $CertificateThumbprint `
            -CertificatePath $CertificatePath `
            -CertificatePassword $CertificatePassword `
            -ManagedIdentity:$ManagedIdentity `
            -GenerateInfo $GenerateInfo `
            -Filters $Filters `
            -Validate:$Validate
    }
    elseif ($null -ne $Mode)
    {
        Write-Output -InputObject "Exporting Microsoft 365 configuration for Mode: $Mode"
        Start-M365DSCConfigurationExtract -Credential $Credential `
            -Mode $Mode `
            -Path $Path -FileName $FileName `
            -MaxProcesses $MaxProcesses `
            -ConfigurationName $ConfigurationName `
            -ApplicationId $ApplicationId `
            -ApplicationSecret $ApplicationSecret `
            -TenantId $TenantId `
            -CertificateThumbprint $CertificateThumbprint `
            -CertificatePath $CertificatePath `
            -CertificatePassword $CertificatePassword `
            -ManagedIdentity:$ManagedIdentity `
            -GenerateInfo $GenerateInfo `
            -AllComponents `
            -Filters $Filters `
            -Validate:$Validate
    }

    # Clear the exported resource instances' names Global variable
    $Global:M365DSCExportedResourceInstancesNames = $null
}

$Script:M365DSCDependenciesValidated = $false

<#
.Description
This function checks if all M365DSC dependencies are present

.Functionality
Internal
#>
function Confirm-M365DSCDependencies
{
    [CmdletBinding()]
    param()

    if (-not $Script:M365DSCDependenciesValidated)
    {
        Write-Verbose -Message 'Dependencies were not already validated.'

        $result = Update-M365DSCDependencies -ValidateOnly

        if ($result.Length -gt 0)
        {
            $ErrorMessage = "The following dependencies need updating:`r`n"
            foreach ($invalidDependency in $result)
            {
                $ErrorMessage += '    * ' + $invalidDependency.ModuleName + "`r`n"
            }
            $ErrorMessage += 'Please run Update-M365DSCDependencies with scope "currentUser" or as Administrator.'
            $ErrorMessage += 'Please run Uninstall-M365DSCOutdatedDependencies.'
            $Script:M365DSCDependenciesValidated = $false
            Add-M365DSCEvent -Message $ErrorMessage -EntryType 'Error' `
                -EventID 1 -Source $($MyInvocation.MyCommand.Source) `
                -TenantId $tenantIdValue
            throw $ErrorMessage
        }
        else
        {
            Write-Verbose -Message 'Dependencies were all successfully validated.'
            $Script:M365DSCDependenciesValidated = $true
        }
    }
    else
    {
        Write-Verbose -Message 'Dependencies were already successfully validated.'
    }
}

<#
.Description
This function re-imports all M365DSC dependencies, if not properly done before

.Example
Import-M365DSCDependencies

.Functionality
Public
#>
function Import-M365DSCDependencies
{
    [CmdletBinding()]
    param
    (
        [parameter()]
        [switch]$Global
    )

    $currentPath = Join-Path -Path $PSScriptRoot -ChildPath '..\' -Resolve
    $manifest = Import-PowerShellDataFile "$currentPath/Dependencies/Manifest.psd1"
    $dependencies = $manifest.Dependencies

    foreach ($dependency in $dependencies)
    {
        Import-Module $dependency.ModuleName -RequiredVersion $dependency.RequiredVersion -Force -Global:$Global
    }
}

<#
.Description
This function removes all versions of dependencies that are not specified in the manifest from the current PowerShell session.

.Example
Remove-M365DSCInvalidDependenciesFromSession

.Functionality
Private
#>
function Remove-M365DSCInvalidDependenciesFromSession
{
    [CmdletBinding()]
    param()

    $currentPath = Join-Path -Path $PSScriptRoot -ChildPath '..\' -Resolve
    $manifest = Import-PowerShellDataFile "$currentPath/Dependencies/Manifest.psd1"
    $dependencies = $manifest.Dependencies

    foreach ($dependency in $dependencies)
    {
        $loadedModuleInstances = Get-Module $dependency.ModuleName

        $incorrectModuleVersions = $null
        if ($loadedModuleInstances)
        {
            $incorrectModuleVersions = $loadedModuleInstances | Where-Object -FilterScript { $_.Version -ne $dependency.RequiredVersion }

            if ($incorrectModuleVersions)
            {
                foreach ($incorrectVersion in $incorrectModuleVersions)
                {
                    $FQN = @{
                        ModuleName    = $incorrectVersion.Name
                        ModuleVersion = $incorrectVersion.Version
                    }
                    Write-Verbose -Message "Removing Module {$($incorrectVersion.Name)} version {$($incorrectVersion.Version)} from the current PowerShell session"
                    Remove-Module -FullyQualifiedName $FQN -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

<#
.Description
This function gets the onmicrosoft.com name of the tenant

.Functionality
Internal
#>
function Get-M365DSCTenantDomain
{
    [CmdletBinding(DefaultParameterSetName = 'AppId')]
    param
    (
        [Parameter(ParameterSetName = 'AppId', Mandatory = $true)]
        [System.String]
        $ApplicationId,

        [Parameter(Mandatory = $true)]
        [System.String]
        $TenantId,

        [Parameter(ParameterSetName = 'AppId')]
        [System.Management.Automation.PSCredential]
        $ApplicationSecret,

        [Parameter(ParameterSetName = 'AppId')]
        [System.String]
        $CertificateThumbprint,

        [Parameter(ParameterSetName = 'AppId')]
        [System.String]
        $CertificatePath,

        [Parameter(ParameterSetName = 'MID')]
        [Switch]
        $ManagedIdentity
    )

    if ([System.String]::IsNullOrEmpty($CertificatePath))
    {
        $ConnectionMode = New-M365DSCConnection -Workload 'MicrosoftGraph' `
            -InboundParameters $PSBoundParameters

        try
        {
            $tenantDetails = Get-MgBetaOrganization -ErrorAction 'Stop'
            $defaultDomain = $tenantDetails.VerifiedDomains | Where-Object -FilterScript { $_.IsInitial }

            return $defaultDomain.Name
        }
        catch
        {
            if ($_.Exception.Message -eq 'Insufficient privileges to complete the operation.')
            {
                New-M365DSCLogEntry `
                    -Message 'Error retrieving Organizational information: Missing Organization.Read.All permission. ' `
                    -Exception $_ `
                    -Source $($MyInvocation.MyCommand.Source) `
                    -TenantId $TenantId `
                    -Credential $Credential

                return ''
            }

            throw $_
        }
    }

    if ($TenantId.Contains('onmicrosoft'))
    {
        return $TenantId
    }
    else
    {
        throw 'TenantID must be in format contoso.onmicrosoft.com'
    }
}

<#
.Description
This function gets the DNS domain used in the specified credential

.Functionality
Internal
#>
function Get-M365DSCOrganization
{
    param
    (
        [Parameter()]
        [System.Management.Automation.PSCredential]
        $Credential,

        [Parameter()]
        [System.String]
        $TenantId
    )

    if ($null -ne $Credential -and $Credential.UserName.Contains('@'))
    {
        $organization = $Credential.UserName.Split('@')[1]
        return $organization
    }
    if (-not [System.String]::IsNullOrEmpty($TenantId))
    {
        if ($TenantId.contains('.'))
        {
            $organization = $TenantId
            return $organization
        }
        else
        {
            Throw 'Tenant ID must be name of tenant not a GUID. Ex contoso.onmicrosoft.com'
        }

    }
}

<#
.Description
This function creates a new connection to the specifiek M365 workload

.Functionality
Internal
#>
function New-M365DSCConnection
{
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('ExchangeOnline', 'Intune', `
                'SecurityComplianceCenter', 'PnP', 'PowerPlatforms', `
                'MicrosoftTeams', 'MicrosoftGraph', 'Tasks')]
        [System.String]
        $Workload,

        [Parameter(Mandatory = $true)]
        [ValidateScript({
            if ($null -ne $_.Credential)
            {
                $invalid = $_.Credential.Username -notmatch ".onmicrosoft."
                if (-not $invalid)
                {
                    return $true
                }
                else
                {
                    Write-Warning -Message "We recommend providing the username in the format of <tenant>.onmicrosoft.* for the Credential property."
                }
            }

            if ($null -ne $_.TenantId)
            {
                $invalid = $false
                try
                {
                    [System.Guid]::Parse($_.TenantId) | Out-Null
                    $invalid = $true
                }
                catch
                {
                    $invalid = $false
                }
                if ($invalid)
                {
                    throw "Please provide the tenant name (e.g., contoso.onmicrosoft.com) for TenantId instead of its GUID."
                }
                else
                {
                    $invalid = $_.TenantId -notmatch ".onmicrosoft."
                    if (-not $invalid)
                    {
                        return $true
                    }
                    else
                    {
                        Write-Warning -Message "We recommend providing the tenant name in format <tenant>.onmicrosoft.* for TenantId."
                    }
                }
            }
            return $true
        })]
        [System.Collections.Hashtable]
        $InboundParameters,

        [Parameter()]
        [System.String]
        $Url,

        [Parameter()]
        [System.Boolean]
        $SkipModuleReload = $false
    )

    $Global:MaximumFunctionCount = 32767

    if ($Workload -eq 'MicrosoftTeams')
    {
        try
        {
            $cmdlet = Get-Command 'Connect-MicrosoftTeams' -ErrorAction Stop
        }
        catch
        {
            Import-Module 'MicrosoftTeams' -Global -Force | Out-Null
        }
    }

    Write-Verbose -Message "Attempting connection to {$Workload} with:"
    Write-Verbose -Message "$($InboundParameters | Out-String)"

    if ($SkipModuleReload -eq $true)
    {
        $Global:CurrentModeIsExport = $true
    }
    else
    {
        $Global:CurrentModeIsExport = $false
    }
    #Ensure the proper dependencies are installed in the current environment.
    Confirm-M365DSCDependencies

    #region Telemetry
    $data = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $data.Add('Source', 'M365DSCUtil')
    $data.Add('Platform', $Workload)

    # Get the ApplicationSecret parameter back as a string.
    if ($InboundParameters.ApplicationSecret)
    {
        $InboundParameters.ApplicationSecret = $InboundParameters.ApplicationSecret.GetNetworkCredential().Password
    }

    # Case both authentication methods are attempted
    if ($null -ne $InboundParameters.Credential -and `
        (-not [System.String]::IsNullOrEmpty($InboundParameters.TenantId) -or `
                -not [System.String]::IsNullOrEmpty($InboundParameters.CertificateThumbprint)))
    {
        $message = 'Both Authentication methods are attempted'
        Write-Verbose -Message $message
        $data.Add('Event', 'Error')
        $data.Add('Exception', $message)
        $errorText = "You can't specify both the Credential and one of {TenantId, CertificateThumbprint}"
        $data.Add('CustomMessage', $errorText)
        Add-M365DSCTelemetryEvent -Type 'Error' -Data $data
        throw $errorText
    }
    # Case no authentication method is specified
    elseif ($null -eq $InboundParameters.Credential -and `
            [System.String]::IsNullOrEmpty($InboundParameters.ApplicationId) -and `
            [System.String]::IsNullOrEmpty($InboundParameters.TenantId) -and `
            [System.String]::IsNullOrEmpty($InboundParameters.CertificateThumbprint) -and `
            -not $InboundParameters.ManagedIdentity)
    {
        $message = 'No Authentication method was provided'
        Write-Verbose -Message $message
        $message += "`r`nProvided Keys --> $($InboundParameters.Keys)"
        $data.Add('Event', 'Error')
        $data.Add('Exception', $message)
        $errorText = 'You must specify either the Credential or ApplicationId, TenantId and CertificateThumbprint parameters.'
        $data.Add('CustomMessage', $errorText)
        Add-M365DSCTelemetryEvent -Type 'Error' -Data $data
        throw $errorText
    }
    # Case only Credential is specified
    elseif ($null -ne $InboundParameters.Credential -and `
            [System.String]::IsNullOrEmpty($InboundParameters.ApplicationId) -and `
            [System.String]::IsNullOrEmpty($InboundParameters.TenantId) -and `
            [System.String]::IsNullOrEmpty($InboundParameters.CertificateThumbprint))
    {
        Write-Verbose -Message 'Credential was specified. Connecting via User Principal'
        if ([System.String]::IsNullOrEmpty($Url))
        {
            Connect-M365Tenant -Workload $Workload `
                -Credential $InboundParameters.Credential `
                -SkipModuleReload $Global:CurrentModeIsExport
            $data.Add('ConnectionType', 'Credential')

            try
            {
                $tenantId = $InboundParameters.Credential.Username.Split('@')[1]
                $data.Add('Tenant', $tenantId)
            }
            catch
            {
                Write-Verbose -Message $_
            }

            Add-M365DSCTelemetryEvent -Data $data -Type 'Connection'
            return 'Credentials'
        }
        if ($InboundParameters.ContainsKey('Credential') -and
            $null -ne $InboundParameters.Credential)
        {
            Connect-M365Tenant -Workload $Workload `
                -Credential $InboundParameters.Credential `
                -Url $Url `
                -SkipModuleReload $Global:CurrentModeIsExport
            $data.Add('ConnectionType', 'Credential')

            try
            {
                $tenantId = $InboundParameters.Credential.Username.Split('@')[1]
                $data.Add('Tenant', $tenantId)
            }
            catch
            {
                Write-Verbose -Message $_
            }

            Add-M365DSCTelemetryEvent -Data $data -Type 'Connection'
            return 'Credentials'
        }
    }
    # Case only Credential with ApplicationId is specified
    elseif ($null -ne $InboundParameters.Credential -and `
            -not [System.String]::IsNullOrEmpty($InboundParameters.ApplicationId) -and `
            [System.String]::IsNullOrEmpty($InboundParameters.TenantId) -and `
            [System.String]::IsNullOrEmpty($InboundParameters.CertificateThumbprint))
    {
        if ([System.String]::IsNullOrEmpty($Url))
        {
            Connect-M365Tenant -Workload $Workload `
                -ApplicationId $InboundParameters.ApplicationId `
                -Credential $InboundParameters.Credential `
                -SkipModuleReload $Global:CurrentModeIsExport
            $data.Add('ConnectionType', 'CredentialsWithApplicationId')

            try
            {
                $tenantId = $InboundParameters.Credential.Username.Split('@')[1]
                $data.Add('Tenant', $tenantId)
            }
            catch
            {
                Write-Verbose -Message $_
            }

            Add-M365DSCTelemetryEvent -Data $data -Type 'Connection'
            return 'CredentialsWithApplicationId'
        }
        else
        {
            Connect-M365Tenant -Workload $Workload `
                -ApplicationId $InboundParameters.ApplicationId `
                -Credential $InboundParameters.Credential `
                -Url $Url `
                -SkipModuleReload $Global:CurrentModeIsExport
            $data.Add('ConnectionType', 'CredentialsWithApplicationId')

            try
            {
                $tenantId = $InboundParameters.Credential.Username.Split('@')[1]
                $data.Add('Tenant', $tenantId)
            }
            catch
            {
                Write-Verbose -Message $_
            }

            Add-M365DSCTelemetryEvent -Data $data -Type 'Connection'
            return 'CredentialsWithApplicationId'
        }
    }
    # Case only the ServicePrincipal with Thumbprint parameters are specified
    elseif ($null -eq $InboundParameters.Credential -and `
            -not [System.String]::IsNullOrEmpty($InboundParameters.ApplicationId) -and `
            -not [System.String]::IsNullOrEmpty($InboundParameters.TenantId) -and `
            -not [System.String]::IsNullOrEmpty($InboundParameters.CertificatePath) -and `
            $null -ne $InboundParameters.CertificatePassword)
    {
        if ([System.String]::IsNullOrEmpty($url))
        {
            Write-Verbose -Message 'ApplicationId, TenantId, CertificatePath & CertificatePassword were specified. Connecting via Service Principal'
            Connect-M365Tenant -Workload $Workload `
                -ApplicationId $InboundParameters.ApplicationId `
                -TenantId $InboundParameters.TenantId `
                -CertificatePassword $InboundParameters.CertificatePassword.Password `
                -CertificatePath $InboundParameters.CertificatePath `
                -SkipModuleReload $Global:CurrentModeIsExport

            $data.Add('ConnectionType', 'ServicePrincipalWithPath')
            $data.Add('Tenant', $InboundParameters.TenantId)
            Add-M365DSCTelemetryEvent -Data $data -Type 'Connection'
            return 'ServicePrincipalWithPath'
        }
        #endregion

        # Case both authentication methods are attempted
        if ($null -ne $InboundParameters.Credential -and `
            (-not [System.String]::IsNullOrEmpty($InboundParameters.TenantId) -or `
                    -not [System.String]::IsNullOrEmpty($InboundParameters.CertificateThumbprint)))
        {
            $message = 'Both Authentication methods are attempted'
            Write-Verbose -Message $message
            $data.Add('Event', 'Error')
            $data.Add('Exception', $message)
            $errorText = "You can't specify both the Credential and one of {TenantId, CertificateThumbprint}"
            $data.Add('CustomMessage', $errorText)
            Add-M365DSCTelemetryEvent -Type 'Error' -Data $data
            throw $errorText
        }
        # Case no authentication method is specified
        elseif ($null -eq $InboundParameters.Credential -and `
                [System.String]::IsNullOrEmpty($InboundParameters.ApplicationId) -and `
                [System.String]::IsNullOrEmpty($InboundParameters.TenantId) -and `
                [System.String]::IsNullOrEmpty($InboundParameters.CertificateThumbprint))
        {
            $message = 'No Authentication method was provided'
            Write-Verbose -Message $message
            $message += "`r`nProvided Keys --> $($InboundParameters.Keys)"
            $data.Add('Event', 'Error')
            $data.Add('Exception', $message)
            $errorText = 'You must specify either the Credential or ApplicationId, TenantId and CertificateThumbprint parameters.'
            $data.Add('CustomMessage', $errorText)
            Add-M365DSCTelemetryEvent -Type 'Error' -Data $data
            throw $errorText
        }
        # Case only Credential is specified
        elseif ($null -ne $InboundParameters.Credential -and `
                [System.String]::IsNullOrEmpty($InboundParameters.ApplicationId) -and `
                [System.String]::IsNullOrEmpty($InboundParameters.TenantId) -and `
                [System.String]::IsNullOrEmpty($InboundParameters.CertificateThumbprint))
        {
            Write-Verbose -Message 'Credential was specified. Connecting via User Principal'
            if ([System.String]::IsNullOrEmpty($Url))
            {
                Connect-M365Tenant -Workload $Platform `
                    -Credential $InboundParameters.Credential `
                    -SkipModuleReload $Global:CurrentModeIsExport
            }
            else
            {
                Connect-M365Tenant -Workload $Platform `
                    -Credential $InboundParameters.Credential `
                    -ConnectionUrl $Url `
                    -SkipModuleReload $Global:CurrentModeIsExport
            }

            $data.Add('ConnectionType', 'Credential')
            try
            {
                $tenantId = $InboundParameters.Credential.Username.Split('@')[1]
                $data.Add('Tenant', $tenantId)
            }
            catch
            {
                Write-Verbose -Message $_
            }
            Add-M365DSCTelemetryEvent -Data $data -Type 'Connection'
            return 'Credentials'
        }
        # Case only the ApplicationID and Credentials parameters are specified
        elseif ($null -ne $InboundParameters.Credential -and `
                -not [System.String]::IsNullOrEmpty($InboundParameters.ApplicationId))
        {

            Connect-M365Tenant -Workload $Workload `
                -ApplicationId $InboundParameters.ApplicationId `
                -TenantId $InboundParameters.TenantId `
                -CertificatePassword $InboundParameters.CertificatePassword.Password `
                -CertificatePath $InboundParameters.CertificatePath `
                -Url $Url `
                -SkipModuleReload $Global:CurrentModeIsExport
        }
        $data.Add('ConnectionType', 'ServicePrincipalWithPath')
        $data.Add('Tenant', $InboundParameters.TenantId)
        Add-M365DSCTelemetryEvent -Data $data -Type 'Connection'

        return 'ServicePrincipalWithPath'
    }
    # Case only the ApplicationSecret, TenantId and ApplicationID are specified
    elseif ($null -eq $InboundParameters.Credential -and `
            -not [System.String]::IsNullOrEmpty($InboundParameters.ApplicationId) -and `
            -not [System.String]::IsNullOrEmpty($InboundParameters.TenantId) -and `
            -not [System.String]::IsNullOrEmpty($InboundParameters.ApplicationSecret))
    {
        if ([System.String]::IsNullOrEmpty($url))
        {
            Write-Verbose -Message 'ApplicationId, TenantId, ApplicationSecret were specified. Connecting via Service Principal'
            Connect-M365Tenant -Workload $Workload `
                -ApplicationId $InboundParameters.ApplicationId `
                -TenantId $InboundParameters.TenantId `
                -ApplicationSecret $InboundParameters.ApplicationSecret `
                -SkipModuleReload $Global:CurrentModeIsExport


            $data.Add('ConnectionType', 'ServicePrincipalWithSecret')
            $data.Add('Tenant', $InboundParameters.TenantId)
            Add-M365DSCTelemetryEvent -Data $data -Type 'Connection'
            return 'ServicePrincipalWithSecret'
        }
        else
        {
            Connect-M365Tenant -Workload $Workload `
                -ApplicationId $InboundParameters.ApplicationId `
                -TenantId $InboundParameters.TenantId `
                -ApplicationSecret $InboundParameters.ApplicationSecret `
                -Url $Url `
                -SkipModuleReload $Global:CurrentModeIsExport


            $data.Add('ConnectionType', 'ServicePrincipalWithSecret')
            $data.Add('Tenant', $InboundParameters.TenantId)
            Add-M365DSCTelemetryEvent -Data $data -Type 'Connection'
            return 'ServicePrincipalWithSecret'
        }
    }
    elseif ($InboundParameters.CertificateThumbprint -and $InboundParameters.ApplicationId -and $InboundParameters.TenantId)
    {
        Write-Verbose -Message 'ApplicationId, TenantId, CertificateThumbprint were specified. Connecting via Service Principal'
        Connect-M365Tenant -Workload $Workload `
            -ApplicationId $InboundParameters.ApplicationId `
            -TenantId $InboundParameters.TenantId `
            -CertificateThumbprint $InboundParameters.CertificateThumbprint `
            -SkipModuleReload $Global:CurrentModeIsExport `
            -Url $Url

        $data.Add('ConnectionType', 'ServicePrincipalWithThumbprint')
        $data.Add('Tenant', $InboundParameters.TenantId)
        Add-M365DSCTelemetryEvent -Data $data -Type 'Connection'
        return 'ServicePrincipalWithThumbprint'
    }
    # Case only Managed Identity and TenantId are specified
    elseif ($InboundParameters.ManagedIdentity -and `
            -not [System.String]::IsNullOrEmpty($InboundParameters.TenantId))
    {
        Write-Verbose -Message 'Connecting via managed identity'
        Connect-M365Tenant -Workload $Workload `
            -Identity `
            -TenantId $InboundParameters.TenantId `
            -SkipModuleReload $Global:CurrentModeIsExport


        $data.Add('ConnectionType', 'ManagedIdentity')
        $data.Add('Tenant', $Global:MSCloudLoginConnectionProfile.MicrosoftGraph.TenantId)
        Add-M365DSCTelemetryEvent -Data $data -Type 'Connection'
        return 'ManagedIdentity'
    }
    else
    {
        throw 'Could not determine authentication method'
    }
}

<#
.Description
This function gets the URL of the SPO Administration site

.Functionality
Internal
#>
function Get-SPOAdministrationUrl
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $false)]
        [switch]
        $UseMFA,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $Credential
    )

    if ($UseMFA)
    {
        $UseMFASwitch = @{UseMFA = $true }
    }
    else
    {
        $UseMFASwitch = @{ }
    }
    Write-Verbose -Message 'Connection to Azure AD is required to automatically determine SharePoint Online admin URL...'
    $ConnectionMode = New-M365DSCConnection -Workload 'MicrosoftGraph' `
        -InboundParameters $PSBoundParameters
    Write-Verbose -Message 'Getting SharePoint Online admin URL...'
    [Array]$defaultDomain = Get-MgBetaDomain | Where-Object { ($_.Id -like '*.onmicrosoft.com' -or $_.Id -like '*.onmicrosoft.de' -or $_.Id -like '*.onmicrosoft.us') -and $_.IsInitial -eq $true } # We don't use IsDefault here because the default could be a custom domain

    if ($defaultDomain[0].Id -like '*.onmicrosoft.com*')
    {
        $global:tenantName = $defaultDomain[0].Id -replace '.onmicrosoft.com', ''
    }
    elseif ($defaultDomain[0].Id -like '*.onmicrosoft.de*')
    {
        $global:tenantName = $defaultDomain[0].Id -replace '.onmicrosoft.de', ''
    }
    $global:AdminUrl = "https://$global:tenantName-admin.sharepoint.com"
    Write-Verbose -Message "SharePoint Online admin URL is $global:AdminUrl"
    return $global:AdminUrl
}

<#
.Description
This function gets the name of the M365 tenant

.Functionality
Internal
#>
function Get-M365TenantName
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $false)]
        [switch]
        $UseMFA,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $Credential
    )

    if ($UseMFA)
    {
        $UseMFASwitch = @{UseMFA = $true }
    }
    else
    {
        $UseMFASwitch = @{ }
    }
    Write-Verbose -Message 'Connection to Azure AD is required to automatically determine SharePoint Online admin URL...'
    $ConnectionMode = New-M365DSCConnection -Workload 'MicrosoftGraph' `
        -InboundParameters $PSBoundParameters
    Write-Verbose -Message 'Getting SharePoint Online admin URL...'
    [Array]$defaultDomain = Get-MgBetaDomain | Where-Object { ($_.Id -like '*.onmicrosoft.com' -or $_.Id -like '*.onmicrosoft.de') -and $_.IsInitial -eq $true } # We don't use IsDefault here because the default could be a custom domain

    if ($defaultDomain[0].Id -like '*.onmicrosoft.com*')
    {
        $tenantName = $defaultDomain[0].Id -replace '.onmicrosoft.com', ''
    }
    elseif ($defaultDomain[0].Id -like '*.onmicrosoft.de*')
    {
        $tenantName = $defaultDomain[0].Id -replace '.onmicrosoft.de', ''
    }

    Write-Verbose -Message "M365 tenant name is $tenantName"
    return $tenantName
}

<#
.Description
This function splits the provided array in the specified number of arrays

.Functionality
Internal
#>
function Split-ArrayByParts
{
    [OutputType([System.Object[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object[]]
        $Array,

        [Parameter(Mandatory = $true)]
        [System.Uint32]
        $Parts
    )

    if ($Parts)
    {
        $PartSize = [Math]::Ceiling($Array.Count / $Parts)
    }
    $outArray = New-Object 'System.Collections.Generic.List[PSObject]'

    for ($i = 1; $i -le $Parts; $i++)
    {
        $start = (($i - 1) * $PartSize)

        if ($start -lt $Array.Count)
        {
            $end = (($i) * $PartSize) - 1
            if ($end -ge $Array.count)
            {
                $end = $Array.count - 1
            }
            $outArray.Add(@($Array[$start..$end]))
        }
    }
    return , $outArray
}

<#
.Description
This function runs provided code and makes sure throtteling is not causing any issues

.Functionality
Internal
#>
function Invoke-M365DSCCommand
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ScriptBlock]
        $ScriptBlock,

        [Parameter()]
        [System.String]
        $InvokationPath,

        [Parameter()]
        [Object[]]
        $Arguments,

        [Parameter()]
        [System.UInt32]
        $Backoff = 2
    )

    $InformationPreference = 'SilentlyContinue'
    $WarningPreference = 'SilentlyContinue'
    $ErrorActionPreference = 'Stop'
    try
    {
        if (-not [System.String]::IsNullOrEmpty($InvokationPath))
        {
            $baseScript = "Import-Module '$InvokationPath\*.psm1' -Force;"
        }

        $invokeArgs = @{
            ScriptBlock = [ScriptBlock]::Create($baseScript + $ScriptBlock.ToString())
        }
        if ($null -ne $Arguments)
        {
            $invokeArgs.Add('ArgumentList', $Arguments)
        }
        return Invoke-Command @invokeArgs
    }
    catch
    {
        if ($_.Exception -like '*M365DSC - *')
        {
            Write-Warning $_.Exception
        }
        else
        {
            if ($Backoff -le 128)
            {
                $NewBackoff = $Backoff * 2
                Write-Warning "    * Throttling detected. Waiting for {$NewBackoff seconds}"
                Start-Sleep -Seconds $NewBackoff
                return Invoke-M365DSCCommand -ScriptBlock $ScriptBlock -Backoff $NewBackoff -Arguments $Arguments -InvokationPath $InvokationPath
            }
            else
            {
                Write-Warning $_
            }
        }
    }
}

<#
.Description
This function creates a PSCustomObject of the provided input values

.Functionality
Internal
#>
function Get-SPOUserProfilePropertyInstance
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Key,

        [Parameter()]
        [System.String]
        $Value
    )

    $result = [PSCustomObject]@{
        Key   = $Key
        Value = $Value
    }

    return $result
}

<#
.Description
This function downloads and installs the Dev branch of Microsoft365DSC on the local machine

.Parameter Scope
Specifies the scope of the update of the module. The default value is AllUsers(needs to run as elevated user).

.Example
Install-M365DSCDevBranch

.Example
Install-M365DSCDevBranch -Scope CurrentUser

.Functionality
Public
#>
function Install-M365DSCDevBranch
{
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet("CurrentUser", "AllUsers")]
        $Scope = "AllUsers"
    )

    try {

        #region Download and Extract Dev branch's ZIP
        Write-Host 'Downloading the Zip package...' -NoNewline
        $url = 'https://github.com/microsoft/Microsoft365DSC/archive/Dev.zip'
        $output = "$($env:Temp)\dev.zip"
        $extractPath = $env:Temp + '\O365Dev'
        Write-Host 'Done' -ForegroundColor Green

        Invoke-WebRequest -Uri $url -OutFile $output

        Expand-Archive $output -DestinationPath $extractPath -Force
        #endregion

        #region Install All Dependencies
        $manifest = Import-PowerShellDataFile "$extractPath\Microsoft365DSC-Dev\Modules\Microsoft365DSC\Microsoft365DSC.psd1"
        $dependencies = $manifest.RequiredModules
        if ((-not(([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) -and ($Scope -eq "AllUsers"))
        {
            Write-Error 'Cannot update the dependencies for Microsoft365DSC. You need to run this command as a local administrator.'
        }
        else
        {
            foreach ($dependency in $dependencies)
            {
                Write-Host "Installing {$($dependency.ModuleName)}..." -NoNewline
                $existingModule = Get-Module $dependency.ModuleName -ListAvailable | Where-Object -FilterScript { $_.Version -eq $dependency.RequiredVersion }
                if ($null -eq $existingModule)
                {
                    Install-Module $dependency.ModuleName -RequiredVersion $dependency.RequiredVersion -Force -AllowClobber -Scope $Scope | Out-Null
                }
                Import-Module $dependency.ModuleName -Force | Out-Null
                Write-Host 'Done' -ForegroundColor Green
            }
        }
        #endregion

        #region Install M365DSC
        Write-Host 'Updating the Core Microsoft365DSC module...' -NoNewline
        $defaultPath = 'C:\Program Files\WindowsPowerShell\Modules\Microsoft365DSC\'
        $currentVersionPath = $defaultPath + ([Version]$($manifest.ModuleVersion)).ToString()

        Copy-Item "$extractPath\Microsoft365DSC-Dev\Modules\Microsoft365DSC\*" `
            -Destination $defaultPath -Recurse -Force

        Import-Module ($defaultPath + 'Microsoft365DSC.psd1') -Force | Out-Null
        $oldModule = Get-Module 'Microsoft365DSC' | Where-Object -FilterScript { $_.ModuleBase -eq $currentVersionPath }
        Remove-Module $oldModule -Force | Out-Null
        if (Test-Path $currentVersionPath)
        {
            try
            {
                Remove-Item $currentVersionPath -Recurse -Confirm:$false -Force `
                    -ErrorAction Stop
            }
            catch
            {
                Write-Verbose -Message $_
            }
        }
        Write-Host 'Done' -ForegroundColor Green
        #endregion
    }
    catch
    {
        New-M365DSCLogEntry -Message 'Error installing Dev Branch:' `
            -Exception $_ `
            -Source $($MyInvocation.MyCommand.Source)
        Write-Error $_
    }
}

<#
.Description
This function downloads all apps installed in SPO

.Functionality
Internal
#>
function Get-AllSPOPackages
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable[]])]
    param
    (
        [Parameter()]
        [System.Management.Automation.PSCredential]
        $Credential,

        [Parameter()]
        [System.String]
        $ApplicationId,

        [Parameter()]
        [System.String]
        $TenantId,

        [Parameter()]
        [System.String]
        $CertificatePath,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $CertificatePassword,

        [Parameter()]
        [System.String]
        $CertificateThumbprint,

        [Parameter()]
        [Switch]
        $ManagedIdentity
    )

    try
    {
        $ConnectionMode = New-M365DSCConnection -Workload 'PnP' `
            -InboundParameters $PSBoundParameters

        $tenantAppCatalogUrl = Get-PnPTenantAppCatalogUrl -ErrorAction Stop

        $ConnectionMode = New-M365DSCConnection -Workload 'PnP' `
            -InboundParameters $PSBoundParameters `
            -Url $tenantAppCatalogUrl

        $filesToDownload = @()
        $allFiles = @()
        if ($null -ne $tenantAppCatalogUrl)
        {
            try
            {
                [Array]$spfxFiles = Find-PnPFile -List 'AppCatalog' -Match '*.sppkg' -ErrorAction Stop
                [Array]$appFiles = Find-PnPFile -List 'AppCatalog' -Match '*.app' -ErrorAction Stop

                $allFiles = $spfxFiles + $appFiles

                foreach ($file in $allFiles)
                {
                    $filesToDownload += @{Name = $file.Name; Site = $tenantAppCatalogUrl; Title = $file.Title }
                }
            }
            catch
            {
                New-M365DSCLogEntry -Message $_.Exception.Message `
                -Exception $_ `
                -Source $($MyInvocation.MyCommand.Source) `
                -TenantId $TenantId `
                -Credential $Credential
            }
        }
        return $filesToDownload
    }
    catch
    {
        Write-Verbose -Message $_
    }
    return $null
}

<#
.Description
This function removes all items that have a Null value from the provided hashtable

.Functionality
Internal
#>
function Remove-NullEntriesFromHashtable
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.COllections.HashTable]
        $Hash
    )

    $keysToRemove = @()
    foreach ($key in $Hash.Keys)
    {
        if ([System.String]::IsNullOrEmpty($Hash.$key))
        {
            $keysToRemove += $key
        }
    }

    foreach ($key in $keysToRemove)
    {
        $Hash.Remove($key) | Out-Null
    }

    return $Hash
}

<#
.Description
This function compares a created export with the specified M365DSC Blueprint

.Parameter BluePrintUrl
Specifies the url to the blueprint to which the tenant should be compared.

.Parameter OutputReportPath
Specifies the path of the report that will be created.

.Parameter Credentials
Specifies the credentials that will be used for authentication.

.Parameter ApplicationId
Specifies the application id to be used for authentication.

.Parameter ApplicationSecret
Specifies the application secret of the application to be used for authentication.

.Parameter TenantId
Specifies the id of the tenant.

.Parameter CertificateThumbprint
Specifies the thumbprint to be used for authentication.

.Parameter CertificatePassword
Specifies the password of the PFX file which is used for authentication.

.Parameter CertificatePath
Specifies the path of the PFX file which is used for authentication.

.Parameter HeaderFilePath
Specifies that file that contains a custom header for the report.

.Parameter ExcludedProperties
Specifies the name of parameters that should not be assessed as part of the report. The names speficied will apply to all resources where they are encountered.

.Parameter ExcludedResources
Specifies the name of resources that should not be assessed as part of the report.

.Example
Assert-M365DSCBlueprint -BluePrintUrl 'C:\DS\blueprint.m365' -OutputReportPath 'C:\DSC\BlueprintReport.html'

.Example
Assert-M365DSCBlueprint -BluePrintUrl 'C:\DS\blueprint.m365' -OutputReportPath 'C:\DSC\BlueprintReport.html' -Credentials $credentials -HeaderFilePath 'C:\DSC\ReportCustomHeader.html'

.Example
Assert-M365DSCBlueprint -BluePrintUrl 'C:\DS\blueprint.m365' -OutputReportPath 'C:\DSC\BlueprintReport.html' -ApplicationId $clientid -TenantId $tenantId -CertificateThumbprint $certthumbprint -HeaderFilePath 'C:\DSC\ReportCustomHeader.html'

.Functionality
Public
#>
function Assert-M365DSCBlueprint
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $BluePrintUrl,

        [Parameter(Mandatory = $true)]
        [System.String]
        $OutputReportPath,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $Credentials,

        [Parameter()]
        [System.String]
        $ApplicationId,

        [Parameter()]
        [System.String]
        $TenantId,

        [Parameter()]
        [System.String]
        $CertificatePath,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $CertificatePassword,

        [Parameter()]
        [System.String]
        $CertificateThumbprint,

        [Parameter()]
        [System.String]
        $HeaderFilePath,

        [Parameter()]
        [System.String]
        [ValidateSet('HTML', 'JSON')]
        $Type = 'HTML',

        [Parameter()]
        [System.String[]]
        $ExcludedProperties,

        [Parameter()]
        [System.String[]]
        $ExcludedResources
    )

    $InformationPreference = 'SilentlyContinue'
    $WarningPreference = 'SilentlyContinue'

    #Ensure the proper dependencies are installed in the current environment.
    Confirm-M365DSCDependencies

    #region Telemetry
    $data = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $data.Add('Event', 'AssertBlueprint')
    $data.Add('BluePrint', $BluePrintUrl)
    Add-M365DSCTelemetryEvent -Data $data
    #endregion

    $TempBluePrintName = (New-Guid).ToString() + '.M365'
    $LocalBluePrintPath = Join-Path -Path $env:Temp -ChildPath $TempBluePrintName
    try
    {
        # Download the BluePrint locally in a temp location
        Invoke-WebRequest -Uri $BluePrintUrl -OutFile $LocalBluePrintPath
    }
    catch
    {
        # If the download failed, we assume the provided Url was a local path
        # and we try copying the item instead.
        try
        {
            Copy-Item -Path $BluePrintUrl -Destination $LocalBluePrintPath
        }
        catch
        {
            throw $_
        }
    }

    if ((Test-Path -Path $LocalBluePrintPath))
    {
        # Parse the content of the BluePrint into an array of PowerShell Objects
        $fileContent = Get-Content $LocalBluePrintPath -Raw
        $startPosition = $fileContent.IndexOf(' -ModuleVersion')
        if ($startPosition -gt 0)
        {
            $endPosition = $fileContent.IndexOf("`r", $startPosition)
            $fileContent = $fileContent.Remove($startPosition, $endPosition - $startPosition)
        }

        try
        {
            $parsedBluePrint = ConvertTo-DSCObject -Content $fileContent
        }
        catch
        {
            throw $_
        }

        # Generate an Array of Resource Types contained in the BluePrint
        $ResourcesInBluePrint = @()
        foreach ($resource in $parsedBluePrint)
        {
            if ($resource.ResourceName -in $ExcludedResources)
            {
                continue
            }
            if ($ResourcesInBluePrint -notcontains $resource.ResourceName)
            {
                $ResourcesInBluePrint += $resource.ResourceName
            }
        }

        if ([String]::IsNullOrEmpty($ResourcesInBluePrint))
        {
            if (![String]::IsNullOrEmpty($ExcludedResources))
            {
                Write-Host 'All resources were excluded from BluePrint, aborting'
            }
            else
            {
                Write-Host 'Malformed BluePrint, aborting'
            }
            break
        }

        Write-Host "Selected BluePrint contains ($($ResourcesInBluePrint.Length)) components to assess."

        # Call the Export-M365DSCConfiguration cmdlet to extract only the resource
        # types contained within the BluePrint;
        Write-Host "Initiating the Export of those ($($ResourcesInBluePrint.Length)) components from the tenant..."
        $TempExportName = (New-Guid).ToString() + '.ps1'
        Export-M365DSCConfiguration -Components $ResourcesInBluePrint `
            -Path $env:temp `
            -FileName $TempExportName `
            -Credential $Credentials `
            -ApplicationId $ApplicationId `
            -ApplicationSecret $ApplicationSecret `
            -TenantId $TenantId `
            -CertificateThumbprint $CertificateThumbprint `
            -CertificatePath $CertificatePath `
            -CertificatePassword $CertificatePassword

        # Call the New-M365DSCDeltaReport configuration to generate the Delta Report between
        # the BluePrint and the extracted resources;
        $ExportPath = Join-Path -Path $env:Temp -ChildPath $TempExportName
        New-M365DSCDeltaReport -Source $ExportPath `
            -Destination $LocalBluePrintPath `
            -OutputPath $OutputReportPath `
            -DriftOnly:$true `
            -IsBlueprintAssessment:$true `
            -HeaderFilePath $HeaderFilePath `
            -Type $Type `
            -ExcludedProperties $ExcludedProperties `
            -ExcludedResources $ExcludedResources
    }
    else
    {
        Write-Error "M365DSC Template Path {$LocalBluePrintPath} does not exist."
    }
}

<#
.Description
This function checks if new versions are available for the M365DSC dependencies

.Example
Test-M365DSCDependenciesForNewVersions

.Functionality
Public
#>
function Test-M365DSCDependenciesForNewVersions
{
    [CmdletBinding()]
    param ()

    $InformationPreference = 'Continue'
    $currentPath = Join-Path -Path $PSScriptRoot -ChildPath '..\' -Resolve
    $manifest = Import-PowerShellDataFile "$currentPath/Dependencies/Manifest.psd1"
    $dependencies = $manifest.Dependencies
    $i = 1
    Import-Module PowerShellGet -Force

    foreach ($dependency in $dependencies)
    {
        Write-Progress -Activity 'Scanning Dependencies' -PercentComplete ($i / $dependencies.Count * 100)
        try
        {
            $moduleInGallery = Find-Module $dependency.ModuleName
            [array]$moduleInstalled = Get-Module $dependency.ModuleName -ListAvailable | Select-Object Version
            if ($moduleInstalled)
            {
                $modules = $moduleInstalled | Sort-Object Version -Descending
            }
            $moduleInstalled = $modules[0]
            if (-not $modules -or [Version]($moduleInGallery.Version) -gt [Version]($moduleInstalled[0].Version))
            {
                Write-Host "New version of {$($dependency.ModuleName)} is available {$($moduleInGallery.Version)}"
            }
        }
        catch
        {
            Write-Host $_
            Write-Host "New version of {$($dependency.ModuleName)} is available"
        }
        $i++
    }

    # The progress bar seems to hang sometimes. Make sure it is no longer displayed.
    Write-Progress -Activity 'Scanning Dependencies' -Completed
}

<#
.Description
This function installs all missing M365DSC dependencies

.Parameter Force
Specifies that all dependencies should be forcefully imported again.

.Parameter ValidateOnly
Specifies that the function should only return the dependencies that are not installed.

.Parameter Scope
Specifies the scope of the update of the module. The default value is AllUsers(needs to run as elevated user).

.Example
Update-M365DSCDependencies

.Example
Update-M365DSCDependencies -Force

.Example
Update-M365DSCDependencies -Scope CurrenUser

.Functionality
Public
#>
function Update-M365DSCDependencies
{
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [Switch]
        $Force,

        [Parameter()]
        [Switch]
        $ValidateOnly,
        [Parameter()]
        [ValidateSet("CurrentUser", "AllUsers")]
        $Scope = "AllUsers"
    )

    try
    {
        $Global:MaximumFunctionCount = 32767

        $InformationPreference = 'Continue'
        $currentPath = Join-Path -Path $PSScriptRoot -ChildPath '..\' -Resolve
        $manifest = Import-PowerShellDataFile "$currentPath/Dependencies/Manifest.psd1"
        $dependencies = $manifest.Dependencies
        $i = 1

        $returnValue = @()

        foreach ($dependency in $dependencies)
        {
            Write-Progress -Activity 'Scanning Dependencies' -PercentComplete ($i / $dependencies.Count * 100)
            try
            {
                if (-not $Force)
                {
                    $found = Get-Module $dependency.ModuleName -ListAvailable | Where-Object -FilterScript { $_.Version -eq $dependency.RequiredVersion }
                }

                if ((-not $found -or $Force) -and -not $ValidateOnly)
                {
                    if ((-not(([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) -and ($Scope -eq "AllUsers"))
                    {
                        Write-Error 'Cannot update the dependencies for Microsoft365DSC. You need to run this command as a local administrator.'
                    }
                    else
                    {
                        Write-Information -MessageData "Installing $($dependency.ModuleName) version {$($dependency.RequiredVersion)}"
                        Remove-Module $dependency.ModuleName -Force -ErrorAction SilentlyContinue
                        if ($dependency.ModuleName -like 'Microsoft.Graph*')
                        {
                            Remove-Module 'Microsoft.Graph.Authentication' -Force -ErrorAction SilentlyContinue
                        }
                        Remove-Module $dependency.ModuleName -Force -ErrorAction SilentlyContinue
                        Install-Module $dependency.ModuleName -RequiredVersion $dependency.RequiredVersion -AllowClobber -Force -Scope "$Scope"
                    }
                }

                if (-not $found -and $validateOnly)
                {
                    $returnValue += $dependency
                }
            }
            catch
            {
                Write-Host "Could not update or import {$($dependency.ModuleName)}"
                Write-Host "Error-Mesage: $($_.Exception.Message)"
            }

            $i++
        }

        # The progress bar seems to hang sometimes. Make sure it is no longer displayed.
        Write-Progress -Activity 'Scanning Dependencies' -Completed

        if ($ValidateOnly)
        {
            return $returnValue
        }

    }
    catch
    {
        New-M365DSCLogEntry -Message 'Error Updating Dependencies:' `
            -Exception $_ `
            -Source $($MyInvocation.MyCommand.Source)
        Write-Error $_
    }
}

<#
.Description
This function uninstalls all previous M365DSC dependencies and older versions of the module.
.Example
Uninstall-M365DSCOutdatedDependencies
.Functionality
Public
#>
function Uninstall-M365DSCOutdatedDependencies
{
    [CmdletBinding()]
    param()

    try
    {
        $InformationPreference = 'Continue'

        [array]$microsoft365DscModules = Get-Module Microsoft365DSC -ListAvailable
        $outdatedMicrosoft365DscModules = $microsoft365DscModules | Sort-Object Version | Select-Object -SkipLast 1

        foreach ($module in $outdatedMicrosoft365DscModules)
        {
            try
            {
                Write-Information -MessageData "Uninstalling $($module.Name) Version {$($module.Version)}"
                if (Test-Path -Path $($module.Path))
                {
                    Remove-Item $($module.Path) -Force -Recurse
                }
            }
            catch
            {
                New-M365DSCLogEntry -Message "Could not uninstall $($module.Name) Version $($module.Version)" `
                    -Exception $_ `
                    -Source $($MyInvocation.MyCommand.Source)
                Write-Host "Could not uninstall $($module.Name) Version $($module.Version)"
            }
        }

        $currentPath = Join-Path -Path $PSScriptRoot -ChildPath '..\' -Resolve
        $manifest = Import-PowerShellDataFile "$currentPath\Dependencies\Manifest.psd1"

        $allDependenciesExceptAuth = $manifest.Dependencies | Where-Object { $_.ModuleName -ne 'Microsoft.Graph.Authentication' }

        $i = 1
        foreach ($dependency in $allDependenciesExceptAuth)
        {
            Write-Progress -Activity 'Scanning Dependencies' -PercentComplete ($i / $allDependenciesExceptAuth.Count * 100)
            try
            {
                $found = Get-Module $dependency.ModuleName -ListAvailable | Where-Object -FilterScript { $_.Version -ne $dependency.RequiredVersion }
                foreach ($foundModule in $found)
                {
                    try
                    {
                        Write-Information -MessageData "Uninstalling $($foundModule.Name) Version {$($foundModule.Version)}"
                        if (Test-Path -Path $($foundModule.Path))
                        {
                            Remove-Item $($foundModule.ModuleBase) -Force -Recurse
                        }
                    }
                    catch
                    {
                        New-M365DSCLogEntry -Message "Could not uninstall $($foundModule.Name) Version $($foundModule.Version)" `
                            -Exception $_ `
                            -Source $($MyInvocation.MyCommand.Source)
                        Write-Host "Could not uninstall $($foundModule.Name) Version $($foundModule.Version)"
                    }
                }
            }
            catch
            {
                Write-Host "Could not uninstall {$($dependency.ModuleName)}"
            }
            $i++
        }
    }
    catch
    {
        New-M365DSCLogEntry -Message 'Error Uninstalling Outdated Dependencies:' `
            -Exception $_ `
            -Source $($MyInvocation.MyCommand.Source)
        Write-Error $_
    }

    $authModule = $manifest.Dependencies | Where-Object { $_.ModuleName -eq 'Microsoft.Graph.Authentication' }
    try
    {
        Write-Information -MessageData 'Checking Microsoft.Graph.Authentication'
        $found = Get-Module $authModule.ModuleName -ListAvailable | Where-Object -FilterScript { $_.Version -ne $authModule.RequiredVersion }
        foreach ($foundModule in $found)
        {
            try
            {
                Write-Information -MessageData "Uninstalling $($foundModule.Name) version {$($foundModule.Version)}"
                if (Test-Path -Path $($foundModule.Path))
                {
                    Remove-Item $($foundModule.ModuleBase) -Force -Recurse
                }
            }
            catch
            {
                Write-Host "Could not uninstall $($foundModule.Name) Version $($foundModule.Version) "
            }
        }
    }
    catch
    {
        Write-Host "Could not uninstall {$($dependency.ModuleName)}"
    }
}

<#
.Description
This function removes all empty values from a dictionary object

.Functionality
Internal
#>
function Remove-EmptyValue
{
    [alias('Remove-EmptyValues')]
    [CmdletBinding()]
    param
    (
        [alias('Splat', 'IDictionary')][Parameter(Mandatory)][System.Collections.IDictionary] $Hashtable,
        [string[]] $ExcludeParameter,
        [switch] $Recursive,
        [int] $Rerun
    )

    foreach ($Key in [string[]] $Hashtable.Keys)
    {
        if ($Key -notin $ExcludeParameter)
        {
            if ($Recursive)
            {
                if ($Hashtable[$Key] -is [System.Collections.IDictionary])
                {
                    if ($Hashtable[$Key].Count -eq 0)
                    {
                        $Hashtable.Remove($Key)
                    }
                    else
                    {
                        Remove-EmptyValue -Hashtable $Hashtable[$Key] -Recursive:$Recursive
                    }
                }
                else
                {
                    if ($null -eq $Hashtable[$Key] -or ($Hashtable[$Key] -is [string] -and $Hashtable[$Key] -eq '') -or ($Hashtable[$Key] -is [System.Collections.IList] -and $Hashtable[$Key].Count -eq 0))
                    {
                        $Hashtable.Remove($Key)
                    }
                }
            }
            else
            {
                if ($null -eq $Hashtable[$Key] -or ($Hashtable[$Key] -is [string] -and $Hashtable[$Key] -eq '') -or ($Hashtable[$Key] -is [System.Collections.IList] -and $Hashtable[$Key].Count -eq 0))
                {
                    $Hashtable.Remove($Key)
                }
            }
        }
    }
    if ($Rerun)
    {
        for ($i = 0; $i -lt $Rerun; $i++)
        {
            Remove-EmptyValue -Hashtable $Hashtable -Recursive:$Recursive
        }
    }
}


<#
.Description
This function updates the exported results with the specified authentication method

.Functionality
Internal
#>
function Update-M365DSCExportAuthenticationResults
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        [ValidateSet('ServicePrincipalWithThumbprint', 'ServicePrincipalWithSecret', 'ServicePrincipalWithPath', 'CredentialsWithApplicationId', 'Credentials', 'ManagedIdentity')]
        $ConnectionMode,

        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]
        $Results
    )

    if ($Results.ContainsKey('ManagedIdentity') -and -not $Results.ManagedIdentity)
    {
        $Results.Remove('ManagedIdentity')
    }
    if ($ConnectionMode -eq 'Credentials')
    {
        $Results.Credential = Resolve-Credentials -UserName 'credential'
        if ($Results.ContainsKey('ApplicationId'))
        {
            $Results.Remove('ApplicationId') | Out-Null
        }
        if ($Results.ContainsKey('TenantId'))
        {
            $Results.Remove('TenantId') | Out-Null
        }
        if ($Results.ContainsKey('ApplicationSecret'))
        {
            $Results.Remove('ApplicationSecret') | Out-Null
        }
        if ($Results.ContainsKey('CertificateThumbprint'))
        {
            $Results.Remove('CertificateThumbprint') | Out-Null
        }
        if ($Results.ContainsKey('CertificatePath'))
        {
            $Results.Remove('CertificatePath') | Out-Null
        }
        if ($Results.ContainsKey('CertificatePassword'))
        {
            $Results.Remove('CertificatePassword') | Out-Null
        }
    }
    else
    {
        if ($Results.ContainsKey('Credential') -and $ConnectionMode -ne 'CredentialsWithApplicationId')
        {
            $Results.Remove('Credential') | Out-Null
        }
        elseif ($Results.ContainsKey('Credential') -and $ConnectionMode -eq 'CredentialsWithApplicationId')
        {
            $Results.Credential = Resolve-Credentials -UserName 'credential'
        }
        if (-not [System.String]::IsNullOrEmpty($Results.ApplicationId))
        {
            $Results.ApplicationId = "`$ConfigurationData.NonNodeData.ApplicationId"
        }
        else
        {
            try
            {
                $Results.Remove('ApplicationId') | Out-Null
            }
            catch
            {
                Write-Verbose -Message 'Error removing ApplicationId from Update-M365DSCExportAuthenticationResults'
            }
        }
        if (-not [System.String]::IsNullOrEmpty($Results.CertificateThumbprint))
        {
            $Results.CertificateThumbprint = "`$ConfigurationData.NonNodeData.CertificateThumbprint"
        }
        else
        {
            try
            {
                $Results.Remove('CertificateThumbprint') | Out-Null
            }
            catch
            {
                Write-Verbose -Message 'Error removing CertificateThumbprint from Update-M365DSCExportAuthenticationResults'
            }
        }
        if (-not [System.String]::IsNullOrEmpty($Results.CertificatePath))
        {
            $Results.CertificatePath = "`$ConfigurationData.NonNodeData.CertificatePath"
        }
        else
        {
            try
            {
                $Results.Remove('CertificatePath') | Out-Null
            }
            catch
            {
                Write-Verbose -Message 'Error removing CertificatePath from Update-M365DSCExportAuthenticationResults'
            }
        }
        if (-not [System.String]::IsNullOrEmpty($Results.TenantId))
        {
            $Results.TenantId = "`$ConfigurationData.NonNodeData.TenantId"
        }
        else
        {
            try
            {
                $Results.Remove('TenantId') | Out-Null
            }
            catch
            {
                Write-Verbose -Message 'Error removing TenantId from Update-M365DSCExportAuthenticationResults'
            }
        }
        if (-not [System.String]::IsNullOrEmpty($Results.ApplicationSecret))
        {
            $Results.ApplicationSecret = "New-Object System.Management.Automation.PSCredential ('ApplicationSecret', (ConvertTo-SecureString `$ConfigurationData.NonNodeData.ApplicationSecret -AsPlainText -Force))"
        }
        else
        {
            try
            {
                $Results.Remove('ApplicationSecret') | Out-Null
            }
            catch
            {
                Write-Verbose -Message 'Error removing ApplicationSecret from Update-M365DSCExportAuthenticationResults'
            }
        }
        if ($null -ne $Results.CertificatePassword)
        {
            $Results.CertificatePassword = Resolve-Credentials -UserName 'CertificatePassword'
        }
        else
        {
            try
            {
                $Results.Remove('CertificatePassword') | Out-Null
            }
            catch
            {
                Write-Verbose -Message 'Error removing CertificatePassword from Update-M365DSCExportAuthenticationResults'
            }
        }
    }
    return $Results
}

<#
.Description
This function generates DSC string from an exported result hashtable

.Functionality
Internal
#>
function Get-M365DSCExportContentForResource
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $ResourceName,

        [Parameter(Mandatory = $true)]
        [System.String]
        [ValidateSet('ServicePrincipalWithThumbprint', 'ServicePrincipalWithSecret', 'ServicePrincipalWithPath', 'CredentialsWithApplicationId', 'Credentials', 'ManagedIdentity')]
        $ConnectionMode,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ModulePath,

        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]
        $Results,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $Credential
    )

    $OrganizationName = ''
    if ($ConnectionMode -like 'ServicePrincipal*' -or `
            $ConnectionMode -eq 'ManagedIdentity')
    {
        $OrganizationName = $Results.TenantId
    }
    else
    {
        $OrganizationName = $Credential.UserName.Split('@')[1]
    }

    # Ensure the string properties are properly formatted;
    $Results = Format-M365DSCString -Properties $Results `
        -ResourceName $ResourceName

    $primaryKey = ''
    if ($Results.ContainsKey('IsSingleInstance'))
    {
        $primaryKey = ''
    }
    elseif ($Results.ContainsKey('DisplayName'))
    {
        $primaryKey = $Results.DisplayName
    }
    elseif ($Results.ContainsKey('Identity'))
    {
        $primaryKey = $Results.Identity
    }
    elseif ($Results.ContainsKey('Id'))
    {
        $primaryKey = $Results.Id
    }
    elseif ($Results.ContainsKey('Name'))
    {
        $primaryKey = $Results.Name
    }
    elseif ($Results.ContainsKey('Title'))
    {
        $primaryKey = $Results.Title
    }
    elseif ($Results.ContainsKey('CdnType'))
    {
        $primaryKey = $Results.CdnType
    }
    elseif ($Results.ContainsKey('Usage'))
    {
        $primaryKey = $Results.Usage
    }

    $instanceName = $ResourceName
    if (-not [System.String]::IsNullOrEmpty($primaryKey))
    {
        $instanceName += "-$primaryKey"
    }

    if ($Results.ContainsKey('Workload'))
    {
        $instanceName += "-$($Results.Workload)"
    }

    # Check to see if a resource with this exact name was already exported, if so, append a number to the end.
    $i = 2
    $tempName = $instanceName.Replace('"', '')
    while ($null -ne $Global:M365DSCExportedResourceInstancesNames -and `
           $Global:M365DSCExportedResourceInstancesNames.Contains($tempName))
    {
        $tempName = $instanceName + "-" + $i.ToString()
        $i++
    }
    $instanceName = $tempName
    [string[]]$Global:M365DSCExportedResourceInstancesNames += $tempName

    $content = [System.Text.StringBuilder]::New()
    [void]$content.Append("        $ResourceName `"$instanceName`"`r`n")
    [void]$content.Append("        {`r`n")
    $partialContent = Get-DSCBlock -Params $Results -ModulePath $ModulePath
    # Test for both Credentials and CredentialsWithApplicationId
    if ($ConnectionMode -match 'Credentials')
    {
        $partialContent = Convert-DSCStringParamToVariable -DSCBlock $partialContent `
            -ParameterName 'Credential'
        if (![System.String]::IsNullOrEmpty($Results.ApplicationId))
        {
            $partialContent = Convert-DSCStringParamToVariable -DSCBlock $partialContent `
                -ParameterName 'ApplicationId'
        }
    }
    else
    {
        if (![System.String]::IsNullOrEmpty($Results.ApplicationId))
        {
            $partialContent = Convert-DSCStringParamToVariable -DSCBlock $partialContent `
                -ParameterName 'ApplicationId'
        }
        if (![System.String]::IsNullOrEmpty($Results.TenantId))
        {
            $partialContent = Convert-DSCStringParamToVariable -DSCBlock $partialContent `
                -ParameterName 'TenantId'
        }
        if (![System.String]::IsNullOrEmpty($Results.ApplicationSecret))
        {
            $partialContent = Convert-DSCStringParamToVariable -DSCBlock $partialContent `
                -ParameterName 'ApplicationSecret'
        }
        if (![System.String]::IsNullOrEmpty($Results.CertificatePath))
        {
            $partialContent = Convert-DSCStringParamToVariable -DSCBlock $partialContent `
                -ParameterName 'CertificatePath'
        }
        if (![System.String]::IsNullOrEmpty($Results.CertificateThumbprint))
        {
            $partialContent = Convert-DSCStringParamToVariable -DSCBlock $partialContent `
                -ParameterName 'CertificateThumbprint'
        }
        if (![System.String]::IsNullOrEmpty($Results.CertificatePassword))
        {
            $partialContent = Convert-DSCStringParamToVariable -DSCBlock $partialContent `
                -ParameterName 'CertificatePassword'
        }
    }

    if ($partialContent.ToLower().IndexOf($OrganizationName.ToLower()) -gt 0)
    {
        $partialContent = $partialContent -ireplace [regex]::Escape($OrganizationName + ':'), "`$($OrganizationName):"
        $partialContent = $partialContent -ireplace [regex]::Escape($OrganizationName), "`$OrganizationName"
        $partialContent = $partialContent -ireplace [regex]::Escape('@' + $OrganizationName), "@`$OrganizationName"
    }
    [void]$content.Append($partialContent)
    [void]$content.Append("        }`r`n")

    return $content.ToString()
}

<#
.Description
This function gets all resources that support the specified authentication method

.Functionality
Internal
#>
function Get-M365DSCComponentsForAuthenticationType
{
    [CmdletBinding()]
    [OutputType([System.String[]])]
    param
    (
        [Parameter()]
        [System.String[]]
        [ValidateSet('Application', 'ApplicationWithSecret', 'Certificate', 'Credentials')]
        $AuthenticationMethod,

        [Parameter()]
        [System.String[]]
        $ResourcesToExport
    )

    $modules = Get-ChildItem -Path ($PSScriptRoot + '\..\DSCResources\') -Recurse -Filter '*.psm1'
    $Components = @()
    foreach ($resource in $modules)
    {
        if ($ResourcesToExport.Contains($resource.Name.Replace('MSFT_', '').Split('.')[0]))
        {
            Import-Module $resource.FullName -Force
            $parameters = (Get-Command 'Set-TargetResource').Parameters.Keys

            # Case - Resource only supports AppID & GlobalAdmin
            if ($AuthenticationMethod.Contains('Application') -and `
                    $AuthenticationMethod.Contains('Credentials') -and `
                ($parameters.Contains('ApplicationId') -and `
                        $parameters.Contains('Credential') -and `
                        -not $parameters.Contains('CertificateThumbprint') -and `
                        -not $parameters.Contains('CertificatePath') -and `
                        -not $parameters.Contains('CertificatePassword') -and `
                        -not $parameters.Contains('TenantId')))
            {
                $Components += $resource.Name -replace 'MSFT_', '' -replace '.psm1', ''
            }

            #Case - Resource certificate info and TenantId
            elseif ($AuthenticationMethod.Contains('Certificate') -and `
                ($parameters.Contains('CertificateThumbprint') -or `
                        $parameters.Contains('CertificatePath') -or `
                        $parameters.Contains('CertificatePassword')) -and `
                    $parameters.Contains('TenantId'))
            {
                $Components += $resource.Name -replace 'MSFT_', '' -replace '.psm1', ''
            }

            # Case - Resource contains ApplicationSecret
            elseif ($AuthenticationMethod.Contains('ApplicationWithSecret') -and `
                    $parameters.Contains('ApplicationId') -and `
                    $parameters.Contains('ApplicationSecret') -and `
                    $parameters.Contains('TenantId'))
            {
                $Components += $resource.Name -replace 'MSFT_', '' -replace '.psm1', ''
            }

            # Case - Resource contains Credential
            elseif ($AuthenticationMethod.Contains('Credentials') -and `
                    $parameters.Contains('Credential'))
            {
                $Components += $resource.Name -replace 'MSFT_', '' -replace '.psm1', ''
            }
            elseif ($AuthenticationMethod.Contains('ManagedIdentity') -and `
                    $parameters.Contains('ManagedIdentity'))
            {
                $Components += $resource.Name -replace 'MSFT_', '' -replace '.psm1', ''
            }
        }
    }
    return $Components
}

<#
.Description
This function gets all resources that support the specified authentication method and
determines the most secure authentication method supported by the resource.

.Functionality
Internal
#>
function Get-M365DSCComponentsWithMostSecureAuthenticationType
{
    [CmdletBinding()]
    [OutputType([System.String[]])]
    param
    (
        [Parameter()]
        [System.String[]]
        [ValidateSet('ApplicationWithSecret', 'CertificateThumbprint', 'CertificatePath', 'Credentials', 'CredentialsWithApplicationId', 'ManagedIdentity')]
        $AuthenticationMethod,

        [Parameter()]
        [System.String[]]
        $Resources
    )

    $modules = Get-ChildItem -Path ($PSScriptRoot + '\..\DSCResources\') -Recurse -Filter '*.psm1'
    $Components = @()
    foreach ($resource in $modules)
    {
        if ($Resources -contains ($resource.Name.Replace('.psm1', '').Replace('MSFT_', '')))
        {
            Import-Module $resource.FullName -Force
            $parameters = (Get-Command 'Set-TargetResource').Parameters.Keys

            #Case - Resource supports CertificateThumbprint
            if ($AuthenticationMethod.Contains('CertificateThumbprint') -and `
                    $parameters.Contains('ApplicationId') -and `
                    $parameters.Contains('CertificateThumbprint') -and `
                    $parameters.Contains('TenantId'))
            {
                $Components += @{
                    Resource   = $resource.Name -replace 'MSFT_', '' -replace '.psm1', ''
                    AuthMethod = 'CertificateThumbprint'
                }
            }

            # Case - Resource supports CertificatePath
            elseif ($AuthenticationMethod.Contains('CertificatePath') -and `
                    $parameters.Contains('ApplicationId') -and `
                    $parameters.Contains('CertificatePath') -and `
                    $parameters.Contains('TenantId'))
            {
                $Components += @{
                    Resource   = $resource.Name -replace 'MSFT_', '' -replace '.psm1', ''
                    AuthMethod = 'CertificatePath'
                }
            }

            # Case - Resource supports ApplicationSecret
            elseif ($AuthenticationMethod.Contains('ApplicationWithSecret') -and `
                    $parameters.Contains('ApplicationId') -and `
                    $parameters.Contains('ApplicationSecret') -and `
                    $parameters.Contains('TenantId'))
            {
                $Components += @{
                    Resource   = $resource.Name -replace 'MSFT_', '' -replace '.psm1', ''
                    AuthMethod = 'ApplicationSecret'
                }
            }
            # Case - Resource supports Credential using CredentialsWithApplicationId
            elseif ($AuthenticationMethod.Contains('CredentialsWithApplicationId') -and `
                    $parameters.Contains('Credential'))
            {
                $Components += @{
                    Resource   = $resource.Name -replace 'MSFT_', '' -replace '.psm1', ''
                    AuthMethod = 'CredentialsWithApplicationId'
                }
            }
            # Case - Resource supports Credential
            elseif ($AuthenticationMethod.Contains('Credentials') -and `
                    $parameters.Contains('Credential'))
            {
                $Components += @{
                    Resource   = $resource.Name -replace 'MSFT_', '' -replace '.psm1', ''
                    AuthMethod = 'Credentials'
                }
            }
            elseif ($AuthenticationMethod.Contains('ManagedIdentity') -and `
                    $parameters.Contains('ManagedIdentity'))
            {
                $Components += @{
                    Resource   = $resource.Name -replace 'MSFT_', '' -replace '.psm1', ''
                    AuthMethod = 'ManagedIdentity'
                }
            }
        }
    }
    return $Components
}

<#
.Description
This function gets all available M365DSC resources in the module

.Example
Get-M365DSCAllResources

.Functionality
Public
#>
function Get-M365DSCAllResources
{
    [CmdletBinding()]
    [OutputType([System.String[]])]
    [CmdletBinding()]
    param ()

    $allResources = Get-ChildItem -Path ($PSScriptRoot + '\..\DSCResources\') -Recurse -Filter '*.psm1'
    $result = @()
    foreach ($resource in $allResources)
    {
        $result += $resource.Name -replace 'MSFT_', '' -replace '.psm1', ''
    }

    return $result
}

<#
.Description
This function checks if the specified object has the specified property

.Functionality
Internal, Hidden
#>
function Test-M365DSCObjectHasProperty
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true, Position = 1)]
        [Object]
        $Object,

        [Parameter(Mandatory = $true, Position = 2)]
        [String]
        $PropertyName
    )

    if (([bool]($Object.PSobject.Properties.name -contains $PropertyName)) -eq $true)
    {
        if ($null -ne $Object.$PropertyName)
        {
            return $true
        }
    }
    return $false
}

<#
.Description
This function returns the used workloads for the specified DSC resources

.Parameter ResourceNames
Specifies the resources for which the workloads should be determined.

.Example
Get-M365DSCWorkloadsListFromResourceNames -ResourceNames AADUSer

.Functionality
Public
#>
function Get-M365DSCWorkloadsListFromResourceNames
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true, Position = 1)]
        [String[]]
        $ResourceNames
    )

    [Array] $workloads = @()
    foreach ($resource in $ResourceNames)
    {
        switch ($resource.Substring(0, 2).ToUpper())
        {
            'AA'
            {
                if (-not $workloads.Contains('MicrosoftGraph'))
                {
                    $workloads += 'MicrosoftGraph'
                }
            }
            'EX'
            {
                if (-not $workloads.Contains('ExchangeOnline'))
                {
                    $workloads += 'ExchangeOnline'
                }
            }
            'In'
            {
                if (-not $workloads.Contains('MicrosoftGraph'))
                {
                    $workloads += 'MicrosoftGraph'
                }
            }
            'O3'
            {
                if (-not $workloads.Contains('MicrosoftGraph') -and $resource -eq 'O365Group')
                {
                    $workloads += 'MicrosoftGraph'
                }
                elseif (-not $workloads.Contains('ExchangeOnline'))
                {
                    $workloads += 'ExchangeOnline'
                }
            }
            'OD'
            {
                if (-not $workloads.Contains('PnP'))
                {
                    $workloads += 'PnP'
                }
            }
            'Pl'
            {
                if (-not $workloads.Contains('MicrosoftGraph'))
                {
                    $workloads += 'MicrosoftGraph'
                }
            }
            'SP'
            {
                if (-not $workloads.Contains('PnP'))
                {
                    $workloads += 'PnP'
                }
            }
            'SC'
            {
                if (-not $workloads.Contains('SecurityComplianceCenter'))
                {
                    $workloads += 'SecurityComplianceCenter'
                }
            }
            'Te'
            {
                if (-not $workloads.Contains('MicrosoftTeams'))
                {
                    $workloads += 'MicrosoftTeams'
                }
            }
        }
    }
    return ($workloads | Sort-Object)
}

<#
.Description
This function gets the used authentication mode based on the specified parameters

.Functionality
Internal
#>
function Get-M365DSCAuthenticationMode
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]
        $Parameters
    )

    if ($Parameters.ApplicationId -and $Parameters.TenantId -and $Parameters.CertificateThumbprint)
    {
        $AuthenticationType = 'ServicePrincipalWithThumbprint'
    }
    elseif ($Parameters.ApplicationId -and $Parameters.TenantId -and $Parameters.ApplicationSecret)
    {
        $AuthenticationType = 'ServicePrincipalWithSecret'
    }
    elseif ($Parameters.ApplicationId -and $Parameters.TenantId -and $Parameters.CertificatePath -and $Parameters.CertificatePassword)
    {
        $AuthenticationType = 'ServicePrincipalWithPath'
    }
    elseif ($Parameters.Credentials -and $Parameters.ApplicationId)
    {
        $AuthenticationType = 'CredentialsWithApplicationId'
    }
    elseif ($Parameters.Credentials)
    {
        $AuthenticationType = 'Credentials'
    }
    elseif ($Parameters.ManagedIdentity)
    {
        $AuthenticationType = 'ManagedIdentity'
    }
    else
    {
        $AuthenticationType = 'Interactive'
    }
    return $AuthenticationType
}

<#
.Description
This function creates Markdown documentation of all public M365DSC cmdlets
and places these in the correct location of the docs folder.

.Functionality
Internal
#>
function New-M365DSCCmdletDocumentation
{
    param()

    $cmdletDocsRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\docs\docs\user-guide\cmdlets'

    if ((Test-Path -Path $cmdletDocsRoot) -eq $false)
    {
        $null = New-Item -Path $cmdletDocsRoot -ItemType Directory
    }

    $filesInFolder = Get-ChildItem -Path $cmdletDocsRoot
    if ($filesInFolder.Count -ne 0)
    {
        Remove-Item -Path $filesInFolder.FullName -Confirm:$false
    }

    Write-Host -Object ' '
    Write-Host -Object 'Creating Markdown documentation for M365DSC cmdlets:' -ForegroundColor Gray

    $counter = 0
    foreach ($command in (Get-Module Microsoft365Dsc).ExportedCommands.GetEnumerator())
    {
        $commandName = $command.Key
        $helpInfo = Get-Help $commandName
        $functionality = $helpInfo.Functionality -split ', '
        if ('Public' -in $functionality)
        {
            Write-Host -Object "  * $commandName " -ForegroundColor Gray -NoNewline

            $output = New-Object -TypeName System.Text.StringBuilder

            $null = $output.AppendLine("# $($commandName)")
            $null = $output.AppendLine('')

            $helpInfo = Get-Help -Name $commandName
            if ($helpInfo.description.Count -ne 0)
            {
                $null = $output.AppendLine('## Description')
                $null = $output.AppendLine('')
                $null = $output.AppendLine($helpInfo.Description[0].Text)
                $null = $output.AppendLine('')
            }

            $cmd = Get-Command -Name $commandName
            if ([String]::IsNullOrEmpty($cmd.OutputType) -eq $false)
            {
                $null = $output.AppendLine('## Output')
                $null = $output.AppendLine('')
                $null = $output.AppendLine('This function outputs information as the following type:')
                $null = $output.AppendLine("**$($cmd.OutputType)**")
                $null = $output.AppendLine('')
            }
            else
            {
                $null = $output.AppendLine('## Output')
                $null = $output.AppendLine('')
                $null = $output.AppendLine('This function does not generate any output.')
                $null = $output.AppendLine('')
            }

            $ast = $cmd.ScriptBlock.Ast
            $parameters = $null
            $parameters = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ParameterAst] }, $true)

            $null = $output.AppendLine('## Parameters')
            $null = $output.AppendLine('')
            if ($parameters.Count -gt 0)
            {
                $null = $output.AppendLine('| Parameter | Required | DataType | Default Value | Allowed Values | Description |')
                $null = $output.AppendLine('| --- | --- | --- | --- | --- | --- |')

                $ast = $cmd.ScriptBlock.Ast
                $parameters = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ParameterAst] }, $true)
                foreach ($parameter in $parameters)
                {
                    $paramName = $parameter.Name.VariablePath.UserPath

                    $paramHelp = $helpInfo.parameters.parameter | Where-Object { $_.Name -eq $paramName }
                    $description = ''
                    if ($paramHelp.description.Count -gt 0)
                    {
                        $description = $paramHelp.description[0].Text
                    }
                    $mandatory = $parameter.Attributes.Where({ $_.TypeName.FullName -eq 'Parameter' }).NamedArguments.Where({ $_.ArgumentName -eq 'Mandatory' }).Argument.VariablePath.UserPath
                    if ($null -eq $mandatory)
                    {
                        $mandatory = 'False'
                    }
                    $mandatory = (Get-Culture).TextInfo.ToTitleCase($mandatory.ToLower())

                    $null = $output.AppendLine("| $($paramName) | $($mandatory) | $($parameter.StaticType.Name) | $($parameter.DefaultValue.Value) | $($parameter.Attributes.Where({$_.TypeName.FullName -eq 'ValidateSet'}).PositionalArguments.Value -join ', ') | $($description) |")

                }
                $null = $output.AppendLine('')
            }
            else
            {
                $null = $output.AppendLine('This function does not have any input parameters.')
            }

            if ($helpInfo.examples.example.Count -ne 0)
            {
                $null = $output.AppendLine('## Examples')
                $null = $output.AppendLine('')
                foreach ($example in $helpInfo.examples.example)
                {
                    $null = $output.AppendLine($example.title)
                    $null = $output.AppendLine('')
                    $null = $output.AppendLine("``$($example.code)``")
                    $null = $output.AppendLine('')
                }
            }

            $savePath = Join-Path -Path $cmdletDocsRoot -ChildPath "$commandName.md"
            $null = Out-File `
                -InputObject ($output.ToString() -replace '\r?\n', "`r`n") `
                -FilePath $savePath `
                -Encoding utf8 `
                -Force:$Force
            Write-Host -Object $Global:M365DSCEmojiGreenCheckmark -ForegroundColor Gray
            $counter++
        }
    }

    Write-Host -Object ' '
    Write-Host -Object "Total number files created: $counter" -ForegroundColor Gray
    Write-Host -Object ' '
}

<#
.Description
This function creates an example from the resource schema, using ReverseDSC code.

.Parameter ResourceName
Specifies the resource name for which the example should be generated.

.Functionality
Internal, Hidden
#>
function Create-M365DSCResourceExample
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $ResourceName
    )

    $resource = Get-DscResource -Name $ResourceName

    $params = Get-DSCFakeParameters -ModulePath $resource.Path

    $params.Credential = '$credsGlobalAdmin'

    if ($params.ContainsKey('ApplicationId'))
    {
        $params.Remove('ApplicationId')
    }

    if ($params.ContainsKey('TenantId'))
    {
        $params.Remove('TenantId')
    }

    if ($params.ContainsKey('ApplicationSecret'))
    {
        $params.Remove('ApplicationSecret')
    }

    if ($params.ContainsKey('CertificateThumbprint'))
    {
        $params.Remove('CertificateThumbprint')
    }

    if ($params.ContainsKey('CertificatePath'))
    {
        $params.Remove('CertificatePath')
    }

    if ($params.ContainsKey('CertificatePassword'))
    {
        $params.Remove('CertificatePassword')
    }

    [string]$userName = 'admin@contoso.onmicrosoft.com'
    [string]$userPassword = 'dummypassword'
    [securestring]$secStringPassword = ConvertTo-SecureString $userPassword -AsPlainText -Force
    [pscredential]$credObject = New-Object System.Management.Automation.PSCredential ($userName, $secStringPassword)

    $resourceExample = Get-M365DSCExportContentForResource -ResourceName $ResourceName -ModulePath $resource.Path -Results $params -ConnectionMode Credentials -Credential $credObject

    $resourceExample = $resourceExample.TrimEnd() -replace ';', ''

    $exampleText = @"
<#
This example is used to test new resources and showcase the usage of new resources being worked on.
It is not meant to use as a production baseline.
#>

Configuration Example
{
    param
    (
        [Parameter(Mandatory = `$true)]
        [PSCredential]
        `$credsGlobalAdmin
    )
    Import-DscResource -ModuleName Microsoft365DSC

    node localhost
    {
$resourceExample
    }
}
"@

    return $exampleText
}

<#
.Description
This function creates an example from the resource schema, using ReverseDSC code.

.Parameter ResourceName
Specifies the resource name for which the example should be generated.

.Functionality
Internal
#>
function New-M365DSCMissingResourcesExample
{
    $location = $PSScriptRoot

    $m365Resources = Get-DscResource -Module Microsoft365DSC | Select-Object -ExpandProperty Name

    $examplesPath = Join-Path $location -ChildPath '..\Examples\Resources'
    $examples = Get-ChildItem -Path $examplesPath | Where-Object { $_.PsIsContainer } | Select-Object -ExpandProperty Name

    [array]$differences = Compare-Object -ReferenceObject $m365Resources -DifferenceObject $examples

    $count = 1
    $total = $differences.Count

    foreach ($difference in $differences)
    {
        Write-Host "[$count/$total] Processing $($difference.InputObject)"
        $path = Join-Path -Path '.\Modules\Microsoft365DSC\Examples\Resources' -ChildPath $difference.InputObject
        switch ($difference.SideIndicator)
        {
            '<='
            {
                Write-Host '  - Example missing, generating!'
                $null = New-Item -Path $path -ItemType Directory
                $exampleFile = Join-Path -Path $path -ChildPath '1-Configure.ps1'
                Set-Content -Path $exampleFile -Value (Create-M365DSCResourceExample -ResourceName $difference.InputObject)
            }
            '=>'
            {
                Write-Host '  - No resource for existing example, removing!'
                Remove-Item -Path $path -Force -Confirm:$false
            }
        }
        $count++
    }
}

<#
.Description
This function validates there are no updates to the module or it's dependencies and no multiple versions are present on the local system.

.Example
Test-M365DSCModuleValidity

.Example
Test-M365DSCModuleValidity -Force

.Functionality
Public
#>
function Test-M365DSCModuleValidity
{
    [CmdletBinding()]
    param()

    if ('AzureAutomation/' -eq $env:AZUREPS_HOST_ENVIRONMENT)
    {
        $message = 'Skipping check for newer version of Microsoft365DSC due to Azure Automation Environment restrictions.'
        Write-Verbose -Message $message
        return
    }

    $InformationPreference = 'Continue'

    # validate only one installation of the module is present (and it's the latest version available from the psgallery)
    $latestVersion = (Find-Module -Name 'Microsoft365DSC' -Repository 'PSGallery' -Includes 'DSCResource').Version
    $localVersion = (Get-Module -Name 'Microsoft365DSC').Version

    if ($latestVersion -gt $localVersion)
    {
        Write-Host "There is a newer version of the 'Microsoft365DSC' module available on the gallery."
        Write-Host "To update the module and it's dependencies, run the following command:"
        Write-Host 'Update-M365DSCModule' -ForegroundColor Blue
    }
}


<#
.Description
This function updates the module, dependencies and uninstalls outdated dependencies.

.Parameter Scope
Specifies the scope of the update of the module. The default value is AllUsers(needs to run as elevated user).

.Example
Update-M365DSCModule

.Example
Update-M365DSCModule -Scope CurrentUser

.Example
Update-M365DSCModule -Scope AllUsers

.Functionality
Public
#>
function Update-M365DSCModule
{
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet("CurrentUser", "AllUsers")]
        $Scope = "AllUsers"
    )
    try
    {
        Update-Module -Name 'Microsoft365DSC' -ErrorAction Stop -Scope $Scope
    }
    catch
    {
        if ($_.Exception.Message -like "*Module 'Microsoft365DSC' was not installed by using Install-Module")
        {
            Write-Verbose -Message "The Microsoft365DSC module was not installed from the PowerShell Gallery and therefore cannot be updated."
        }
    }
    try
    {
        Write-Verbose -Message "Unloading all instances of the Microsoft365DSC module from the current PowerShell session."
        Remove-Module Microsoft365DSC -Force

        Write-Verbose -Message "Retrieving all versions of the Microsoft365DSC installed on the machine."
        [Array]$instances = Get-Module Microsoft365DSC -ListAvailable | Sort-Object -Property Version -Descending
        if ($instances.Length -gt 0)
        {
            Write-Verbose -Message "Loading version {$($instances[0].Version.ToString())} of the Microsoft365DSC module from {$($instances[0].ModuleBase)}"
            Import-Module Microsoft365DSC -RequiredVersion $instances[0].Version.ToString() -Force
        }
    }
    catch
    {
        New-M365DSCLogEntry -Message 'Error Updating Module:' `
            -Exception $_ `
            -Source $($MyInvocation.MyCommand.Source)
        throw $_
    }
    Update-M365DSCDependencies -Scope $Scope
    Uninstall-M365DSCOutdatedDependencies
}

<#
.Description
This function writes messages and adds M365DSCEvents to Eventlog

.Example
Write-M365DSCLogEvent -Message $_ -EventSource $($MyInvocation.MyCommand.Source) -TenantId $tenantid -Credential $Credential

.Functionality
Internal
#>
function Write-M365DSCLogEvent
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Message,

        [Parameter()]
        [System.String]
        $EventSource = 'M365DSC',

        [Parameter()]
        [System.Uint32]
        $EventID = 1,

        [Parameter()]
        [ValidateSet('Error', 'Information', 'FailureAudit', 'SuccessAudit', 'Warning')]
        [System.String]
        $EventEntryType = 'Error',

        [Parameter()]
        [System.String]
        $TenantId,

        [Parameter()]
        [PSCredential]
        $Credential
    )

    try
    {
        Write-Verbose -Message $Message
        $tenantIdValue = ''
        if (-not [System.String]::IsNullOrEmpty($TenantId))
        {
            $tenantIdValue = $TenantId
        }
        elseif ($null -ne $Credential)
        {
            $tenantIdValue = $Credential.UserName.Split('@')[1]
        }
        Add-M365DSCEvent -Message $Message -EntryType $EventEntryType -EventID $EventID -Source $EventSource -TenantId $tenantIdValue
    }
    catch
    {
        Write-Verbose -Message $_
    }
    return $nullReturn
}

<#
.Description
This function removes the authentication parameters from the hashtable.

.Functionality
Internal
#>
function Remove-M365DSCAuthenticationParameter
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]
        $BoundParameters
    )

    if ($BoundParameters.ContainsKey('Ensure'))
    {
        $BoundParameters.Remove('Ensure') | Out-Null
    }
    if ($BoundParameters.ContainsKey('Credential'))
    {
        $BoundParameters.Remove('Credential') | Out-Null
    }
    if ($BoundParameters.ContainsKey('ApplicationId'))
    {
        $BoundParameters.Remove('ApplicationId') | Out-Null
    }
    if ($BoundParameters.ContainsKey('ApplicationSecret'))
    {
        $BoundParameters.Remove('ApplicationSecret') | Out-Null
    }
    if ($BoundParameters.ContainsKey('TenantId'))
    {
        $BoundParameters.Remove('TenantId') | Out-Null
    }
    if ($BoundParameters.ContainsKey('CertificatePassword'))
    {
        $BoundParameters.Remove('CertificatePassword') | Out-Null
    }
    if ($BoundParameters.ContainsKey('CertificatePath'))
    {
        $BoundParameters.Remove('CertificatePath') | Out-Null
    }
    if ($BoundParameters.ContainsKey('CertificateThumbprint'))
    {
        $BoundParameters.Remove('CertificateThumbprint') | Out-Null
    }
    if ($BoundParameters.ContainsKey('ManagedIdentity'))
    {
        $BoundParameters.Remove('ManagedIdentity') | Out-Null
    }
    if ($BoundParameters.ContainsKey('Verbose'))
    {
        $BoundParameters.Remove('Verbose') | Out-Null
    }
    return $BoundParameters
}

<#
.Description
This function analyzes an M365DSC configuration file and returns information about potential issues (e.g., duplicate primary keys).

.Example
Get-M365DSCConfigurationConflict -ConfigurationContent "content"

.Functionality
Public
#>
function Get-M365DSCConfigurationConflict
{
    [CmdletBinding()]
    [OutputType([Array])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $ConfigurationContent
    )

    $results = @()
    Write-Verbose -Message "Converting configuration's content into a PowerShell Object using DSCParser"
    $parsedContent = ConvertTo-DSCObject -Content $ConfigurationContent

    $resourcesPrimaryIdentities = @()
    $resourcesInModule = Get-DSCResource -Module 'Microsoft365DSC'
    foreach ($component in $parsedContent)
    {
        $resourceDefinition = $resourcesInModule | Where-Object -FilterScript {$_.Name -eq $component.ResourceName}
        [Array]$mandatoryProperties = $resourceDefinition.Properties | Where-Object -FilterScript {$_.IsMandatory}
        $primaryKeyValues = ""
        foreach ($mandatoryKey in $mandatoryProperties.Name)
        {
            $primaryKeyValues += "$($component.$mandatoryKey)|"
        }
        $entryValue = "[$($component.ResourceName)]$primaryKeyValues"
        if ($resourcesPrimaryIdentities.Contains($entryValue))
        {
            Write-Verbose -Message "Found primary key conflict in resource {$($component.ResourceInstanceName)}"
            $currentEntry = @{
                ResourceName         = $component.ResourceName
                InstanceName         = $component.ResourceInstanceName
                AdditionalProperties = @{}
                Reason               = "DuplicatePrimaryKey"
            }

            foreach ($mandatoryKey in $mandatoryProperties.Name)
            {
                $currentEntry.AdditionalProperties.Add($mandatoryKey, $component.$mandatoryKey)
            }
            $results += $currentEntry
        }
        else
        {
            $resourcesPrimaryIdentities += $entryValue
        }
    }
    return $results
}

Export-ModuleMember -Function @(
    'Assert-M365DSCBlueprint',
    'Confirm-ImportedCmdletIsAvailable',
    'Confirm-M365DSCDependencies',
    'Convert-M365DscHashtableToString',
    'ConvertTo-SPOUserProfilePropertyInstanceString',
    'Export-M365DSCConfiguration',
    'Get-AllSPOPackages',
    'Get-M365DSCAllResources',
    'Get-M365DSCAuthenticationMode',
    'Get-M365DSCComponentsForAuthenticationType',
    'Get-M365DSCComponentsWithMostSecureAuthenticationType',
    'Get-M365DSCConfigurationConflict',
    'Get-M365DSCExportContentForResource',
    'Get-M365DSCOrganization',
    'Get-M365DSCTenantDomain',
    'Get-M365DSCWorkloadsListFromResourceNames',
    'Get-M365TenantName',
    'Get-SPOAdministrationUrl',
    'Get-SPOUserProfilePropertyInstance',
    'Get-TeamByName',
    'Import-M365DSCDependencies',
    'Install-M365DSCDevBranch',
    'Invoke-M365DSCCommand',
    'New-EXOSafeAttachmentRule',
    'New-EXOSafeLinksRule',
    'New-M365DSCCmdletDocumentation',
    'New-M365DSCConnection',
    'New-M365DSCMissingResourcesExample',
    'Remove-EmptyValue',
    'Remove-M365DSCAuthenticationParameter',
    'Remove-NullEntriesFromHashtable',
    'Set-EXOSafeAttachmentRule',
    'Set-EXOSafeLinksRule',
    'Split-ArrayByParts',
    'Test-M365DSCDependenciesForNewVersions',
    'Test-M365DSCModuleValidity',
    'Test-M365DSCParameterState',
    'Uninstall-M365DSCOutdatedDependencies',
    'Update-M365DSCDependencies',
    'Update-M365DSCExportAuthenticationResults',
    'Update-M365DSCModule',
    'Write-M365DSCLogEvent'
)
