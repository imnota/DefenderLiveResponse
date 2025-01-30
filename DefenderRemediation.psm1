<# MIT License

Copyright (c) Andy Blackman.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE
#>

<#
.SYNOPSIS
Connects to the Defender API

.DESCRIPTION
This function connects to the Defender API

.PARAMETER appID
The Application (Client) ID for the application which will be used to access the Defender API 
(see "Setting up the Application" in the documentation) 

.PARAMETER appSecret
The Client Secret for the application which will be used to access the Defender API

.PARAMETER tenantID
The Tenant ID for your tenant

.PARAMETER securityCenterHost
The security center host you want to use.
Currently this can be one of:
    api.security.microsoft.com
    api-us.security.microsoft.com
    api-eu.security.microsoft.com 
    api-uk.security.microsoft.com 

.PARAMETER returnToken
Whether to return the authorisation header to the calling program

.PARAMETER minBackoffSecs
The starting value for backoff (in seconds).
If the API returns too many requests have been made, it will make the first request again after this many
seconds, then will double the amount of seconds before retrying (to a maximum of maxBackoffSecs)


.PARAMETER maxBackoffSecs
The maximum value for backoff (in seconds).
If the API returns too many requests have been made, it will make the first request again after 
minBackoffSecs, then will double the amount of seconds before retrying, but will quit after the backoff
period is more than maxBack

.EXAMPLE
An example

.NOTES
General notes
#>
function Connect-SecurityCenter {
    param (
        [Parameter(Position = 0, mandatory = $true)] [string]$appID,
        [Parameter(Position = 1, mandatory = $true)] [string]$appSecret,
        [Parameter(Position = 2, mandatory = $false)] [string]$tenantID,
        [Parameter(Position = 3, Mandatory = $false)] 
        [ValidateSet("api.securitycenter.microsoft.com", "api-us.securitycenter.microsoft.com", "api-eu.securitycenter.microsoft.com", "api-uk.securitycenter.microsoft.com")]
        [string]$securityCenterHost = "api-uk.securitycenter.microsoft.com",
        [Parameter(Position = 4, Mandatory = $false)] [bool]$returnToken = $false,
        [Parameter(Position = 5, Mandatory = $false)] [int]$minBackoffSecs = 30,
        [Parameter(Position = 6, Mandatory = $false)] [int]$maxBackoffSecs = 240
    )
    
    $sourceAppIdUri = "https://$($securityCenterHost)"  
    $oAuthUri = "https://login.microsoftonline.com/$TenantId/oauth2/token"
    $authBody = [Ordered] @{
        resource      = "$sourceAppIdUri"
        client_id     = "$appId"
        client_secret = "$appSecret"
        grant_type    = 'client_credentials'
    }
    $authResponse = Invoke-RestMethod -Method Post -Uri $oAuthUri -Body $authBody -ErrorAction Stop
    $script:tokencache = $authResponse.access_token
    $script:securityCenterHost = $securityCenterHost
    $script:minBackoff=$minBackoffSecs
    $script:maxBackoff=$maxBackoffSecs
    if ($returnToken) {
        return $authResponse
    }
}

function Invoke-APICall {
    param (
        [string] $apiCall,
        [string] $token,
        [string] $body,
        [int] $backoff=0
    )

    $header = @{
        Authorization = "Bearer $($token)"
    }
    try {
        if (-not $body) {
            $response = Invoke-RestMethod -Headers $header -Uri $apiCall -Method Get -UseBasicParsing
        }
        else {
            $response = Invoke-RestMethod -Headers $header -Uri $apiCall -Body $body -Method Post -UseBasicParsing
        }
    }
    catch {
        try {
            $exceptionDetails = $_.Exception.Response
            if ($exceptionDetails.statuscode.value__ -eq 429) {
                try {
                    If (($exceptionDetails.headers | where { $_.key -eq "Retry-After" }).count -gt 0) {
                        #OK, we need to round up rather than down, so must add 0.51 seconds
                        $number = [int](([float]"$($($exceptionDetails.headers|where {$_.key -eq "Retry-After"}).value)") + 0.51)
                    }
                    else {
                        $number=$null
                    }
                }
                catch {

                    $Number = $null
                }
                if ((-not ($number -is [int]))) {
                    #So, something is wrong here, we've not been told how long to wait so we will have to throw an error
                    #This likely means that we have hit the total 100 calls per minute limit or another related limit,
                    #let's use some incremental backoff to rate limit
                    if($backoff -eq 0) {
                        $backoff=$minBackoff
                    } else {
                        $backoff=$backoff * 2
                    }
                    $number=$backoff
                }
                if ($backoff -le $maxBackoff) {
                    write-warning "Need to sleep for $($number) seconds"
                    start-sleep -seconds $number
                    try {
                        $response = Invoke-APICall -apicall $apiCall -token $token -body $body -backoff $number
                    }
                    catch {
                        throw $_
                    }
                }
                else {
                    throw $_
                }
            }
            else {
                Throw $_
            }
        }
        catch {
            throw $_
            
        }
        
    }
    return $response
    
}

<#
.SYNOPSIS
Retrieve a list of machines

.DESCRIPTION
Retrieve a list of machines from Defender

.PARAMETER filter
An ODATA filter to pass to the API

.PARAMETER token
An auth token (not required if currently cached)

.EXAMPLE
Get-Machines -filter "computerDNSName eq 'DESKTOP-XXXXXXXX'"

#>
function Get-Machines {
    param (
        [Parameter(Position = 0, mandatory = $false)] [string]$filter,
        [Parameter(Position = 1, mandatory = $false)] [string]$token
        
    )
    if (-not $token) {
        $token = $tokencache
    }
    if (-not $token) {
        throw "Please call Connect-SecurityCenter before attempting to call the APIs"
    }

    $uri = "https://$($securityCenterHost)/api/machines"
    if ($filter) {
        $uri += ("?`$filter=$($filter)" -replace " ", "+")
    }
    try {
        $response = Invoke-APICall -apiCall $uri -token $token 
    }
    catch {
        throw $_
        return $null
    }
    return $response.value
}

<#
.SYNOPSIS
Runs a specified LiveResponse script on the machine with the provided aadDeviceID

.DESCRIPTION
Runs a specified LiveResponse script on the machine with the provided aadDeviceID

.PARAMETER aadDeviceID
The aadDeviceID of the target machine

.PARAMETER scriptName
The name of the script to run 

.PARAMETER Comment
The comment to set on RequestorComment

.PARAMETER token
An auth token (not required if currently cached)

.EXAMPLE
Invoke-LiveResponseScript -aadDeviceID "a345e00e-6b4f-4425-956a-ef7c12e83cb7" -scriptname "MyPreloadedScript.ps1" -comment "Rnning to remediate an issue" 

.NOTES
The script you want to run must already exist in the Defender LiveResponse library
#>
function Invoke-LiveResponseScript {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, mandatory = $true, ValueFromPipelineByPropertyName)] [string]$aadDeviceID,
        [Parameter(Position = 1, mandatory = $true)] [string]$scriptName,
        [Parameter(Position = 2, mandatory = $false)] [string]$Comment = "Executed by Invoke-LiveResponseScript",
        [Parameter(Position = 3, mandatory = $false)] [string]$token
    )
    #API limits: 
    #10 calls per minute
    #25 concurrent sessions
    #Jobs will queue for 3 days if machine not available
    #Scripts time out after 10 minutes

    begin {

    }
    process {

        if (-not $token) {
            $token = $tokencache
        }
        if (-not $token) {
            throw "Please call Connect-SecurityCenter before attempting to call the APIs"
        }
    
        $uri = "https://$($securityCenterHost)/API/machines/$($aadDeviceId)/runliveresponse"

        $body =
        '{
        "Commands":[
           {
              "type":"RunScript",
              "params":[
                 {
                    "key":"ScriptName",
                    "value":"' + $scriptName + '"
                 }
              ]
           }
        ],
        "Comment":"' + $comment + '"
     }'
    
        try {
            $response = Invoke-APICall -apiCall $uri -token $token -body $body
        }
        catch {
            throw $_
        }
        return $response 
    }
}

<#
.SYNOPSIS
Cancel an action running on a machine

.DESCRIPTION
Cancel a Defender action running on a machine

.PARAMETER id
The ID of the action

.PARAMETER Comment
The comment to set on RequestorComment

.PARAMETER token
An auth token (not required if currently cached)

.EXAMPLE
Invoke-CancelMachineAction -id "d1d9d8e9-871f-4d02-87ba-f5dffcfa5fbf" -Comment "Action no longer required"

#>
function Invoke-CancelMachineAction {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, mandatory = $true, ValueFromPipelineByPropertyName)] [string]$id,
        [Parameter(Position = 1, mandatory = $false)] [string]$Comment = "Cancelled by Invoke-CancelMachineAction",
        [Parameter(Position = 2, mandatory = $false)] [string]$token       
    )
    
    begin {

    }

    process {
        if (-not $token) {
            $token = $tokencache
        }
        if (-not $token) {
            throw "Please call Connect-SecurityCenter before attempting to call the APIs"
        }
        $uri = "https://$($securityCenterHost)/API/machineactions/$($id)/cancel"

        $body =
        '{
        "Comment":"' + $comment + '"
    }'
    
        try {
            $response = Invoke-APICall -apiCall $uri -token $token -body $body
        }
        catch {
            throw $_
        }
        return $response 
    }
}

<#
.SYNOPSIS
Gets a machine action

.DESCRIPTION
Retrieves a machine action

.PARAMETER id
ID of the action

.PARAMETER token
An auth token (not required if currently cached)

.EXAMPLE
Get-MachineAction -id "d1d9d8e9-871f-4d02-87ba-f5dffcfa5fbf"
#>
function Get-MachineAction {
    param (
        [Parameter(Position = 0, mandatory = $true)] [string]$id,
        [Parameter(Position = 1, mandatory = $false)] [string]$token
        
    )
    
    if (-not $token) {
        $token = $tokencache
    }
    if (-not $token) {
        throw "Please call Connect-SecurityCenter before attempting to call the APIs"
    }

    $uri = "https://$($securityCenterHost)/api/machineactions/$($id)"
    try {
        $response = Invoke-APICall -apiCall $uri -token $token 
    }
    catch {
        throw $_
    }
    return $response    
}

<#
.SYNOPSIS
Get the result of a machine action

.DESCRIPTION
Retrieves the result of a machine action

.PARAMETER id
The machine action ID

.PARAMETER commandIndex
The index of the command you want to retrieve the result for

.PARAMETER token
An auth token (not required if currently cached)

.EXAMPLE
Get-MachineActionResult -id "d1d9d8e9-871f-4d02-87ba-f5dffcfa5fbf"

#>
function Get-MachineActionResult {
    param (
        [Parameter(Position = 0, mandatory = $true, ValueFromPipelineByPropertyName)] [string]$id,
        [Parameter(Position = 1, mandatory = $false)] [string]$commandIndex = 0,
        [Parameter(Position = 2, mandatory = $false)] [string]$token
    )
    begin {
    
    }
    process {
        if (-not $token) {
            $token = $tokencache
        }
        if (-not $token) {
            throw "Please call Connect-SecurityCenter before attempting to call the APIs"
        }

        $uri = "https://$($securityCenterHost)/api/machineactions/$($id)/GetLiveResponseResultDownloadLink(index=$($commandIndex))"
        try {
            $response = Invoke-APICall -apiCall $uri -token $token 
        }
        catch {
            throw $_
        }

        if ($response.value) {
            $result = Invoke-RestMethod -UseBasicParsing -uri $response.value -Method Get
            return $result
        }
    
    }
}

<#
.SYNOPSIS
Gets machine actions

.DESCRIPTION
Retrieves machine actions from the Defender API based on the filter supplied

.PARAMETER filter
An ODATA filter

.PARAMETER token
An auth token (not required if currently cached)

.EXAMPLE
Get-MachineActions -filter "status eq 'Succeeded'"

#>
function Get-MachineActions {
    param (
        [Parameter(Position = 0, mandatory = $false)] [string]$filter,
        [Parameter(Position = 1, mandatory = $false)] [string]$token
    )
    if (-not $token) {
        $token = $tokencache
    }
    if (-not $token) {
        throw "Please call Connect-SecurityCenter before attempting to call the APIs"
    }

    $uri = "https://$($securityCenterHost)/api/machineactions"
    if ($filter) {
        $uri += ("?`$filter=$($filter)" -replace " ", "+")
    }
    try {
        $response = Invoke-APICall -apiCall $uri -token $token 
    }
    catch {
        throw $_
    }
    return $response.value
}
