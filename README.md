# Poweshell-Az-Get-PolicyStates
Query Azure resources within a single/multiple/all subscriptions and generate a report on how they comply with assigned Azure Policies.


## Script information
This script uses the Az module to connect and gather Azure policy compliance states for all resources within an Azure Subscription, essentially a basic powershell version of the Azure Portal policy compliance page (https://portal.azure.com/#view/Microsoft_Azure_Policy/PolicyMenuBlade/~/Overview)

## Sample output
![image](https://user-images.githubusercontent.com/67024372/183928207-ced52591-14ea-4f2b-bc71-e45db69fc53d.png)


## Options
- Subscription selection mode
  <img width="267" height="113" alt="image" src="https://github.com/user-attachments/assets/9a465109-7032-4b90-84ce-da1c19f3ea37" />
- Subscription selection
  <img width="742" height="163" alt="image" src="https://github.com/user-attachments/assets/35425695-88c2-49ab-afe9-0a0679bd4808" />
- File output selection
  <img width="396" height="108" alt="image" src="https://github.com/user-attachments/assets/afb6ea6c-da51-4e0b-9227-19c5072b5d33" />

## Script in action:
- Querying the policy states
  <img width="1116" height="612" alt="image" src="https://github.com/user-attachments/assets/6fa0e1de-1f49-4aad-abb1-dc7fb2932260" />
- Completed successfully:
  <img width="883" height="201" alt="image" src="https://github.com/user-attachments/assets/2dae36b6-b726-4465-8cea-595925cd7beb" />



## Requirements
- Powershell 5.x or above
- Azure module (install by running : Install-Module -Name Az  (https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-8.2.0)
- Read permissions to Azure Policy objects (or global read to the Tenant or Azure Management Group which the subscription is under)

## Limitations
- The script does not list policy exceptions (yet)

