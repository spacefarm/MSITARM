#301-multi-vm-domain-join-ConfigurableDisks-sqlprem

Deploy from Azure Portal (UI Experience)

Steps:

	1.  Create your storage acount that you want to deploy to. 
	 
		New-AzureRmStorageAccount -ResourceGroupName "yourRG" -AccountName "yourStorageAccountName" -Location "centralus" -Type "Standard_GRS" -Tags @{Name = "AppID"; Value = "enteryourValue"}, @{Name="OrgID";Value="enteryourValue"},@{Name="Env";Value="enteryourValue"}
		
		Create a blob container called "vhds".  You can do this through the Azure Portal. 

	2.  Logon to http://portal.azure.com
	3.  New and search for "Template Deployment"
	4.  Copy and paste the contents of azuredeploy.json into "Edit Template"
	
		Edit the template: you will need to populate the Domain data for the VM to join. 
		YourDomain should be replaced with the short name of your Domain. 
		the FQDN and OU path need to be updated to match your Domain. 
		You may add more Domains in an allowed list that will map to the domainData variable and used by the template.
	
	5.  Update all Parameters
	6.  Follow the rest of the UI
