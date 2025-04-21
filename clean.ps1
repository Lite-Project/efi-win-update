@"
select disk $($(Get-Partition -DriveLetter C).DiskNumber)
select partition $($(Get-Partition | Where-Object {$_.Type -eq "System"}).PartitionNumber[0])
delete partition override
"@ | Out-File -FilePath "C:\remove_old_efi.txt" -Encoding ASCII

#Removes Old EFI Partition
diskpart /s C:\remove_old_efi.txt

#Creates WinRE .xml Backup
Rename-Item -Path "C:\Windows\System32\Recovery\ReAgent.xml" -NewName ReAgent.xml.old

#Forces creation of new WinRE .xml
reagentc /enable

#Disables auto ReAgent for security as well as reseting to default
reagentc /disable

#Verifies ReAgent file generation
try {
    Get-Item -Path "C:\Windows\System32\Recovery\ReAgent.xml"
    #If .xml is confirmed, enables bitlocker
    manage-bde.exe -protectors -enable C:
    #Remove remaining .txt remanents
    Remove-Item "C:\remove_old_efi.txt"
} catch {
    Write-Warning "ReAgent.xml failed to be created"
}