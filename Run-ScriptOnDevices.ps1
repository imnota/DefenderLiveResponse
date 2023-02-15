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
[CmdletBinding()]
param (
    [Parameter(Position = 0, mandatory = $true)] [string[]] $deviceList,
    [Parameter(Position = 1, mandatory = $true)] [string] $scriptName,
    [Parameter(Position = 2, mandatory = $true)] [string] $appID,
    [Parameter(Position = 3, mandatory = $true)] [string] $tenantID,
    [Parameter(Position = 4, mandatory = $true)] [string] $secret,
    [Parameter(Position = 5, mandatory = $false)] [ValidateRange(1, 10)] [int] $maxCallsPerMin = 10,
    [Parameter(Position = 6, mandatory = $false)] [ValidateRange(1, 20)] [int] $maxLiveResponseSessions = 20,
    [Parameter(Position = 7, mandatory = $false)] [ValidateRange(1, 10)] [int] $maxMinInProgress = 5,
    [Parameter(Position = 8, mandatory = $false)] [string] $batchName = "Automated Live Response"
      
)

function Write-Feedback {
    param (
        [String] $Text
    )
    #Function to display indented text in different colours
    #If using in automation, use write-output instead of write-host

    switch ($text.Substring(0, 1)) {  
        "[" {
            $displayText = "    $($text)"
        }
        Default {
            $displayText=$text
        }
    }
    
    
    if ($PSPrivateMetadata.JobId -or $env:AUTOMATION_ASSET_ACCOUNTID) {
        Write-Output "$($displayText)"
    }
    else {
        switch ($text.Substring(0, 3)) {
            "[+]" {
                Write-Host -ForegroundColor Green "$($displayText)"
            }
            "[-]" {
                Write-Host -ForegroundColor Blue "$($displayText)"
            }
            "[*]" {
                Write-Host -ForegroundColor red "$($displayText)"
            }
            "[X]" {
                Write-Host -ForegroundColor Yellow "$($displayText)"
            }
            Default {
                write-host -ForegroundColor DarkGreen $displayText
            }
        }
    }
}

$batchName = "$($batchName) $(get-date)"

#Now ensure uniqueness of requests
$devicelist=$devicelist|select -unique 

Write-Feedback "Will attempt to run $($scriptName) on $($deviceList.count) devices"
Write-Feedback "$($maxCallsPerMin) maximum calls will be made per minute"
Write-Feedback "Calls will be canceled for Pending or InProgress devices after $($maxMinInProgress) minutes"
Write-Feedback "RequestorComment will be set to $($batchName)`n"
import-module .\DefenderRemediation.psm1

#So, first connect to the Defender for endpoint APIs
$token = Connect-SecurityCenter -appID $appID -tenantID $tenantID -appSecret $secret -returnToken $true

#And work out when the token expires
$tokenExpiresAt = ([DateTime]("1970,1,1")).AddSeconds($token.expires_on)

#Let's declare 2 hashtables, one to hold the processing status for each device
$processing = @{}

#And one to hold information about each supplied Device
$devices = @{}

#So, let's pull down the machine list into the hashtable
$machineList = get-machines | where { $_.computerDNSName -in $deviceList }
$machineList | foreach { $devices[$_.computerDNSName] = $_ }

#Now the real work - we need to loop through the devices at a rate of $maxCallsPerMin
while ($devices.count -gt 0 -or ($processing.count -gt 0)) {
    #Need to add check for token expiration and reconnect if necessary!
    if ((get-date).addminutes(5) -gt $tokenExpiresAt) {
        #Oh no, the token has nearly expired
        Write-Verbose "Reauthenticating"
        $token = Connect-SecurityCenter -appID $appID -tenantID $tenantID -appSecret $secret -returnToken $true
        $tokenExpiresAt = ([DateTime]("1970,1,1")).AddSeconds($token.expires_on)
    }
    
    #See if any of our sessions have completed or should expire
    if ($processing.count -gt 0) {
        $processingSessions = get-machineactions -filter "id in ('$($processing.values.id -join "','")')"
    }
    foreach ($processingSession in $processingSessions) {
        #So, have any liveResponseSessions completed?
        if ($processingSession.status -in ("Succeeded", "Cancelled", "Failed", "TimeOut")) {
            Write-Feedback   "[-] $($processingsession.computerDNSName) completed with status of $($processingSession.status)"
            $processing.Remove($processingSession.ID)
        }
        else {
            if (((get-date) - ([datetime]$processingsession.creationDateTimeUtc)).minutes -gt $maxMinInProgress) {
                #Something has been running too long, let's stop it!
                Write-Feedback  "[X] Cancelling job for $($processingsession.computerDNSName)"
                Invoke-CancelMachineAction -id $processingsession.ID | Out-Null
                $processing.Remove($processingSession.Id)
                
            }
        }
    }

    #So, we now kow how many we still have processing, we need to submit other jobs!
    #Before doing so we need to know how many live response sessions are currently running so we don't break our limit
    #We won't take the risk that a pending session could go live either!
    Write-Verbose "Retrieving machineactions"
    $runningSessions = get-machineactions -filter "(status eq 'InProgress' or status eq 'Pending')"
    #How many sessions can we submit?
    $roomFor = 0

    if (($runningSessions.count -lt $maxLiveResponseSessions)) {
        $roomFor = $maxLiveResponseSessions - $runningSessions.count
        if ($roomfor -gt $maxCallsPerMin) {
            $roomfor = $maxCallsPerMin
        }
    }
    
    #But we may not have that many left
    if ($devices.Count -lt $roomfor) {
        $roomFor = $devices.Count
    }
    Write-Verbose "We have room for $($roomFor) sessions"

    #OK, now we can submit the correct number of sessions!
    $keysToRemove = @()
    for ($sessionNo = 0; $sessionNo -lt $roomfor; $sessionNo++) {
        if ($devices.Keys.Count -gt 1) {
            $deviceKey = $($devices.Keys)[$sessionNo]
        }
        else {
            $devicekey = $devices.Keys
        }
        try {
            Write-Feedback "[+] Starting liveResponse on $($devicekey)"
            $result = Invoke-LiveResponseScript -aaddeviceid $devices[$deviceKey].aadDeviceID -comment "$($batchName)" -scriptname "$($scriptName)"
            $keysToRemove += $devicekey
            $processing[$result.id] = $result
        }
        catch {
            #Something went wrong - we need to remove the job from those being awaiting processing
            Write-Feedback "[X] Unable to start liveResponse session for $($devicekey): $_"
            #If it's a 429 - too many calls, we can leave it in to attempt reprocessing
            #otherwise we want to remove it as it has errored
            if ($_.Exception.Response.statuscode.value__ -ne 429) {
                $keysToRemove += $devicekey
            }
        }
    }
    foreach ($key in $keysToRemove) {
        $devices.Remove($key)
    }
    if ($devices.count -gt 0 -or ($processing.count -gt 0)) {
        #Wait the requisite 60 seconds to ensure we don't make too many calls!
        Write-Verbose "WAITING 60"
        start-sleep -Seconds 60 
    }
}
Write-Feedback "`nCompleted with the following results for ""$($batchName)"":`n"
Get-MachineActions | where { $_.requestorcomment -eq $batchName } | group status -noelement | foreach { Write-Feedback "    $($_.count) $($_.Name)" }
Write-Host "`n"