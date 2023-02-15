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

###############################################################################
#
#  PLEASE NOTE - THIS SCRIPT MAY NOT BE SUITABLE IN YOUR ENVIRONMENT
#                MODIFY AND TEST BEFORE USE
#
###############################################################################

write-output "Running on $(hostname)"
$mdmCertIssuer = "CN=Microsoft Intune MDM Device CA"
$allCerts = dir cert:\\LocalMachine\My
$mdmCert = $allcerts | where { $_.Issuer -eq $mdmCertIssuer }
write-output "Determined the following are Intune MDM issued certs:"
$mdmCert | foreach {
    write-output "    $($_.subject) issued by $($_.Issuer)"
}
$dodgyCertificates = $allCerts | where { $_.Issuer -ne $mdmCertIssuer -and $_.subject -in $mdmCert.subject }
if ($dodgyCertificates) {
    Write-Output "The following certificates were not issued by Intune MDM:"
    $dodgyCertificates | foreach {
        write-output "    $($_.subject) issued by $($_.Issuer)"
    }
}

if ($dodgyCertificates) {
    try {
        foreach ($cert in $dodgyCertificates) {
            if ($cert.Thumbprint) {
                write-output "Removing cert:\\LocalMachine\My\$($cert.Thumbprint)"
                remove-Item "cert:\\LocalMachine\My\$($cert.Thumbprint)"
            }
        }
        Get-ScheduledTask | where { $_.TaskName -eq "PushLaunch" } | Start-ScheduledTask
        exit 0
    }
    catch {
        write-error $error[0]
        exit 1
    }
}
else {
    Write-Output "No certificates to delete"
}