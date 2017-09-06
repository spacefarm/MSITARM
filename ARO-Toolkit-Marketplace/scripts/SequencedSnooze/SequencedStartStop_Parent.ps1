<#
.SYNOPSIS  
	This runbook used to perform sequenced start or stop Azure RM/Classic VM
.DESCRIPTION  
	This runbook used to perform sequenced start or stop Azure RM/Classic VM.
	Create a tag called “Sequence” on each VM that you want to sequence start\stop activity for. The value of the tag should be an integer (1,2,3) that corresponds to the order you want to start\stop. For stopping VMs, the order goes ascending (1,2,3) and for starting it goes descending (3,2,1). WhatIf behaves the same as in other runbooks. 
	Upon completion of the runbook, an option to email results of the started VM can be sent via SendGrid account. 
	
	This runbook requires the Azure Automation Run-As (Service Principle) account, which must be added when creating the Azure Automation account.
 .PARAMETER  
    Parameters are read in from Azure Automation variables.  
    Variables (editable):
    -  External_ResourceGroupNames:  ResourceGroup that contains VMs to be started/stopped. Must be in the same subscription that the Azure Automation Run-As account has permission to manage.
    -  External_ExcludeVMNames         :  VM names to be excluded from being started.
    -  External_IsSendEmail            :  Boolean option to send email (True) or not send email (False)
    -  External_EmailSubject           :  Email subject (title) 
    -  External_EmailToAddress         :  List of recipients of the email.  Seperate by semi-colon ';'
.EXAMPLE  
	.\SequencedStartStop_Parent.ps1 -Action "Value1" 

#>

Param(
[Parameter(Mandatory=$true,HelpMessage="Enter the value for Action. Values can be either stop or start")][String]$Action,
[Parameter(Mandatory=$false,HelpMessage="Enter the value for WhatIf. Values can be either true or false")][bool]$WhatIf = $false,
[Parameter(Mandatory=$false,HelpMessage="Enter the value for ContinueOnError. Values can be either true or false")][bool]$ContinueOnError = $false
)
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
		
		$Body += "<br><br><table border=1><tr><td><b>VM Name</b></td><td><b>Resource Group Name</b></td></tr>"

        foreach($vm in $VMList)
        {
            $Body +="<tr><td>$($vm.Name)</td><td>$($vm.ResourceGroupName)</td></tr>"
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

function CheckVMState ($VMObject,[string]$Action)
{
    [bool]$IsValid = $false
    
    $CheckVMState = (Get-AzureRmVM -ResourceGroupName $VMObject.ResourceGroupName -Name $VMObject.Name -Status -ErrorAction SilentlyContinue).Statuses.Code[1]
    if($Action.ToLower() -eq 'start' -and $CheckVMState -eq 'PowerState/running')
    {
        $IsValid = $true
    }    
    elseif($Action.ToLower() -eq 'stop' -and $CheckVMState -eq 'PowerState/deallocated')
    {
            $IsValid = $true
    }    
    return $IsValid
}

#---------Read all the input variables---------------
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
     
    Write-Output "Executing the Sequenced $($Action)..."   
    Write-Output "Input parameter values..."
    Write-Output "`$Action : $($Action)"
    Write-Output "`$WhatIf : $($WhatIf)"
    Write-Output "`$ContinueOnError : $($ContinueOnError)"
    Write-Output "Filtering the tags across all the VM's..."
    
    $tagValue = "sequence"    
    $TagKeys = Get-AzureRmVM | Where-Object {$_.Tags.Keys -eq $tagValue.ToLower()} | Select Tags
    $Sequences=[System.Collections.ArrayList]@()
    foreach($tag in $TagKeys.Tags)
    {
        if($tag.ContainsKey($tagValue))
        {
            [void]$Sequences.add([int]$tag.sequence)
        }
    }

    $Sequences = $Sequences | Sort-Object -Unique
    if($Action.ToLower() -eq 'start')
    {
        $Sequences = $Sequences | Sort -Descending
    }

    $EmailVMList=@()
    foreach($seq in $Sequences)
    {
        if($WhatIf -eq $false)
        {
            Write-Output "Performing the $($Action) for the sequence-$($seq) VM's..."
            $AzureVMList=Find-AzureRmResource -TagName $tagValue.ToLower() -TagValue $seq | Where-Object {$_.ResourceType -eq “Microsoft.Compute/virtualMachines”} | Select Name, ResourceGroupName
        
            foreach($vmObj in $AzureVMList)
            {                
                Write-Output "Performing the $($Action) action on VM: $($vmobj.Name)"
                $params = @{"VMName"="$($vmObj.Name)";"Action"=$Action;"ResourceGroupName"="$($vmObj.ResourceGroupName)"}                    
                Start-AzureRmAutomationRunbook -automationAccountName $automationAccountName -Name 'ScheduledStartStop_Child' -ResourceGroupName $aroResourceGroupName –Parameters $params   
                $EmailVMList += $vmObj          
            }

            Write-Output "Completed the sequenced $($Action) for the sequence-$($seq) VM's..." 

            if(($Action -eq 'stop' -and $seq -ne $Sequences.Count) -or ($Action -eq 'start' -and $seq -ne [int]$Sequences.Count - ([int]$Sequences.Count-1)))
            {
                Write-Output "Validating the status before processing the next sequence..."
            }        

            foreach($vmObjStatus in $AzureVMList)
            {
                [int]$SleepCount = 0 
                $CheckVMStatus = CheckVMState -VMObject $vmObjStatus -Action $Action
                While($CheckVMStatus -eq $false)
                {                
                    Write-Output "Checking the VM Status in 10 seconds..."
                    Start-Sleep -Seconds 10
                    $SleepCount+=10
                    if($SleepCount -gt 600 -and $ContinueOnError -eq $false)
                    {
                        Write-Output "Unable to $($Action) the VM $($vmObjStatus.Name). ContinueOnError is set to False, hence terminating the sequenced $($Action)..."
                        Write-Output "Completed the sequenced $($Action)..."
                        exit
                    }
                    elseif($SleepCount -gt 600 -and $ContinueOnError -eq $true)
                    {
                        Write-Output "Unable to $($Action) the VM $($vmObjStatus.Name). ContinueOnError is set to True, hence moving to the next resource..."
                        break
                    }
                    $CheckVMStatus = CheckVMState -VMObject $vmObjStatus -Action $Action
                }
            }
        }
        elseif($WhatIf -eq $true)
        {
            Write-Output "WhatIf parameter is set to True..."
            Write-Output "When 'WhatIf' is set to TRUE, runbook provides a list of Azure Resources (e.g. VMs), that will be impacted if you choose to deploy this runbook."
            Write-Output "No action will be taken at this time..."
            $AzureVMList=Find-AzureRmResource -TagName $tagValue.ToLower() -TagValue $seq | Where-Object {$_.ResourceType -eq “Microsoft.Compute/virtualMachines”} | Select-Object Name, ResourceGroupName            
            Write-Output $($AzureVMList)
        }
    }

    if($EmailVMList -ne $null -and $isSendMail -eq $true)
    {
        sendEmail -VMList $EmailVMList -Action $Action
    }
    Write-Output "Completed the sequenced $($Action)..."
}
catch
{
    Write-Output "Error Occurred in the sequence $($Action) runbook..."   
    Write-Output $_.Exception
}