#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$ISO = 'C:\Users\andpe\Downloads\CentOS-Stream-10-latest-x86_64-dvd1.iso',
    [string]$VMRoot = 'D:\Hyper-V\Gandalf',
    [string]$SwitchName = 'K8s-External',
    [string]$VMName = 'gandalf-storage1',
    [UInt64]$MemoryBytes = 4GB,
    [int]$ProcessorCount = 2,
    [UInt64]$OSDiskSizeBytes = 40GB,
    [UInt64]$DataDiskSizeBytes = 100GB
)

$ErrorActionPreference = 'Stop'

Import-Module Hyper-V

if (-not (Test-Path -LiteralPath $ISO -PathType Leaf)) {
    throw "ISO CentOS non trovato: $ISO"
}

Get-VMSwitch -Name $SwitchName -ErrorAction Stop | Out-Null

if (Get-VM -Name $VMName -ErrorAction SilentlyContinue) {
    throw "La VM '$VMName' esiste già. Non verrà modificata."
}

$vmDirectory = Join-Path $VMRoot $VMName
$osVhdPath = Join-Path $vmDirectory "$VMName-os.vhdx"
$dataVhdPath = Join-Path $vmDirectory "$VMName-data.vhdx"
if (Test-Path -LiteralPath $vmDirectory) {
    throw "La directory '$vmDirectory' esiste già. Verifica i file prima di procedere."
}

if ($PSCmdlet.ShouldProcess($VMName, "creare la VM NFS e collegare un disco dati da $DataDiskSizeBytes byte")) {
    New-Item -ItemType Directory -Path $vmDirectory -Force | Out-Null

    New-VM `
        -Name $VMName `
        -MemoryStartupBytes $MemoryBytes `
        -Generation 2 `
        -SwitchName $SwitchName `
        -Path $VMRoot `
        -NewVHDPath $osVhdPath `
        -NewVHDSizeBytes $OSDiskSizeBytes | Out-Null

    Set-VM -Name $VMName -ProcessorCount $ProcessorCount -AutomaticCheckpointsEnabled $false
    Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false -StartupBytes $MemoryBytes
    Set-VMFirmware -VMName $VMName -EnableSecureBoot Off

    New-VHD -Path $dataVhdPath -SizeBytes $DataDiskSizeBytes -Dynamic | Out-Null
    Add-VMHardDiskDrive -VMName $VMName -Path $dataVhdPath -ControllerType SCSI

    Add-VMDvdDrive -VMName $VMName -Path $ISO
    $dvd = Get-VMDvdDrive -VMName $VMName
    Set-VMFirmware -VMName $VMName -FirstBootDevice $dvd

    Write-Host "VM '$VMName' creata con disco OS ($osVhdPath) e disco dati ($dataVhdPath)."
    Write-Host 'Installa CentOS, configura IP statico e SSH, poi usa il playbook Ansible per inizializzare il disco dati e NFS.'
}