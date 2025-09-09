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
$existingContext = Get-AzContext -ErrorAction SilentlyContinue

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

# Function to select subscriptions with removal capability
function Select-Subscriptions {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SelectionMode
    )

    $subscriptions = Get-AzSubscription | Sort-Object Name
    if ($subscriptions.Count -eq 0) {
        Write-Host "No Azure subscriptions found for this account." -ForegroundColor Red
        exit
    }

    $selectedSubscriptions = @()

    if ($SelectionMode -eq "Single") {
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

        $selectedIndex = [int]$choice - 1
        $selectedSubscriptions += $subscriptions[$selectedIndex]
    }
    elseif ($SelectionMode -eq "Multiple") {
        Write-Host "`nAvailable subscriptions:" -ForegroundColor Cyan
        for ($i=0; $i -lt $subscriptions.Count; $i++) {
            Write-Host "$($i+1)) $($subscriptions[$i].Name) ($($subscriptions[$i].Id))"
        }

        Write-Host "`nEnter subscription numbers separated by commas (e.g. 1,3,5) or 'q' to exit"
        do {
            $choice = Read-Host "Enter selection"
            if ($choice -eq 'q') { exit }

            $numbers = $choice -split ',' | ForEach-Object { $_.Trim() }
            $validNumbers = @()
            $valid = $true

            foreach ($num in $numbers) {
                if ([int]::TryParse($num, [ref]$null) -and 
                    $num -ge 1 -and $num -le $subscriptions.Count) {
                    $validNumbers += [int]$num
                } else {
                    $valid = $false
                    break
                }
            }

            if ($valid -and $numbers.Count -gt 0) {
                foreach ($num in $validNumbers) {
                    $selectedIndex = $num - 1
                    $selectedSubscriptions += $subscriptions[$selectedIndex]
                }
                break
            } else {
                Write-Host "Invalid input. Please enter valid numbers separated by commas." -ForegroundColor Yellow
            }
        } while ($true)
    }
    elseif ($SelectionMode -eq "All") {
        $selectedSubscriptions = $subscriptions
    }

    return $selectedSubscriptions
}

# Main subscription selection menu
Write-Host "`nSelect subscription mode:" -ForegroundColor Cyan
Write-Host "1) Single subscription"
Write-Host "2) Multiple subscriptions" 
Write-Host "3) All subscriptions"
Write-Host "4) Exit"

do {
    $choice = Read-Host "`nEnter your choice (1-4)"
    if ($choice -eq '4') { exit }
    if ($choice -ge 1 -and $choice -le 4) {
        break
    }
    Write-Host "Invalid input. Please enter a number between 1 and 4." -ForegroundColor Yellow
} while ($true)

$subscriptionMode = switch ($choice) {
    1 { "Single" }
    2 { "Multiple" }
    3 { "All" }
}

# Get selected subscriptions based on mode
$selectedSubscriptions = Select-Subscriptions -SelectionMode $subscriptionMode

# File output selection
Write-Host "`nSelect file output mode:" -ForegroundColor Cyan
Write-Host "1) Single CSV file for all subscriptions"
Write-Host "2) Separate CSV file per subscription"
Write-Host "3) Both (single file and separate files)"
Write-Host "4) Exit"

do {
    $fileChoice = Read-Host "`nEnter your choice (1-4)"
    if ($fileChoice -eq '4') { exit }
    if ($fileChoice -ge 1 -and $fileChoice -le 4) {
        break
    }
    Write-Host "Invalid input. Please enter a number between 1 and 4." -ForegroundColor Yellow
} while ($true)

$fileOutputMode = switch ($fileChoice) {
    1 { "Single" }
    2 { "Separate" }
    3 { "Both" }
}

# Process policy states for each selected subscription
$csvPath = "Output-PolicyComplianceStates.csv"
$PolicyStates = @()
$policyDefinitionsCache = @{}
$policySetDefinitionsCache = @{}

try {
    # Pre-fetch all policy definitions to avoid repeated API calls
    Write-Host "Fetching all policy definitions..."
    $allPolicyDefinitions = Get-AzPolicyDefinition -ErrorAction Stop
    foreach ($definition in $allPolicyDefinitions) {
        $policyDefinitionsCache[$definition.Name] = $definition.DisplayName
    }

    Write-Host "Fetching all policy set definitions..."
    $allPolicySetDefinitions = Get-AzPolicySetDefinition -ErrorAction Stop
    foreach ($definition in $allPolicySetDefinitions) {
        $policySetDefinitionsCache[$definition.Name] = $definition.DisplayName
    }

    # Initialize report object
    $reportTemplate = New-Object psobject
    $reportTemplate | Add-Member -MemberType NoteProperty -name SubscriptionID -Value $null
    $reportTemplate | Add-Member -MemberType NoteProperty -name SubscriptionName -Value $null
    $reportTemplate | Add-Member -MemberType NoteProperty -name PolicySetDefinitionName -Value $null
    $reportTemplate | Add-Member -MemberType NoteProperty -name PolicySetDefinitionDescriptiveName -Value $null
    $reportTemplate | Add-Member -MemberType NoteProperty -name PolicyDefinitionName -Value $null
    $reportTemplate | Add-Member -MemberType NoteProperty -name PolicyDefinitionDescriptiveName -Value $null
    $reportTemplate | Add-Member -MemberType NoteProperty -name PolicySetDefinitionCategory -Value $null
    $reportTemplate | Add-Member -MemberType NoteProperty -name ResourceGroup -Value $null
    $reportTemplate | Add-Member -MemberType NoteProperty -name ResourceID -Value $null
    $reportTemplate | Add-Member -MemberType NoteProperty -name ResourceLocation -Value $null
    $reportTemplate | Add-Member -MemberType NoteProperty -name ResourceType -Value $null
    $reportTemplate | Add-Member -MemberType NoteProperty -name PolicyDefinitionAction -Value $null
    $reportTemplate | Add-Member -MemberType NoteProperty -name ComplianceState -Value $null

    # Handle file output modes
    if ($fileOutputMode -eq "Single" -or $fileOutputMode -eq "Both") {
        # Prepare the CSV file – delete if it already exists, then create a fresh file with the correct header.
        if (Test-Path -LiteralPath $csvPath) {
            Remove-Item -LiteralPath $csvPath -Force
        }
        # Export the *empty* report object once – this writes only the headers
        $reportTemplate | Export-Csv -Path $csvPath -NoTypeInformation
    }

    # Initialize count
    $Count = 1
    $totalItems = 0

    # Process each subscription
    foreach ($subscription in $selectedSubscriptions) {
        Write-Host "`nProcessing subscription: $($subscription.Name) ($($subscription.Id))" -ForegroundColor Cyan

        # Set context to current subscription
        Set-AzContext -SubscriptionId $subscription.Id | Out-Null

        # Get policy states for this subscription
        Write-Host "Fetching policy states..."
        $subscriptionPolicyStates = Get-AzPolicyState -ErrorAction Stop | 
                        Select-Object SubscriptionID, PolicySetDefinitionName, PolicyDefinitionName, 
                                     PolicyDefinitionAction, PolicySetDefinitionCategory, ResourceGroup, 
                                     ResourceID, ResourceLocation, ResourceType, ComplianceState |
                        Sort-Object SubscriptionID, PolicySetDefinitionName, PolicyDefinitionName 

        if ($null -eq $subscriptionPolicyStates) {
            Write-Host "No policy states found for subscription: $($subscription.Name)" -ForegroundColor Yellow
            continue
        }

        $totalItems += $subscriptionPolicyStates.Count

        # Handle file output modes
        if ($fileOutputMode -eq "Separate" -or $fileOutputMode -eq "Both") {
            $singleCsvPath = "Output-PolicyComplianceStates-$($subscription.Name).csv"
            if (Test-Path -LiteralPath $singleCsvPath) {
                Remove-Item -LiteralPath $singleCsvPath -Force
            }
            # Export the *empty* report object once – this writes only the headers for the subscription file
            $reportTemplate | Export-Csv -Path $singleCsvPath -NoTypeInformation
        }

        # Iterate through all policy states for this subscription
        foreach ($PolicyState in $subscriptionPolicyStates) {
            Write-Progress -Activity "Processing Policy States" -Status "Processing State $Count of $totalItems" -PercentComplete ($Count / $totalItems * 100)

            try {
                # Create a new report object for each policy state to avoid overwriting
                $report = $reportTemplate | Select-Object * -ExcludeProperty PSComputerName, PSShowComputerName, PSVersionTable

                # Get descriptive names from cache or API
                $policyDefinitionDisplayName = ""
                if ($PolicyState.PolicyDefinitionName) {
                    if ($policyDefinitionsCache.ContainsKey($PolicyState.PolicyDefinitionName)) {
                        $policyDefinitionDisplayName = $policyDefinitionsCache[$PolicyState.PolicyDefinitionName]
                    } else {
                        # Fallback to API call if not in cache (shouldn't happen)
                        $definition = Get-AzPolicyDefinition -Name $PolicyState.PolicyDefinitionName -ErrorAction Stop
                        $policyDefinitionDisplayName = $definition.DisplayName
                        $policyDefinitionsCache[$PolicyState.PolicyDefinitionName] = $policyDefinitionDisplayName
                    }
                }

                $policySetDefinitionDisplayName = ""
                if ($PolicyState.PolicySetDefinitionName) {
                    if ($policySetDefinitionsCache.ContainsKey($PolicyState.PolicySetDefinitionName)) {
                        $policySetDefinitionDisplayName = $policySetDefinitionsCache[$PolicyState.PolicySetDefinitionName]
                    } else {
                        # Fallback to API call if not in cache (shouldn't happen)
                        $definition = Get-AzPolicySetDefinition -Name $PolicyState.PolicySetDefinitionName -ErrorAction Stop
                        $policySetDefinitionDisplayName = $definition.DisplayName
                        $policySetDefinitionsCache[$PolicyState.PolicySetDefinitionName] = $policySetDefinitionDisplayName
                    }
                }

                # Generate Report
                $report.SubscriptionID = $PolicyState.SubscriptionId
                $report.SubscriptionName = $subscription.Name
                $report.PolicySetDefinitionName = $PolicyState.PolicySetDefinitionName
                $report.PolicySetDefinitionDescriptiveName = $policySetDefinitionDisplayName
                $report.PolicyDefinitionName = $PolicyState.PolicyDefinitionName
                $report.PolicyDefinitionDescriptiveName = $policyDefinitionDisplayName
                $report.PolicyDefinitionAction = $PolicyState.PolicyDefinitionAction
                $report.PolicySetDefinitionCategory = $PolicyState.PolicySetDefinitionCategory
                $report.ResourceGroup = $PolicyState.ResourceGroup
                $report.ResourceID = $PolicyState.ResourceID
                $report.ResourceLocation = $PolicyState.ResourceLocation
                $report.ResourceType = $PolicyState.ResourceType
                $report.ComplianceState = $PolicyState.ComplianceState

                # Export report to CSV based on output mode
                if ($fileOutputMode -eq "Single" -or $fileOutputMode -eq "Both") {
                    $report | Export-CSV -Path $csvPath -Append -NoTypeInformation
                }

                if ($fileOutputMode -eq "Separate" -or $fileOutputMode -eq "Both") {
                    $singleCsvPath = "Output-PolicyComplianceStates-$($subscription.Name).csv"
                    $report | Export-CSV -Path $singleCsvPath -Append -NoTypeInformation
                }

                $Count++
            } catch {
                Write-Warning "Error processing policy state: $_"
                continue
            }
        }
    }
    Write-Progress -Activity "Complete" -Status "Operation Finished" -Completed

    Write-Host "`nScript completed successfully." -ForegroundColor Green

    if ($fileOutputMode -eq "Single") {
        Write-Host "Results exported to: $csvPath" -ForegroundColor Cyan
    } elseif ($fileOutputMode -eq "Separate") {
        Write-Host "Separate files created for each subscription" -ForegroundColor Cyan
    } elseif ($fileOutputMode -eq "Both") {
        Write-Host "Results exported to: $csvPath (master file)" -ForegroundColor Cyan
        Write-Host "Separate files created for each subscription" -ForegroundColor Cyan
    }
}
catch {
    Write-Error "An error occurred: $_"
    exit 1
}


#Get-azPolicyExcemption logic - coming soon
