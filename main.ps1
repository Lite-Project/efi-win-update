# 
#=====---v---=====#=====---v---=====#=-Default  Param-=#=====---v---=====#=====---v---=====#=====---v---=====#
$o1 = 'X'
$o2 = 'X'
$o3 = 'X'

$sfcE = "Windows Resource Protection found corrupt files but was unable"
$dismE = "Error"

#list of available drive letters
$ad = [char[]]('A'[0]..'Z'[0]) | Where-Object { $_ -notin (Get-PSDrive -PSProvider FileSystem).Name }
#New EFI Partition size for L3
$esize = 512MB

#=====---^---=====#=====---^---=====#=====---^---=====#=====---^---=====#=====---^---=====#=====---^---=====#

function main {
    cls
    Write-Host @"


1.  [$o1] DISM and SFC
2.  [$o2] Clear Fonts in EFI partition
3.  [$o3] Recreate EFI Partition
"@
    $input = Read-Host "Please select which option you'd like to run"
    if ($input -eq '1') {
        if ($o1 -eq 'X') {$o1 = '✓'} else {$o1 = 'X'}
    } elseif ($input -eq '2') {
        if ($o2 -eq 'X') {$o2 = '✓'} else {$o2 = 'X'}
    } elseif ($input -eq '3') {
        if ($ad.Count -lt 2) {
            Write-Warning "There are insufficient available drive letters to select this operation."
            Read-Host " "
        } elseif ($o3 -eq 'X') {$o3 = '✓'} else {$o3 = 'X'}
    }
    if (($input -eq '') -and (($o1 -eq '✓') -or ($o2 -eq '✓') -or ($o3 -eq '✓'))) {
        if ($o1 -eq '✓') {
            l1
        }
        if ($o2 -eq '✓') {
            l2
            if ($o3 -eq '✓') {l3 -L3 $true}
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
        cls
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
        cls
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

    Get-Partition -DriveLetter $ad[0] | Remove-PartitionAccessPath -AccessPath "$($ad[0]):\"
}

function l3 {
    param([bool]$L3 = $false)

}

main