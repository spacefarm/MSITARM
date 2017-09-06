<#
.SYNOPSIS  
 Runbook for shutdown the Azure VM based on CPU usage
.DESCRIPTION  
 Runbook for shutdown the Azure VM based on CPU usage
.EXAMPLE  
.\AutoStop_CreateAlert_Parent.ps1 -WhatIf $false
Version History  
v1.0   - Initial Release  
v2.0   - Added classic support
#>

Param(
[Parameter(Mandatory=$false,HelpMessage="Enter the value for WhatIf. Values can be either true or false")][bool]$WhatIf = $false
)

function CheckExcludeVM ($FilterVMList)
{
    
    [boolean] $ISexists = $false
    [string[]] $invalidvm=@()
    $ExAzureVMList=@()

    foreach($filtervm in $FilterVMList) 
    {
	
		$currentVM = Get-AzureVM | where Name -Like $filtervm  -ErrorAction SilentlyContinue
		if ($currentVM.Count -ge 1)
		{
			$ExAzureVMList+=$vmname
		}
		else
		{
			$currentVM = Get-AzureRmVM | where Name -Like $filtervm  -ErrorAction SilentlyContinue
			if ($currentVM.Count -ge 1)
			{
				$ExAzureVMList+=$vmname
			}
			else
			{
				$invalidvm = $invalidvm+$filtervm
				Write-Error "Error: No VM instance with name $($VMObject.Name) found"
			}
		}
       
    }

    if($invalidvm -ne $null)
    {
        Write-Output "Runbook Execution Stopped! Invalid VM Name(s) in the exclude list: $($invalidvm) "
        Write-Warning "Runbook Execution Stopped! Invalid VM Name(s) in the exclude list: $($invalidvm) "
        exit
    }
    else
    {
        return $ExAzureVMList
    }
    
}

#-----L O G I N - A U T H E N T I C A T I O N-----
$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch 
{
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

#
# Initialize the Azure subscription we will be working against for Classic Azure resources
#
Write-Verbose "Authenticating Classic RunAs account"
$ConnectionAssetName = "AzureClassicRunAsConnection"
$connection = Get-AutomationConnection -Name $connectionAssetName        
Write-Verbose "Get connection asset: $ConnectionAssetName" -Verbose
$Conn = Get-AutomationConnection -Name $ConnectionAssetName
if ($Conn -eq $null)
{
    throw "Could not retrieve connection asset: $ConnectionAssetName. Assure that this asset exists in the Automation account."
}
$CertificateAssetName = $Conn.CertificateAssetName
Write-Verbose "Getting the certificate: $CertificateAssetName" -Verbose
$AzureCert = Get-AutomationCertificate -Name $CertificateAssetName
if ($AzureCert -eq $null)
{
    throw "Could not retrieve certificate asset: $CertificateAssetName. Assure that this asset exists in the Automation account."
}
Write-Verbose "Authenticating to Azure with certificate." -Verbose
Set-AzureSubscription -SubscriptionName $Conn.SubscriptionName -SubscriptionId $Conn.SubscriptionID -Certificate $AzureCert 
Select-AzureSubscription -SubscriptionId $Conn.SubscriptionID


#---------Read all the input variables---------------
$SubId = Get-AutomationVariable -Name 'Internal_AzureSubscriptionId'
$ResourceGroupNames = Get-AutomationVariable -Name 'External_ResourceGroupNames'
$ExcludeVMNames = Get-AutomationVariable -Name 'External_ExcludeVMNames'
$automationAccountName = Get-AutomationVariable -Name 'Internal_AutomationAccountName'
$aroResourceGroupName = Get-AutomationVariable -Name 'Internal_ResourceGroupName'

#-----Prepare the inputs for alert attributes-----
$webhookUri = Get-AutomationVariable -Name 'Internal_AutoSnooze_WebhookUri'

try
    {  
        Write-Output "Runbook Execution Started..."
        [string[]] $VMfilterList = $ExcludeVMNames -split ","
        [string[]] $VMRGList = $ResourceGroupNames -split ","

        #Validate the Exclude List VM's and stop the execution if the list contains any invalid VM
        if (([string]::IsNullOrEmpty($ExcludeVMNames) -ne $true) -and ($ExcludeVMNames -ne "none"))
        {
            Write-Output "Exclude VM's added so validating the resource(s)..."            
            $ExAzureVMList = CheckExcludeVM -FilterVMList $VMfilterList
        } 

        if ($ExAzureVMList -ne $null -and $WhatIf -eq $false)
        {
            foreach($VM in $ExAzureVMList)
            {
                try
                {
                        Write-Output "Disabling the alert rules for VM : $($VM.Name)" 
                        $params = @{"VMObject"=$VM;"AlertAction"="Disable";"WebhookUri"=$webhookUri}                    
                        $runbook = Start-AzureRmAutomationRunbook -automationAccountName $automationAccountName -Name 'AutoStop_CreateAlert_Child' -ResourceGroupName $aroResourceGroupName –Parameters $params
                }
                catch
                {
                    $ex = $_.Exception
                    Write-Output $_.Exception 
                }
            }
        }
        elseif($ExAzureVMList -ne $null -and $WhatIf -eq $true)
        {
            Write-Output "WhatIf parameter is set to True..."
            Write-Output "What if: Performing the alert rules disable for the Exclude VM's..."
            Write-Output $ExcludeVMNames
        }

        $AzureVMListTemp = $null
        $AzureVMList=@()
        ##Getting VM Details based on RG List or Subscription
        if (($VMRGList -ne $null) -and ($VMRGList -ne "*"))
        {
            foreach($Resource in $VMRGList)
            {
                Write-Output "Validating the resource group name ($($Resource.Trim()))" 
                $checkRGname = Get-AzureRmResourceGroup  $Resource.Trim() -ev notPresent -ea 0  
                if ($checkRGname -eq $null)
                {
                    Write-Output "$($Resource) is not a valid Resource Group Name. Please Verify!"
                    Write-Warning "$($Resource) is not a valid Resource Group Name. Please Verify!"
                }
                else
                {                   
                   	# Get classic VM resources in group and record target state for each in table
					$taggedClassicVMs = Find-AzureRMResource -ResourceGroupNameEquals $Resource -ResourceType "Microsoft.ClassicCompute/virtualMachines"
					foreach($vmResource in $taggedClassicVMs)
					{
						Write-Output "VM classic location $vmResource.Location"
						if ($vmResource.ResourceGroupName -Like $Resource)
						{
							$AzureVMList += @{Name = $vmResource.Name; Location = $vmResource.Location; ResourceGroupName = $vmResource.ResourceGroupName; Type = "Classic"}
						}
					}
					
					# Get resource manager VM resources in group and record target state for each in table
					$taggedRMVMs = Find-AzureRMResource -ResourceGroupNameEquals $Resource -ResourceType "Microsoft.Compute/virtualMachines"
					foreach($vmResource in $taggedRMVMs)
					{
						if ($vmResource.ResourceGroupName -Like $Resource)
						{
							$AzureVMList += @{Name = $vmResource.Name; Location = $vmResource.Location; ResourceGroupName = $vmResource.ResourceGroupName; Type = "ResourceManager"}
						}
					}
                }
            }
        } 
        else
        {
            Write-Output "Getting all the VM's from the subscription..."  
           			
			$ResourceGroups = Get-AzureRmResourceGroup 
			foreach ($ResourceGroup in $ResourceGroups)
			{    
				# Get classic VM resources in group 
				$taggedClassicVMs = Find-AzureRMResource -ResourceGroupNameEquals $ResourceGroup.ResourceGroupName -ResourceType "Microsoft.ClassicCompute/virtualMachines"
				foreach($vmResource in $taggedClassicVMs)
				{
				    Write-Output "RG : $vmResource.ResourceGroupName , Classic VM $($vmResource.Name)"
					$AzureVMList += @{Name = $vmResource.Name; ResourceGroupName = $vmResource.ResourceGroupName; Type = "Classic"}
				}
				
				# Get resource manager VM resources in group and record target state for each in table
				$taggedRMVMs = Find-AzureRMResource -ResourceGroupNameEquals $ResourceGroup.ResourceGroupName -ResourceType "Microsoft.Compute/virtualMachines"
				foreach($vmResource in $taggedRMVMs)
				{
					Write-Output "RG : $vmResource.ResourceGroupName , ARM VM $($vmResource.Name)"
					$AzureVMList += @{Name = $vmResource.Name; ResourceGroupName = $vmResource.ResourceGroupName; Type = "ResourceManager"}
				}
			}
        }        
        
        $ActualAzureVMList=@()
        if($VMfilterList -ne $null)
        {
            foreach($VM in $AzureVMList)
            {  
                ##Checking Vm in excluded list                         
                if($VMfilterList -notcontains ($($VM.Name)))
                {
                    $ActualAzureVMList+=$VM
                }
            }
        }
        else
        {
            $ActualAzureVMList = $AzureVMList
        }

        if($WhatIf -eq $false)
        {    
            foreach($VM in $ActualAzureVMList)
            {  
                    Write-Output "Creating alert rules for the VM : $($VM.Name)"
                    $params = @{"VMObject"=$VM;"AlertAction"="Create";"WebhookUri"=$webhookUri}                    
                    $runbook = Start-AzureRmAutomationRunbook -automationAccountName $automationAccountName -Name 'AutoStop_CreateAlert_Child' -ResourceGroupName $aroResourceGroupName –Parameters $params
            }
            Write-Output "Note: All the alert rules creation are processed in parallel. Please check the child runbook (AutoStop_CreateAlert_Child) job status..."
        }
        elseif($WhatIf -eq $true)
        {
            Write-Output "WhatIf parameter is set to True..."
            Write-Output "When 'WhatIf' is set to TRUE, runbook provides a list of Azure Resources (e.g. VMs), that will be impacted if you choose to deploy this runbook."
            Write-Output "No action will be taken at this time..."
            Write-Output $($ActualAzureVMList) 
        }
        Write-Output "Runbook Execution Completed..."
    }
    catch
    {
        $ex = $_.Exception
        Write-Output $_.Exception
    }
