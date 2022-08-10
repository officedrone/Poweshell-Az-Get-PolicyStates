
#Tenant ID Variable
$TenantID = "Your-Tenant-ID-Here"

#Check if connected to Az yet
$AzAccount = Read-Host "Are you connected to AzAccount yet? (y/n)"
while("y","n" -notcontains $AzAccount)
{
    $AzAccount = Read-Host "Are you connected to AzAccount yet? (y/n)"
    
}


#Connect to Az if user selected 'n' above
If ($AzAccount -eq 'n')
{
    Connect-AzAccount -TenantID $TenantID 
}

#Get list of subscriptions to which we have access to
$Subscriptions= Get-AzSubscription

#Present user with subscription list for selection
Write-Host "--------Subscriptions found---------"
foreach ($Subscription in $Subscriptions) 
{
    Write-Host "Name: " $Subscription.Name " | Id: " $Subscription.ID
    
}

Write-Host "-----------------------------------"
$SubscriptionChoice = read-host "Enter the subscription ID for the subscription you'd like to use"

Set-AzContext $SubscriptionChoice





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


#Get all Policy States (Added Top 3000 due to it not being present resulting in partial results. More than 3000 entries apparently causes problems(https://github.com/MicrosoftDocs/azure-docs/issues/41368))
#If you have more than 3000 policy states in your subscription then consider adapting this script to run against a smaller scope (e.g. resource group)
$PolicyStates = Get-AzPolicyState -Top 3000| Select-Object   SubscriptionID, PolicySetDefinitionName, PolicyDefinitionName, PolicyDefinitionAction, PolicySetDefinitionCategory, ResourceGroup, ResourceID, ResourceLocation, ResourceType, ComplianceState |Sort-Object SubscriptionID, PolicySetDefinitionName, PolicyDefinitionName

#Initialize count
$Count = 1

#Iterate through all policy states
foreach ($PolicyState in $PolicyStates)
{

    Write-Host "Processing State " $Count " of " $PolicyStates.count
    #Only call to cloud if PolicyDefinitionName is a different value then get the name for the new policy defintion 
    if ($LoopPolicyDefinitionName -ne $PolicyState.PolicyDefinitionName)
    {
        $LoopPolicyDefinitionDescriptiveName = Get-AzPolicyDefinition -Name $PolicyState.PolicyDefinitionName |Select-Object -ExpandProperty "Properties" | Select-Object -ExpandProperty "displayName"
        #Set loop variables for polciy and policy set definition names. This is to avoid mutliple calls for name for repeat names
        $LoopPolicyDefinitionName = $PolicyState.PolicyDefinitionName
    }
    #Only call to cloud if PolicyDefinitionSetName is a different value then get the name for the new policy defintion set
    if ($LoopPolicySetDefinitionName -ne $PolicyState.PolicySetDefinitionName)
    {
        #Get the policy display name and assign to variable
        $LoopPolicSetDefinitionDescriptiveName = Get-AzPolicySetDefinition -Name $PolicyState.PolicySetDefinitionName |Select-Object -ExpandProperty "Properties" | Select-Object -ExpandProperty "displayName"
        
        #Set loop variables for polciy and policy set definition names. This is to avoid mutliple calls for name for repeat names
        $LoopPolicySetDefinitionName = $PolicyState.PolicySetDefinitionName
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
