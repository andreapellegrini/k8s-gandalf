$ISO = "C:\Users\andpe\Downloads\CentOS-Stream-10-latest-x86_64-dvd1.iso"
$VMRoot = "D:\Hyper-V\Gandalf"

New-Item -ItemType Directory -Force -Path $VMRoot | Out-Null

# crea switch esterno
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
if (-not (Get-VMSwitch -Name "K8s-External" -ErrorAction SilentlyContinue)) {
    New-VMSwitch -Name "K8s-External" -NetAdapterName $adapter.Name -AllowManagementOS $false
}

$vmSpecs = @(
    @{ Name = "gandalf-master1"; Memory = 8GB; CPU = 4; Disk = 80GB },
    @{ Name = "gandalf-worker1"; Memory = 16GB; CPU = 4; Disk = 120GB },
    @{ Name = "gandalf-worker2"; Memory = 16GB; CPU = 4; Disk = 120GB }
)

foreach ($vm in $vmSpecs) {
    $vmPath = "$VMRoot\$($vm.Name)"
    New-Item -ItemType Directory -Force -Path $vmPath | Out-Null

    New-VM -Name $vm.Name `
        -MemoryStartupBytes $vm.Memory `
        -Generation 2 `
        -SwitchName "K8s-External" `
        -Path $VMRoot `
        -NewVHDPath "$vmPath\$($vm.Name).vhdx" `
        -NewVHDSizeBytes $vm.Disk

    Set-VM -Name $vm.Name -ProcessorCount $vm.CPU
    Set-VMMemory -VMName $vm.Name -DynamicMemoryEnabled $false -StartupBytes $vm.Memory
    Set-VM -Name $vm.Name -AutomaticCheckpointsEnabled $false
    Set-VMFirmware -VMName $vm.Name -EnableSecureBoot Off

    Add-VMDvdDrive -VMName $vm.Name -Path $ISO
    $dvd = Get-VMDvdDrive -VMName $vm.Name
    Set-VMFirmware -VMName $vm.Name -FirstBootDevice $dvd
}

Get-VM -Name "gandalf-master1","gandalf-worker1","gandalf-worker2" | Select-Object Name,MemoryStartup,ProcessorCount,State