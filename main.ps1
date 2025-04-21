#=====---v---=====#=====---v---=====#=-Default  Param-=#=====---v---=====#=====---v---=====#=====---v---=====#
Import-Module Storage

$o1 = 'X'
$o2 = 'X'
$o3 = 'X' # Needs to stay X on default for error checking

$sfcE = "Windows Resource Protection found corrupt files but was unable"
$dismE = "Error"

#list of available drive letters
$ad = [char[]]('A'[0]..'Z'[0]) | Where-Object { $_ -notin (Get-PSDrive -PSProvider FileSystem).Name }
#New EFI Partition size for L3
$esize = 512MB

#=====---^---=====#=====---^---=====#=====---^---=====#=====---^---=====#=====---^---=====#=====---^---=====#

function main {
    Clear-Host
    Write-Host @"


1.  [$o1] DISM and SFC
2.  [$o2] Clear Fonts in EFI partition
3.  [$o3] Recreate EFI Partition
"@
    $ipt = Read-Host "Please select which option you'd like to run"
    if ($ipt -eq '1') {
        if ($o1 -eq 'X') {$o1 = '✓'} else {$o1 = 'X'}
    } elseif ($ipt -eq '2') {
        if ($o2 -eq 'X') {$o2 = '✓'} else {$o2 = 'X'}
    } elseif ($ipt -eq '3') {
        if ($ad.Count -lt 2) {
            Write-Warning "There are insufficient available drive letters to select this operation."
            Read-Host " "
        } elseif ($o3 -eq 'X') {$o3 = '✓'} else {$o3 = 'X'}
    }
    if (($ipt -eq '') -and (($o1 -eq '✓') -or ($o2 -eq '✓') -or ($o3 -eq '✓'))) {
        if ($o1 -eq '✓') {
            l1
        }
        if ($o2 -eq '✓') {
            l2
            if ($o3 -eq '✓') {l2 -L3 $true}
        }
        if (($o3 -eq '✓') -and ($o2 -eq 'X')) {
            l3
        }
    } else {main}
}

function l1 {
    $sout = ''
    $dout = ''

    Write-Host "Running SFC now."
    & cmd.exe /c "sfc /scannow" 2>&1 | ForEach-Object {
        Clear-Host
        $line = $_.Replace("`0","")
        Write-Host "SFC: $line"  # Display live updates in the terminal
        $sout += $line  # Append each line to the output array
    }
    if ($sout -match $sfcE) {
        Write-Output $sout
        Read-Host "The process will now exit. Please resolve the issue before retrying."
        exit
    }
    & cmd.exe /c "dism /online /cleanup-image /restorehealth" 2>&1 | ForEach-Object {
        Clear-Host
        Write-Host "DISM: $_"  # Display live updates in the terminal
        $dout += $_  # Append each line to the output array
    }
    if ($dout -match $dismE) {
        Write-Output $dout
        Read-Host "The process will now exit. Please resolve the issue before retrying."
        exit
    }

    Write-Host "DISM ran successfully."
}

function l2 {
    param([bool]$L3 = $false)
    #Mounts System Reserved Partition
    Get-Partition `
        | Where-Object GptType -eq "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" `
        | Set-Partition -NewDriveLetter $ad[0]

    if ($(Get-PSDrive -Name $ad[0]).Free -le 15MB) {
        #Clears Font folder to make enough space for the windows update
        Remove-Item -Path "$($ad[0]):\EFI\Microsoft\Boot\Fonts\*" -Recurse -Force
        if ($(Get-PSDrive -Name $ad[0]).Free -ge 15MB) {
            #Unmounts System Reserved Partition
            Write-Host -ForegroundColor Green "New System Reserved Partition Size $($(Get-PSDrive -Name $ad[0]).Free / 1MB) MB"
        } else {
            Write-Warning "Unable to clear enough enough space. (Required Free Space 15MB, Reserved Partition: $($(Get-PSDrive -Name $ad[0]).Free / 1MB) MB)"
        }
    } else {
        Write-Warning "System Reserved Partition more than 15MB already."
    }

    if ($L3) {
        while ($true) {
            $ipt = Read-Host "Type 'yes' to continue to resize the partition"
            if ($ipt -match 'y') {
                L3 -L3 $true
            } elseif ($ipt -match 'n') {exit}
            Clear-Host
        }
    } else {Get-Partition -DriveLetter $ad[0] | Remove-PartitionAccessPath -AccessPath "$($ad[0]):\"}
}

function l3 {
    param([bool]$L3 = $false)
    $w1 = @"
#===---~---===#===---~---===#USE AT YOUR OWN RISK#===---~---===#===---~---===#
It appears that the less invasive cleanup has not been executed.
Please re-run the script and select options 2 and 3 to perform the less invasive cleanup prior to proceeding.


"@
    if ($($(Get-PSDrive -Name C).Free / 1MB) -ge $($($esize + 5MB) / 1MB)){
        while ($true) {
            if (!$L3) {
                Write-Warning $w1
            }
            Write-Warning @"
#===---~---===#===---~---===#USE AT YOUR OWN RISK#===---~---===#===---~---===#
PLEASE REMEMBER THIS IS STILL EXPERIMENTAL. 
"@
            $ipt = Read-Host "Type 'yes' if you wish to continue"
            if ($ipt -match 'y') {
                l3f1 #Function for step 1
            } elseif ($ipt -match 'n') {exit}
            Clear-Host
        }
    } else {
        Write-Warning "Warning you do not have enough space to recreate the EFI partition."
        Read-Host " "
        exit
    }
}

function l3f1 {
    Import-Module Storage
#Generates .txt file for new efi partition.
@"
select disk $($(Get-Partition -DriveLetter C).DiskNumber)
create partition efi size=$($esize / 1MB)
format fs=fat32 quick
assign letter=$($ad[1])
"@ | Out-File -FilePath "C:\create_efi.txt" -Encoding ASCII
#Generates .txt file for removing old efi partition.
@"
select disk $($(Get-Partition -DriveLetter C).DiskNumber)
select partition $($(Get-Partition | Where-Object {$_.Type -eq "System"}).PartitionNumber[0])
delete partition override
"@ | Out-File -FilePath "C:\remove_old_efi.txt" -Encoding ASCII

    irm 
    #Suspends Bitlocker
    manage-bde.exe -protectors -disable C:
    if (!(Get-PSDrive -Name $ad[0] -ErrorAction SilentlyContinue)) {
        #Mounts Original EFI Partiton to $ad[0]
        Get-Partition `
            | Where-Object GptType -eq "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" `
            | Set-Partition -NewDriveLetter $ad[0] | Out-Null
    }
    # Shrink the C: drive by $esize
    Resize-Partition -DiskNumber 0 -PartitionNumber $(Get-Partition -DriveLetter C).PartitionNumber -Size ($(Get-Partition -DriveLetter C).Size - $esize)
    #Creates new specialized EFI partition
    diskpart /s C:\create_efi.txt
    try {
        #Checks if Z Partition has been made successfully
        Get-Partition -DriveLetter $ad[1] | Out-Null
        #Clones old EFI System Partition to New Partition
        robocopy $ad[0]:\ $ad[1]:\ /MIR /COPYALL /XJ
        cmd.exe /c "bcdboot C:\Windows /s $($ad[1]):"
        cmd.exe /c "bcdboot C:\Windows /s $($ad[1]): /f UEFI"
        #Changes Boot path from C to be updated to newly created Z drive.
        cmd.exe /c "bcdedit /set {bootmgr} device partition=$($ad[1]):"
        cmd.exe /c "bcdedit /set {current} device partition=C:"
        cmd.exe /c "bcdedit /set {current} osdevice partition=C:"
        #Unbinds Y path to prevent ghost volumes
        Get-Partition -DriveLetter $ad[0] | Remove-PartitionAccessPath -AccessPath "$($ad[0]):\"
        #Deletes efi .txt file
        Remove-Item "C:\create_efi.txt"
        #Forces a restart
        shutdown /r /t 10
    } catch {
        Remove-Item "C:\create_efi.txt"
        Remove-Item "C:\remove_old_efi.txt"
        Write-Host "Unable to locate $($ad[1]) drive"
    }
}

main