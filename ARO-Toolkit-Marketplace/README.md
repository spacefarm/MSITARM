# **Start/Stop VMs during off-hours solution in Azure Automation**
Deploy an Azure Automation account with preconfigured runbooks, schedules, and Log Analytics to your subscription and start saving money.  Optional deployment of SendGrid for email notifications.  Azure resource optimization happens automatically on your subscription including on new resources!  

***Objective:*** Provide decentralized automation capabilities for customers who want to reduce their costs.  Features include: 
1.  Schedule VMs to stop/start  
2.  Schedule VMs to stop/start in ascending and descending order using Azure Tags
3.  Auto stop VMs based on low CPU
4.  Bulk delete resource groups on demand

***Prerequisites:*** 
* The runbooks work with an Azure Run As account. The Run As account is the preferred authentication method since it uses certificate authentication instead of a password that may expire or change frequently. 
* This solution can only manage VMs that are in the same subscription as where the Automation account resides. 
* This solution only deploys to the following Azure regions - Australia Southeast, East US, Southeast Asia, and West Europe. * The runbooks that manage the VM schedule can target VMs in any region. 
* To send email notifications when the start and stop VM runbooks complete, you must select select "Yes" to deploy SendGrid for email notifications during deployment from Azure Marketplace.

# **All about each Default Schedule**
This is a list of each of the Default Schedules which will be deployed with Azure Automation.   It is not recommended that you modify the Default Schedules.  If a different schedule is required,  you should create a custom schedule.  By default each of these schedules are disabled, and is up to you to enable per your requirements.

It is not recommended to enable ALL schedules as there would an overlap on which schedule performs an action, rather it would be best to determine which optimizations you wish to perform and choose accordingly. 

**ScheduleName** | **Time and Frequency** | **What it does**
--- | --- | ---
Schedule_AutoStop_CreateAlert_Parent | Time of Deployment, Every 8 Hours | Runs the AutoStop_CreateAlert_Parent runbook every 8 hours, which in turn will stop VM’s based on rules defined in the External_AutoStop* Asset Variables. 
Scheduled_StopVM | User Defined, Every Day | Runs the Scheduled_Parent runbook with a parameter of “Stop” every day at the given time.  Will Automatically stop all VM’s that meet the rules defined via Asset Variables.  Recommend enabling the sister schedule, Scheduled-StartVM.  
 Scheduled_StartVM | User Defined, Every Day | Runs the Scheduled_Parent runbook with a parameter of “Start” every day at the given time.  Will Automatically start all VM’s that meet the rules defined via Asset Variables.  Recommend enabling the sister schedule, Scheduled-StopVM.
 Sequenced-StopVM | 1:00AM (UTC), Every Friday | Runs the Sequenced_Parent runbook with a parameter of “Stop” every Friday at the given time.  Will sequentially (ascending) stop all VM’s with a tag of “Sequence” defined.  Refer to Runbooks section for more details on tag values.  Recommend enabling the sister schedule, Sequenced-StartVM.
 Sequenced-StartVM | 1:00PM (UTC), Every Monday | Runs the Sequenced_Parent runbook with a parameter of “Start” Every Monday at the given time.  Will  sequentially (descending) start all VM’s with a tag of “Sequence” defined.  Refer to Runbooks section for more details on tag values.  Recommend enabling the sister schedule, Sequenced-StopVM.


# **All about each Runbook**

This is a list of runbooks that will be deployed with Azure Automation.  It is not recommended that you make changes to the runbook code, but rather write your own runbook for new functionality.

***Pro Tip:*** Don’t directly run any runbook with the name “Child” appended to the end.

  **Runbook Name** | **Parameters** | **What it does**
  --- | --- | ---
  AutoStop\_CreateAlert\_Child | VMObject <br> AlertAction <br> WebHookURI | Called from the parent runbook only. Creates alerts on per resource basis for AutoStop scenario.
  AutoStop\_CreateAlert\_Parent | WhatIf: True or False. | Creates or updates azure alert rules on VMs in the targeted subscription or resource groups. <br> WhatIf: True -> Runbook output will tell you which resources will be targeted. <br> WhatIf: False -> Create or update the alert rules.
  AutoStop\_Disable | none | Disable AutoStop alerts and default schedule.
  AutoStop\_StopVM\_Child | WebHookData | Called from parent runbook only. Alert rules call this runbook and it does the work of stopping the VM.
  Bootstrap\_Main | none | Used one time to set-up bootstrap configurations such as Run As account and webhookURI which is typically not accessible from ARM. This runbook will be removed automatically if deployment has gone successfully.
  DeleteResourceGroup\_Child | RGName | Called from the parent runbook only. Deletes a single resource group.
  DeleteResourceGroups\_Parent | RGNames: Comma separated list of resource groups.  WhatIf: True or False |Deletes resource groups in bulk. Typically an ad hoc subscription clean-up method. <br> WhatIf: True -> Shows which resource groups will be targeted. <br> WhatIf: False -> Deletes those targete resource groups.  
  DisableAllOptimizations | None | Turns off all alert rules and default schedules. Use this when you want to ensure all resources are available for an event like quarter close or Black Friday.
  ScheduledStartStop\_Child | VMName: <br> Action: Stop or Start <br> ResourceGroupName: | Called from parent runbook only. Does the actual execution of stop or start for scheduled Stop.
  ScheduledStartStop\_Parent | Action: Stop or Start <br> WhatIF: True or False | This will take effect on all VMs in the subscription unless you edit the “External\_ResourceGroupNames” which will restrict it to only execute on these target resource groups. You can also exclude specific VMs by updating the “External\_ExcludeVMNames” variable. WhatIf behaves the same as in other runbooks.
  SequencedStartStop\_Parent | Action: Stop or Start <br> WhatIf:  True or False | Create a tag called “Sequence” on each VM that you want to sequence stop\\unsnooze activity for. The value of the tag should be an integer (1,2,3) that corresponds to the order you want to snooze\\unsnooze. For snoozing VMs, the order goes ascending (1,2,3) and for unsnoozing it goes descending (3,2,1). WhatIf behaves the same as in other runbooks. <br> **Note: This will work exclusively off tag values and will run subscription wide.**

# **All about each Variable**

This is a list of variables that will be deployed with Azure Automation.  

***Pro Tip:*** Only change variables prefixed with "External".  Do not change variables prefixed with "Internal"

  **Variable Name** | **Description** 
  --- | --- 
  External\_AutoStop\_Condition | This is the conditional operator required for configuring the condition before triggering an alert. Possible values are [GreaterThan, GreaterThanOrEqual, LessThan, LessThanOrEqual].
  External\_AutoStop\_Description | Alert to stop the VM if the CPU % exceed the threshold.
  External\_AutoStop\_MetricName | Name of the metric the Azure Alert rule is to be configured for.
  External\_AutoStop\_Threshold | Threshold for the Azure Alert rule. Possible percentage values ranging from 1 to 100.
  External\_AutoStop\_TimeAggregationOperator | The time aggregation operator which will be applied to the selected window size to evaluate the condition. Possible values are [Average, Minimum, Maximum, Total, Last].
  External\_AutoStop\_TimeWindow | The window size over which Azure will analyze selected metric for triggering an alert. This parameter accepts input in timespan format. Possible values are from 5 mins to 6 hours.
  External\_EmailSubject | Email subject text (title).
  External\_EmailToAddress | Enter the recipient of the email.  Seperate names by using comma(,).
  External\_ExcludeVMNames | Excluded VMs as comma separated list: vm1,vm2,vm3
  External\_IsSendEmail | Boolean option to send email (True) or not send email (False).This option should be 'False' if you did not create SendGrid during the initial deployment.
  External\_ResourceGroupNames | Resource groups (as comma separated) targeted for Snooze actions: rg1,rg2,rg3
  Internal\_AutomationAccountName | Azure Automation Account Name.
  Internal\_AutoSnooze_WebhookUri | Webhook URI called for the AutoStop scenario.
  Internal\_AzureSubscriptionId | Azure Subscription Id.
  Internal\_ResourceGroupName | Azure Automation Account resource group name.
  Internal\_SendGridAccountName | SendGrid Account Name.
  Internal\_SendGridPassword | SendGrid Password.

  