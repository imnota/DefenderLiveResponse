# About
This repository conatins a sample module for using some of the Microsoft Defender for Endpoint APIs as well as some sample code which demonstrates how it can be used to run a Live Response scripts on multiple devices.

# Prerequisites
Your target device(s) need to be licensed for Microsoft Defender for Endpoint or Microsoft 365 Defender and must have already been onboarded.

You need to set up an Application Registration in Azure AD to grant access to the APIs - a guide can be found in [Setting up the Application](docs/Setting%20up%20the%20Application.pdf)

Any scripts you wish to run on the devices must already be uploaded to the Live Response Library

# History
This was originally designed to assist in fixing an issue with Intune Device Management where certificates had been deployed to devices using the same Subject Name / CN as the Intune Device Management certificate (a CN of the Intune device ID) before the documentation was updated to warn against this.

Using the Run-ScriptOnDevices.ps1 script in conjunction with a small script to delete any certificates matching the CN of the Intune MDM certificate (but not issued by the Intune CA) fixed the issue where the device may stop communicating with Intune if a second certificate exists.

A script demonstrating the basic principal of this can be found in [sample live response library scripts](sample%20live%20response%20library%20scripts) - this is only provided as an example to show a potential technique and should be thoroughly checked and modified before considering deploying to any environment.

# Use
Download all the files from, or clone the repository.

After setting up the application in Azure AD and noting the required information, you can run the script similar to below:
```powershell
.\Run-ScriptOnDevices.ps1 -deviceList ('desktop-a99b99c9','laptop-d88e88f8') -scriptName "my-preuploaded-script.ps1" -appID "[appId]" -tenantID "[tenantID]" -secret "[secret]" -batchName "Something to help identify your batch of script runs"
```
Replacing the "[appId]", "[tenantId]" and "[secret]" with the values from your application and the device list with an array of devicenames you want to run the script on.
