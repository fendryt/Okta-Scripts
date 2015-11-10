﻿<#
    .SYNOPSIS 
        Generates a report of application username discrepencies for a given Okta Application ID
    .DESCRIPTION
        To help find errors in application assignments to groups (it happens) or mismatches when
        a user is renamed after an application has been assigned. This report performs an
        exhaustive search and can take quite some time to run.
    .EXAMPLE
        AppUserNameAudit -oOrg prod -AppId 1ob20l621h2TMIJPGYJP
        This command finds runs a report against the org defined 
        as 'prod' and the application id 1ob20l621h2TMIJPGYJP
    .LINK
        https://github.com/mbegan/Okta-Scripts
        https://support.okta.com/help/community
        http://developer.okta.com/docs/api/getting_started/design_principles.html
#>
Param
(
    [Parameter(Mandatory=$true)][alias('org','OktaOrg')][string]$oOrg,
    [Parameter(Mandatory=$true)][alias('aid','ApplicationID')][string]$AppId
)

Import-Module Okta
if (!(Get-Module Okta))
{
    throw 'Okta module not loaded...'
}

#preseve value
$curVerbosity = $oktaVerbose

if ( [System.Management.Automation.ActionPreference]::SilentlyContinue -ne $VerbosePreference )
{
    $oktaVerbose = $true
} else {
    $oktaVerbose = $false
}

try
{
    $app = oktaGetAppbyId -oOrg $oOrg -aid $AppID
}
catch
{
    throw $_.Exception.Message
}

Write-Verbose ('Getting all users assigned to ' + $app.label)

try
{
    $AppUsers = oktaGetUsersbyAppID -oOrg $oOrg -aid $AppID -limit 200
}
catch
{
    throw $_.Exception.Message
}
$AppUHash = New-Object System.Collections.Hashtable
foreach ($au in $AppUsers)
{
    $AppUHash.Add($au.id,$au)
}

Write-Verbose ('Getting all groups used to assign ' + $app.label)
try
{
    $AppGroups = oktaGetAppGroups -oOrg $oOrg -aid $AppID
}
catch
{
    throw $_.Exception.Message
}

$oktaUsers = New-Object System.Collections.ArrayList
foreach ($agroup in $AppGroups)
{
    $groupUsers = New-Object System.Collections.ArrayList
    try
    {
        $group = oktaGetGroupbyId -oOrg prod -gid $agroup.id
    }
    catch
    {
        throw $_.Exception.Message
    }
    Write-Verbose ('getting all members of' + $group.profile.name + ' the ' + $agroup.priority + ' priority level group for ' + $app.label)

    try
    {
        $groupUsers = oktaGetGroupMembersbyId -oOrg $oOrg -gid $group.id -limit 200 -enablePagination $true
    }
    catch
    {
        throw $_.Exception.Message
    }
    foreach ($gu in $groupUsers)
    {
        $_c = $oktaUsers.add($gu)
    }
}

Write-Verbose ('creating a reference hash for users')
$oktaUHash = New-Object System.Collections.Hashtable
foreach ($u in $oktaUsers)
{
    $oktaUHash.Add($u.id,$u)
}

$report = New-Object System.Collections.ArrayList
$c = 0
$total = $AppUsers.Count
foreach ($AppUser in $AppUsers)
{
    $c++
    
    if ($oktaUHash[$AppUser.id])
    {
        $oktaUser = $oktaUHash[$AppUser.id]
        $oktaUHash.Remove($AppUser.id)
    } else {
        Write-Host $AppUser.id know as $AppUser.credentials.userName was not in the group populated cache, fetching... -BackgroundColor DarkYellow -NoNewline
        try
        {
            $oktauser = oktaGetUserbyID -oOrg $oOrg -userName $AppUser.id
        }
        catch
        {
            $oktaUser = $false
            Write-Host $AppUser.id was Not found in Okta -BackgroundColor Red
        }
        Write-Host $AppUser.id was fetched -BackgroundColor Green
    }

    ### Should detect username template $app.credentials.userNameTemplate.template !!!
    if ($oktaUser.profile.login -ne $AppUser.credentials.userName)
    {
        Write-Verbose ('No Match for ' + $oktaUser.profile.login + ' not equal to ' + $AppUser.credentials.userName)
        $line = @{ Reason = 'NoMatch'; id = $oktaUser.id; Login = $oktaUser.profile.login; BadLogin = $AppUser.credentials.userName }
        $row = New-Object psobject -Property $line
        $_c = $report.Add($row)
    }
}

foreach ($uid in $oktaUHash.Keys)
{
    $user = $oktaUHash[$uid]
    $line = @{ Reason = 'Missing'; id = $user.id; Login = $user.profile.login; BadLogin = $null }
    $row = New-Object psobject -Property $line
    $_c = $report.Add($row)
}

#restore verbosity
$oktaVerbose = $curVerbosity

return ($report | select Reason,id,Login,BadLogin)