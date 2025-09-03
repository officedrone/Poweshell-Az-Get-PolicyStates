


# Verify required Azure PowerShell modules are installed
$requiredModules = @('Az.Accounts', 'Az.PolicyInsights')

foreach ($mod in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        Write-Host "The Azure PowerShell module '$mod' is not installed on this machine."
        Write-Host ""
        Write-Host "You can install it with the following command:"
        Write-Host ""
        Write-Host "   Install-Module -Name $mod -Scope CurrentUser -Repository PSGallery"
        Write-Host ""
        Write-Host "After installation, re-run this script."
        exit
    }
}

# Confirmation that all required modules are present
Write-Host "All required Azure PowerShell modules (Az.Accounts, Az.PolicyInsights) are installed." -ForegroundColor Green


# Auto‑detect an existing Azure session or log in
$existingContext = Get-AzContext -ErrorAction SilentlyContinue   # <‑ keep this

if (-not $existingContext) {
    Write-Host "No active Az session detected - logging in now…"
    do {
        $TenantInput = Read-Host "Enter your Azure tenant ID (GUID) or 'q' to exit"
        if ($TenantInput -eq 'q') { exit }
        if ($TenantInput -match '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') {
            $TenantID = $TenantInput
            break
        }
        Write-Host "Invalid tenant ID. Please enter a GUID in the format xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx."
    } while ($true)

    Connect-AzAccount -TenantId $TenantID | Out-Null

    # After login, automatically pick the *current* subscription that Azure
    # selects for you (usually the first one listed).  This avoids a second
    # prompt later in the script.
    Set-AzContext -SubscriptionName (Get-AzContext).Subscription.Name | Out-Null
}
else {
    Write-Host "Active Az session detected. Using existing context:" -ForegroundColor Cyan
}

# ----------------------------------------------------------------------
# Only run the manual subscription‑selection UI if we started with an
# already‑logged‑in session *and* that session had multiple subscriptions.
# If we just logged in above, skip this block entirely.
if ($existingContext) {
    Write-Host "Select a subscription:" -ForegroundColor Cyan

    $subscriptions = Get-AzSubscription | Sort-Object Name
    if ($subscriptions.Count -eq 0) {
        Write-Host "No Azure subscriptions found for this account." -ForegroundColor Red
        exit
    }

    if ($subscriptions.Count -eq 1) {
        $selectedSubId   = $subscriptions[0].Id
        $selectedSubName = $subscriptions[0].Name
    }
    else {
        Write-Host "`nAvailable subscriptions:" -ForegroundColor Cyan
        for ($i=0; $i -lt $subscriptions.Count; $i++) {
            Write-Host "$($i+1)) $($subscriptions[$i].Name) ($($subscriptions[$i].Id))"
        }
        do {
            $choice = Read-Host "`nEnter the subscription number you want to query policy states against (or 'q' to exit)"
            if ($choice -eq 'q') { exit }
            if ([int]::TryParse($choice, [ref]$null) -and
                $choice -ge 1 -and $choice -le $subscriptions.Count) {
                break
            }
            Write-Host "Invalid input. Please enter a number between 1 and $($subscriptions.Count)." -ForegroundColor Yellow
        } while ($true)

        $selectedIndex   = [int]$choice - 1
        $selectedSubId   = $subscriptions[$selectedIndex].Id
        $selectedSubName = $subscriptions[$selectedIndex].Name
    }

    Set-AzContext -SubscriptionId $selectedSubId | Out-Null
}

# Get the active context after login (or after the UI selection)
$current = Get-AzContext

Write-Host "`nUsing subscription: $($current.Subscription.Name) ($($current.Subscription.Id))`n"






#Arrays
$PolicyStates = @() #Array for all Policy States
#$PolicyExemptions = @() #Array for Policy Exemptions - Coming soon

$LoopPolicyDefinitionName = 'String'
$LoopPolicyDefinitionDescriptiveName = 'String'
$LoopPolicySetDefinitionName = 'String'
$LoopPolicSetDefinitionDescriptiveName = 'String'

#Report Variables
$report = New-Object psobject #initialize report array
$report | Add-Member -MemberType NoteProperty -name SubscriptionID -Value $null
$report | Add-Member -MemberType NoteProperty -name PolicySetDefinitionName -Value $null
$report | Add-Member -MemberType NoteProperty -name PolicySetDefinitionDescriptiveName -Value $null
$report | Add-Member -MemberType NoteProperty -name PolicyDefinitionName -Value $null
$report | Add-Member -MemberType NoteProperty -name PolicyDefinitionDescriptiveName -Value $null
$report | Add-Member -MemberType NoteProperty -name PolicySetDefinitionCategory -Value $null
$report | Add-Member -MemberType NoteProperty -name ResourceGroup -Value $null
$report | Add-Member -MemberType NoteProperty -name ResourceID -Value $null
$report | Add-Member -MemberType NoteProperty -name ResourceLocation -Value $null
$report | Add-Member -MemberType NoteProperty -name ResourceType -Value $null
$report | Add-Member -MemberType NoteProperty -name PolicyDefinitionAction -Value $null
$report | Add-Member -MemberType NoteProperty -name ComplianceState -Value $null


# Prepare the CSV file – delete if it already exists, then create a fresh file with the correct header.
$csvPath = "Output-PolicyComplianceStates.csv"

if (Test-Path -LiteralPath $csvPath) {
    Remove-Item -LiteralPath $csvPath -Force
}

# Export the *empty* report object once – this writes only the headers
$report | Export-Csv -Path $csvPath -NoTypeInformation

#Get all Policy States (Uncomment the top 3000 line below if running in issues due to it not being present resulting in partial results. More than 3000 entries apparently causes problems(https://github.com/MicrosoftDocs/azure-docs/issues/41368))
#If you have more than 3000 policy states in your subscription then consider adapting this script to run against a smaller scope (e.g. resource group)
#$PolicyStates = Get-AzPolicyState -Top 3000| Select-Object   SubscriptionID, PolicySetDefinitionName, PolicyDefinitionName, PolicyDefinitionAction, PolicySetDefinitionCategory, ResourceGroup, ResourceID, ResourceLocation, ResourceType, ComplianceState |Sort-Object SubscriptionID, PolicySetDefinitionName, PolicyDefinitionName

#comment this line if you uncomment the above line
$PolicyStates = Get-AzPolicyState | Select-Object   SubscriptionID, PolicySetDefinitionName, PolicyDefinitionName, PolicyDefinitionAction, PolicySetDefinitionCategory, ResourceGroup, ResourceID, ResourceLocation, ResourceType, ComplianceState |Sort-Object SubscriptionID, PolicySetDefinitionName, PolicyDefinitionName 

#Initialize count
$Count = 1

#Iterate through all policy states
foreach ($PolicyState in $PolicyStates)
{

    Write-Host "Processing State " $Count " of " $PolicyStates.count
    #Only call to cloud if PolicyDefinitionName is a different value then get the name for the new policy defintion 
    if ($LoopPolicyDefinitionName -ne $PolicyState.PolicyDefinitionName)
    {
        $LoopPolicyDefinitionDescriptiveName = Get-AzPolicyDefinition -Name $PolicyState.PolicyDefinitionName |  Select-Object -ExpandProperty displayName
        #Set loop variables for polciy and policy set definition names. This is to avoid mutliple calls for name for repeat names
        $LoopPolicyDefinitionName = $PolicyState.PolicyDefinitionName
    }
    #Only call to cloud if PolicyDefinitionSetName is a different value then get the name foDefir the new policy defintion set
    # Only proceed if a PolicySetDefinitionName exists (not null/empty)
    if ($PolicyState.PolicySetDefinitionName) {

        # If this is a new policy‑set name, cache its display name
        if ($LoopPolicySetDefinitionName -ne $PolicyState.PolicySetDefinitionName) {
            $LoopPolicSetDefinitionDescriptiveName =
                Get-AzPolicySetDefinition -Name $PolicyState.PolicySetDefinitionName |
                Select-Object -ExpandProperty displayName

            # Cache the name so we don’t call again for the same value
            $LoopPolicySetDefinitionName = $PolicyState.PolicySetDefinitionName
        }

    }
    else {
        # Optional: handle missing PolicySetDefinitionName (e.g., set to empty string)
        $LoopPolicSetDefinitionDescriptiveName = ""
        $LoopPolicySetDefinitionName = $null
    }


    #Generate Report
    $report.SubscriptionID = $PolicyState.SubscriptionId
    $report.PolicySetDefinitionName = $LoopPolicySetDefinitionName
    $report.PolicySetDefinitionDescriptiveName = $LoopPolicSetDefinitionDescriptiveName
    $report.PolicyDefinitionDescriptiveName = $LoopPolicyDefinitionDescriptiveName
    $report.PolicyDefinitionName = $LoopPolicyDefinitionName
    $report.PolicyDefinitionAction = $PolicyState.PolicyDefinitionAction
    $report.PolicySetDefinitionCategory = $PolicyState.PolicySetDefinitionCategory
    $report.ResourceGroup = $PolicyState.ResourceGroup
    $report.ResourceID = $PolicyState.ResourceID
    $report.ResourceLocation = $PolicyState.ResourceLocation
    $report.ResourceType = $PolicyState.ResourceType
    $report.ComplianceState = $PolicyState.ComplianceState

    
    #Export report to CSV
    $report| Export-CSV Output-PolicyComplianceStates.csv -Append -NoTypeInformation

    #Increase count
    $Count++
}

#Get-azPolicyExcemption logic - coming soon
