# Reboot computer command
# https://www.windows-commandline.com/reboot-computer-from-command-line/

# "FIND" Exit codes info 
# https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/find#exit-codes

# Execute commands in wsl
# https://github.com/microsoft/WSL/discussions/6128

# DISM DOCS
# https://ss64.com/nt/dism.html

# Automatically detect if the terminal is running as admin and if it isn't restart it with admin rights
$CurrentRole = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$IsAdmin = $CurrentRole.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Output "Checking Admin Rights";

if (!$IsAdmin) {
    $originalArguments = "-NoLogo -NoProfile -NoExit -ExecutionPolicy Bypass"

    $originalArguments += " -File `"$($MyInvocation.MyCommand.Source)`"";

    foreach ($arg in $args) {
        $originalArguments += ' ';
        $originalArguments += $arg;
    }

    Start-Process -FilePath 'powershell' -Wait -Verb RunAs -ArgumentList $originalArguments;
    exit
}

Write-Output "Checking Requieriments";

$windowsFeatures = DISM /Online /Get-Features /Format:table /English

function CheckAndActivateWindowsFeatureRequiered {
    param (
        [string]$FeatureName
    )

    Write-Output "Checking $($FeatureName) status";

    $feature = $windowsFeatures | Select-String -Pattern $FeatureName;

    if ($null -eq $feature) {
        Write-Host "Feature requiered not found, exiting...";
        exit
    }

    $parts = $feature.Line.Split("|");

    if ($parts.Count -ne 2){
        Write-Output "Script isn't processing feature info right. Exiting...";
        exit
    }

    $featureStatus = $parts[1].Trim();

    if ($featureStatus -eq "Disabled") {
        Write-Output "Enabling $($FeatureName)";
        DISM /Online /NoRestart /Enable-Feature /FeatureName:$FeatureName;
        return $true;
    } 
    elseif ($featureStatus -eq "Enabled"){
        Write-Output "$($FeatureName) is already enabled, nothing to do.";
        return $false;
    }
    else {
        Write-Output "The script creator did something stupid, please report this error.";
        exit
    }

    # command to reverse this:
    # DISM /Online /Disable-Feature /FeatureName:$FeatureName
}

$FeaturesRequiered = @(
    "Microsoft-Hyper-V-All",
    "Microsoft-Windows-Subsystem-Linux"
)

$isRestartRequiered = $false;

foreach ($feature in $FeaturesRequiered) {
    $test = CheckAndActivateWindowsFeatureRequiered -FeatureName $feature;
    # Powershell is weird
    if ($test[$test.Count - 1]){
        $isRestartRequiered = $true;
    }
}

if ($isRestartRequiered) {
    $infoText = "The computer will be restarted to enable the needed features, please save your work and run this script again after the reboot";
    Write-Output $infoText;
    shutdown /r /t 15 /c $infoText
    shutdown -a
    exit
}

Write-Output "Preparing building environment";

wsl --update

$wslAvailableDistrosRaw = wsl --list;
# regexr.com/6uoof
$wslAvailableDistrosClean = $wslAvailableDistrosRaw -replace '[^\u0030-\u0039\u0041-\u005A\u0061-\u007A ]', '';

$distroWeNeed = $null;

foreach ($availableDistro in $wslAvailableDistrosClean) {
    if ($availableDistro.StartsWith("Ubuntu")){
        $distroWeNeed = $availableDistro.Replace(" predeterminado", "");
        break;
    }
}

if ($null -eq $distroWeNeed){
    $distroWeNeed = "Ubuntu";

    Write-Host "Installing wsl distro that is needed to continue..."

    wsl --install $distroWeNeed
}

wsl --set-version $distroWeNeed 2

Write-Host "Updating System"

wsl --distribution $distroWeNeed --user root apt update

wsl --distribution $distroWeNeed --user root apt --yes full-upgrade

Write-Host "Installing requisites"

wsl --distribution $distroWeNeed --user root apt --yes  install setools lzip patchelf e2fsprogs aria2 python3 attr wine winetricks python3-pip git

wsl --distribution $distroWeNeed --user root winetricks msxml6

wsl --distribution $distroWeNeed --user root pip install requests

Set-Location $HOME

$folder = "source";

if (!(Test-Path -Path $folder)) {
    Write-Host "Creating Working Directory"
    New-Item -Path $folder -ItemType Directory
}

Set-Location $folder

$subfolderPath = "MagiskOnWSALocal";

if (Test-Path -Path $subfolderPath) {
    Write-Host "Updating files..."
    Set-Location $subfolderPath
    wsl --distribution $distroWeNeed git pull
}
else{
    Write-Host "Downloading files..."
    wsl --distribution $distroWeNeed git clone https://github.com/LSPosed/MagiskOnWSALocal
    Set-Location $subfolderPath
}

wsl --distribution $distroWeNeed --user root scripts/build.sh --arch x64 --release-type WIF --gapps-brand MindTheGapps --gapps-variant pico --root-sol magisk --magisk-ver canary

Set-Location "output"

$lastestRelease = Get-ChildItem -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1

Set-Location $lastestRelease.PSChildName;

#PowerShell.exe -ExecutionPolicy Bypass -File .\Install.ps1

& .\Install.ps1

if ($Host.Name -eq "ConsoleHost") {
    Write-Host "Press any key to continue..."
    $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp") > $null
}
