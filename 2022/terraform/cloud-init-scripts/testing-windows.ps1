Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

# Confirm the Firewall rule is configured. It should be created automatically by setup. Run the following to verify
if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Select-Object Name, Enabled)) {
    Write-Output "Firewall Rule 'OpenSSH-Server-In-TCP' does not exist, creating it..."
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
} else {
    Write-Output "Firewall rule 'OpenSSH-Server-In-TCP' has been created and exists."
}

# Add my SSH key to the authorized_keys file
Add-Content -Path "C:\ProgramData\ssh\administrators_authorized_keys" -Value "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDSDujXqHgH0BhMExw+PpxDIoadAmxl28KQQ/Lr73PRLhSYBe2JSvh3DFL1OkfLaORsNApXFdCmO2U4606o4a0ytduQmTBYSMfcAbaBqHxj3CU1HmOxLv4FZoXSrtm7Jvho8suwjIotVfCdWYqXAyVWxfTNfMUGKVPOJgLBDZhLZ+eg3KEKYR1V37pbdE/KZabBG627vMffXdGlrCXvkQaW3UjvMK7u+VqSh2ykllTijekDApwMAeFt+tSluIN7dvXWy38QnbYkVQAJGBmEkwqEwm1Dpv41JcDaqN1UQY5vjlUryqXDqBvo7Vof/2lubDtO0DHCD/C+1enZYW29UlSyGR7qki9wDS1GFkHemmI5d+QpjK5czKYhP+uB0eKcPTP4+kP6PRdahubZMQ18zkq5yVWfwloRKxa39MwBHYf1d7my+swR8Nf2AhCxb0b8M3RXj1hnT6oYfEAukg1yS3km/QXuSG400WmXKtU+G0i/Jr50CEKky5q8SkYP4ErBxDE= manuel@localhost.localdomain"

# Install containers feature
Enable-WindowsOptionalFeature -Online -FeatureName containers -All

# Install chocolatey
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

choco install -y vim

# Install rke2
Invoke-WebRequest -Uri https://raw.githubusercontent.com/rancher/rke2/master/install.ps1 -Outfile C:\Users\azureuser\rke2-install.ps1
C:\Users\azureuser\rke2-install.ps1 -Channel latest

mkdir /etc/rancher/rke2/

# administrators_authorized_keys needs to have ONLY TWO permissions: SYSTEM and Administrators (important). 
# Run this script in PowerShell as Administrator to fix the permissions on the file.
@'
$ak = "$ENV:ProgramData\ssh\administrators_authorized_keys"
$acl = Get-Acl $ak
$acl.SetAccessRuleProtection($true, $false)
$administratorsRule = New-Object system.security.accesscontrol.filesystemaccessrule("Administrators","FullControl","Allow")
$systemRule = New-Object system.security.accesscontrol.filesystemaccessrule("SYSTEM","FullControl","Allow")
$acl.SetAccessRule($administratorsRule)
$acl.SetAccessRule($systemRule)
$acl | Set-Acl
'@ | Out-File -FilePath fix-ssh-keys.ps1

./fix-ssh-keys.ps1
Restart-Service sshd

@'
server: "https://${IP}:9345"
token: "secret"
# $env:PATH+=";c:\var\lib\rancher\rke2\bin;c:\usr\local\bin"
# .\rke2-install.ps1 -Channel latest
# cp config.yaml /etc/rancher/rke2/config.yaml
# C:\usr\local\bin\rke2.exe agent service --add
# Start-Service -Name 'rke2'
# ctr -n k8s.io c ls
# Get-WinEvent -LogName Application -FilterXPath "*[System[Provider[@Name='rke2']]]" -MaxEvents 120 | Sort-Object TimeCreated | Select-Object TimeCreated, @{Name='ReplacementStrings';Expression={$_.Properties[0].Value}} | Format-Table -Wrap
'@ | Out-File -FilePath config.yaml

cp config.yaml C:\Users\azureuser\config.yaml
cp config.yaml /etc/rancher/rke2/

# Make sure the PATH is correctly set
[Environment]::SetEnvironmentVariable(
    "Path",
    [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine) + ";c:\var\lib\rancher\rke2\bin;c:\usr\local\bin",
    [EnvironmentVariableTarget]::Machine)

Restart-Computer
