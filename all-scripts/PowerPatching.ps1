# Name: PowerPatching
#
# Install: PowerPatching.ps1
#
# example:
# install: c:\PowerPatch\PowerPatching.ps1
#
# Run at startup, delay 30 seconds
# Run: powershell.exe
# Args: -NoLogo -NonInteractive -ExecutionPolicy ByPass -Command "c:\\PowerPatch\\PowerPatching.ps1"
# Run as: SYSTEM



# Avoid the non-terminating error so that DSC does not report a failure
if ((Get-ScheduledTask -TaskPath '\' -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -eq 'E2SPowerPatching'; }) -eq $null)
{
    $TaskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $('-NoLogo -NonInteractive -ExecutionPolicy ByPass -Command "c:\\PowerPatch\\PowerPatching.ps1 "');
    
        $TaskTrigger = New-ScheduledTaskTrigger -Once -at $($([DateTime] $(get-date).ToUniversalTime()).addHours(8)) -RepetitionDuration  (New-TimeSpan -hours 12) -RepetitionInterval  (New-TimeSpan -hour 4)

    $TaskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Limited ;
    $TaskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -ExecutionTimeLimit (New-TimeSpan -Hours 1);

    $ScheduledTask = Register-ScheduledTask -TaskName E2SPowerPatching -TaskPath '\' -Action $TaskAction -Trigger $TaskTrigger -Settings $TaskSettings -Principal $TaskPrincipal
} else {

    $patch = $(c:\PowerPatch\supdate_v4.0.exe -preview)
    write-host $patch

    if($($patch | ?{$_ -Contains 'No Updates Found!'}) -ne "No Updates Found!" ) {

        #patch server
        c:\PowerPatch\supdate_v4.0.exe -Install

    } elseif($($patch | ?{$_ -Contains 'No Updates Found!'}) -eq "No Updates Found!" ) { 

       #remove scheduled task
       Unregister-ScheduledTask -TaskName E2SPowerPatching -Confirm:$false

    }

}
  

