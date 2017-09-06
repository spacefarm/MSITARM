<#
.SYNOPSIS  
	 Wrapper script for get all the VM's in all RG's or subscription level and then call the Start or Stop runbook
.DESCRIPTION  
	 This runbook is intended to start/stop VMs (both classic and ARM based VMs) that resides in a given list of Azure resource group(s).If the resource group list is empty, then the script gets all the VMs in the current subscription.
	 Upon completion of the runbook, an option to email results of the started VM can be sent via SendGrid account. 
		
	 This runbook requires the Azure Automation Run-As (Service Principle) account, which must be added when creating the Azure Automation account.
.EXAMPLE  
	.\ScheduledStartStop_Parent.ps1 -Action "Value1" -WhatIf "False"

.PARAMETER  
    Parameters are read in from Azure Automation variables.  
    Variables (editable):
    -  External_ResourceGroupNames:  ResourceGroup that contains VMs to be started/stopped. Must be in the same subscription that the Azure Automation Run-As account has permission to manage.
    -  External_ExcludeVMNames         :  VM names to be excluded from being started.
    -  External_IsSendEmail            :  Boolean option to send email (True) or not send email (False)
    -  External_EmailSubject           :  Email subject (title) 
    -  External_EmailToAddress         :  List of recipients of the email.  Seperate by semi-colon ';'
   
#>

Param(
[Parameter(Mandatory=$true,HelpMessage="Enter the value for Action. Values can be either stop or start")][String]$Action,
[Parameter(Mandatory=$false,HelpMessage="Enter the value for WhatIf. Values can be either true or false")][bool]$WhatIf = $false
)

function ScheduleSnoozeAction ($VMObject,[string]$Action)
{
    
    Write-Output "Calling the ScheduledStartStop_Child wrapper (Action = $($Action))..."
	
    if($Action.ToLower() -eq 'start')
    {
        $params = @{"VMName"="$($VMObject.Name)";"Action"="start";"ResourceGroupName"="$($VMObject.ResourceGroupName)"}   
    }    
    elseif($Action.ToLower() -eq 'stop')
    {
        $params = @{"VMName"="$($VMObject.Name)";"Action"="stop";"ResourceGroupName"="$($VMObject.ResourceGroupName)"}                    
    }    
   
   	if ($VMObject.Type -eq "Classic")
	{
		Write-Output "Performing the schedule $($Action) for the VM : $($VMObject.Name) using Classic"
		$currentVM = Get-AzureVM | where Name -Like $VMObject.Name
		if ($currentVM.Count -ge 1)
		{
			$runbookName = 'ScheduledStartStop_Child_Classic'
		}
		else
		{
			Write-Error "Error: No VM instance with name $($VMObject.Name) found"
		}
	
	}
	elseif ($VMObject.Type -eq "ResourceManager")
	{
		Write-Output "Performing the schedule $($Action) for the VM : $($VMObject.Name) using AzureRM"
		$runbookName = 'ScheduledStartStop_Child'
	}
	
	 $runbook = Start-AzureRmAutomationRunbook -automationAccountName $automationAccountName -Name $runbookName -ResourceGroupName $aroResourceGroupName –Parameters $params
   
}

function sendEmail($VMList,[string]$Action)
{
    Write-Output "Sending email with details on VM action"
    $sendGridUsername = $sendGridResource.Properties.username
    $sendGridPassword = Get-AutomationVariable -Name 'Internal_SendGridPassword'
    $sendGridEmailTo = Get-AutomationVariable -Name 'External_EmailToAddress'
    $sendGridEmailSubject = Get-AutomationVariable -Name 'External_EmailSubject'
    $sendGridAccountName = Get-AutomationVariable -Name 'Internal_SendGridAccountName'
    try
    {
        $sendGridResource = Find-AzureRmResource -ResourceType "Sendgrid.Email/accounts" -ResourceNameContains $sendGridAccountName -ExpandProperties
        $sendGridUsername = $sendGridResource.Properties.username
        $SMTPServer = $sendGridResource.Properties.smtpServer

        $securedPassword=$sendGridPassword|ConvertTo-SecureString -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential $sendGridUsername, $securedPassword

        $EmailFrom = "No-reply@azureadmin.com"
		[string[]]$EmailToList = $sendGridEmailTo -split ","

        $Body = "The following VMs are attempting to do the operation: $($Action)."
		
		$Body += "<br><br><table border=1><tr><td><b>VM Name</b></td><td><b>Resource Group Name</b></td><td><b>Azure Type</b></td></tr>"

        foreach($vm in $VMList)
        {
            $Body += "<tr><td>$($vm.Name)</td><td>$($vm.ResourceGroupName)</td><td>$($vm.Type)</td></tr>"
        }

		$Body += "</table>"
		 
        Send-MailMessage -smtpServer $SMTPServer -Credential $credential -Usessl -Port 587 -from $EmailFrom -to $EmailToList -subject $sendGridEmailSubject -Body $Body -BodyAsHtml
        Write-Output "Email sent succesfully." 
    }
    catch
    {
        $ex = $_.Exception
        Write-Output $_.Exception
    }

}

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
        Write-Output "Exclude VM's validation completed..."
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

#----- Initialize the Azure subscription we will be working against for Classic Azure resources-----
Write-Output "Authenticating Classic RunAs account"
$ConnectionAssetName = "AzureClassicRunAsConnection"
$connection = Get-AutomationConnection -Name $connectionAssetName        
Write-Output "Get connection asset: $ConnectionAssetName" -Verbose
$Conn = Get-AutomationConnection -Name $ConnectionAssetName
if ($Conn -eq $null)
{
    throw "Could not retrieve connection asset: $ConnectionAssetName. Assure that this asset exists in the Automation account."
}
$CertificateAssetName = $Conn.CertificateAssetName
 Write-Output "Getting the certificate: $CertificateAssetName" -Verbose
$AzureCert = Get-AutomationCertificate -Name $CertificateAssetName
if ($AzureCert -eq $null)
{
    throw "Could not retrieve certificate asset: $CertificateAssetName. Assure that this asset exists in the Automation account."
}
 Write-Output "Authenticating to Azure with certificate." -Verbose
Set-AzureSubscription -SubscriptionName $Conn.SubscriptionName -SubscriptionId $Conn.SubscriptionID -Certificate $AzureCert 
Select-AzureSubscription -SubscriptionId $Conn.SubscriptionID


#---------Read all the input variables---------------
$SubId = Get-AutomationVariable -Name 'Internal_AzureSubscriptionId'
$ResourceGroupNames = Get-AutomationVariable -Name 'External_ResourceGroupNames'
$ExcludeVMNames = Get-AutomationVariable -Name 'External_ExcludeVMNames'
$automationAccountName = Get-AutomationVariable -Name 'Internal_AutomationAccountName'
$aroResourceGroupName = Get-AutomationVariable -Name 'Internal_ResourceGroupName'
$isSendMail = Get-AutomationVariable -Name 'External_IsSendEmail'

try
    {  
        $Action = $Action.Trim().ToLower()

        if(!($Action -eq "start" -or $Action -eq "stop"))
        {
            Write-Output "`$Action parameter value is : $($Action). Value should be either start or stop!"
            Write-Output "Completed the runbook execution..."
            exit
        }            
        Write-Output "Runbook Execution Started..."
        [string[]] $VMfilterList = $ExcludeVMNames -split ","
        [string[]] $VMRGList = $ResourceGroupNames -split ","

        #Validate the Exclude List VM's and stop the execution if the list contains any invalid VM
        if (([string]::IsNullOrEmpty($ExcludeVMNames) -ne $true) -and ($ExcludeVMNames -ne "none"))
        {
            Write-Output "Exclude VM's added so validating the resource(s)..."
            CheckExcludeVM -FilterVMList $VMfilterList
        } 
        $AzureVMListTemp = $null
        $AzureVMList=@()
        ##Getting VM Details based on RG List or Subscription
        if (($VMRGList -ne $null) -and ($VMRGList -ne "*"))
        {
            foreach($Resource in $VMRGList)
            {
				Write-Output "Validating the resource group name ($($Resource.Trim()))" 
                $checkRGname = Get-AzureRmResourceGroup -Name $Resource.Trim() -ev notPresent -ea 0  
                if ($checkRGname -eq $null)
                {
                    Write-Warning "$($Resource) is not a valid Resource Group Name. Please Verify!"
                }
                else
                {    
					# Get classic VM resources in group and record target state for each in table
					$taggedClassicVMs = Find-AzureRMResource -ResourceGroupName $Resource -ResourceType "Microsoft.ClassicCompute/virtualMachines"
					foreach($vmResource in $taggedClassicVMs)
					{
						if ($vmResource.ResourceGroupName -Like $Resource)
						{
							$AzureVMList += @{Name = $vmResource.Name; ResourceGroupName = $vmResource.ResourceGroupName; Type = "Classic"}
						}
					}
					
					# Get resource manager VM resources in group and record target state for each in table
					$taggedRMVMs = Find-AzureRMResource -ResourceGroupName $Resource -ResourceType "Microsoft.Compute/virtualMachines"
					foreach($vmResource in $taggedRMVMs)
					{
						if ($vmResource.ResourceGroupName -Like $Resource)
						{
							$AzureVMList += @{Name = $vmResource.Name; ResourceGroupName = $vmResource.ResourceGroupName; Type = "ResourceManager"}
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
				# Get classic VM resources in group and record target state for each in table
				$taggedClassicVMs = Find-AzureRMResource -ResourceGroupName $ResourceGroup.ResourceGroupName -ResourceType "Microsoft.ClassicCompute/virtualMachines"
				foreach($vmResource in $taggedClassicVMs)
				{
				    Write-Output "RG : $vmResource.ResourceGroupName , Classic VM $($vmResource.Name)"
					$AzureVMList += @{Name = $vmResource.Name; ResourceGroupName = $vmResource.ResourceGroupName; Type = "Classic"}
				}
				
				# Get resource manager VM resources in group and record target state for each in table
				$taggedRMVMs = Find-AzureRMResource -ResourceGroupName $ResourceGroup.ResourceGroupName -ResourceType "Microsoft.Compute/virtualMachines"
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

        Write-Output "The current action is $($Action)"
        
        if($WhatIf -eq $false)
        {    
                
            foreach($VM in $ActualAzureVMList)
            {  
                ScheduleSnoozeAction -VMObject $VM -Action $Action
            }
            
            if ($isSendMail -eq $true)
            {
                sendEmail -VMList $ActualAzureVMList -Action $Action
            }
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
