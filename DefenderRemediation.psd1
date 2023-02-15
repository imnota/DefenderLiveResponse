@{

    # Script module or binary module file associated with this manifest.
    RootModule = '.\DefenderRemediation.psm1'
    
    # Version number of this module.
    ModuleVersion = '1.0.0.0'
    
    # Supported PSEditions
    # CompatiblePSEditions = @()
    
    # ID used to uniquely identify this module
    GUID = 'bae61e39-dfe6-455c-b9b7-ff0fee16ddff'
    
    # Author of this module
    Author = 'Andy Blackman'
        
    # Copyright statement for this module
    Copyright = '(c) 2023 Andy Blackman'
    
    # Description of the functionality provided by this module
    Description = 'DefenderRemediation provides functionality to run scripts via live response in Defender.'
        
    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = 'Connect-SecurityCenter','Get-Machines', `
                        'Get-MachineAction','Get-MachineActions','Get-MachineActionResult','Invoke-CancelMachineAction', `
                        'Invoke-LiveResponseScript'
    
    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = ''
    
    # Variables to export from this module
    VariablesToExport = ''
    
    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport = ''
    
    # DSC resources to export from this module
    # DscResourcesToExport = @()
    
    # List of all modules packaged with this module
    # ModuleList = @()
    
    # List of all files packaged with this module
    # FileList = @()
    
    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.

    # HelpInfo URI of this module
    # HelpInfoURI = ''
    
    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    # DefaultCommandPrefix = ''
    
    }
    