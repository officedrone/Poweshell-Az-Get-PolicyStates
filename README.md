# Poweshell-Az-Get-PolicyStates
Get a list of all policies and whether they comply with Azure Policies


##Script information
This script uses the Az module to connect and gather Azure policy compliance states for all resources within an Azure Subscription.

#Sample output
![image](https://user-images.githubusercontent.com/67024372/183928207-ced52591-14ea-4f2b-bc71-e45db69fc53d.png)




This is essentially a powershell version of the Azure Portal policy compliance page (https://portal.azure.com/#view/Microsoft_Azure_Policy/PolicyMenuBlade/~/Overview)

##Requirements
- Powershell 5.x or above
- Azure module (install by running : Install-Module -Name Az  (https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-8.2.0)
- Read permissions to Azure Policy objects (or global read to the subscription tenant)

## Limitations
- More than 3000 Policy State entries entries apparently causes problems(https://github.com/MicrosoftDocs/azure-docs/issues/41368)). If you have more than 3000 policy states in your subscription then consider adapting this script to run against a smaller scope (e.g. resource group)
- The script does not list policy exceptions (yet)


##Before running the script
- Open the script and change the $TenantID variable to your Tenant ID
![image](https://user-images.githubusercontent.com/67024372/183925203-bce08b0d-71ae-467e-b6de-663bb1b0f3af.png)
