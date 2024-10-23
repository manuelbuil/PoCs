param(
    [string]$IP = "127.0.0.1"
)

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
Add-Content -Path "C:\ProgramData\ssh\administrators_authorized_keys" -Value "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC6t6DDODFcaTE+JB2LvQiE/ENTsea7yI59PjnJmm0TrhsVv1B7dIp2/lGVT2BbGQDZ/monN9F/ms+La56I5tyN34vymkJZi3OB0HEOlwQnpQRSSUcdvYzq/tXOyzSHakS+/eUyUzpXB5iVUMx3FgQd9kYHBBYXQEescbxbcQK+yRPk2QWu/qoioAqGUUZ2QnsguOISwwKCBtqmzlp1CTkCVZ2wHAJRQ+YBm7yFUwdSQAZNW3pUDcjP0lKvcY0XY+ZNQYb1sdEkwwYbu0yK+XHkZ8wPBoYfm4GLZ4sOeKlpk/qYlgLrq7QGNsDBWkgA6CZYTmzh793clsCylGnseZxK9Wb0S0LxwE1GvkyOAmfLWdIUBiFDB3rUPnl6xXVGoqxtbPrKa5HOulnl6elUrceSvAKfu/aoMQ2NhB525hJC2rODTImrUUZuwxVU+BRP5srvTzlVRqIVb0VdYFqszSSWY5/tV95R6NOxVGdG+80gEju3zLTBN+n6WvbzDneBnQM= manuel@pc-3.home"
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

$config = @'
server: "https://THEIP:9345"
token: "secret"
# $env:PATH+=";c:\var\lib\rancher\rke2\bin;c:\usr\local\bin"
# .\rke2-install.ps1 -Channel latest
# cp config.yaml /etc/rancher/rke2/config.yaml
# C:\usr\local\bin\rke2.exe agent service --add
# Start-Service -Name 'rke2'
# ctr -n k8s.io c ls
# Get-WinEvent -LogName Application -FilterXPath "*[System[Provider[@Name='rke2']]]" -MaxEvents 120 | Sort-Object TimeCreated | Select-Object TimeCreated, @{Name='AllProperties';Expression={($_.Properties | ForEach-Object { $_.Value }) -join ', '}} | Format-Table -Wrap
'@

$config = $config -replace 'THEIP', $IP
$config | Out-File -FilePath C:\Users\azureuser\config.yaml

cp C:\Users\azureuser\config.yaml /etc/rancher/rke2/

# Make sure the PATH is correctly set
[Environment]::SetEnvironmentVariable(
    "Path",
    [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine) + ";c:\var\lib\rancher\rke2\bin;c:\usr\local\bin",
    [EnvironmentVariableTarget]::Machine)

Restart-Computer

@'
# Define the username
$username = "azureuser"

# Prompt for the password
$password = Read-Host "Enter the password" -AsSecureString

# Set the password for the user
Set-LocalUser -Name $username -Password $password
'@

@'
xfreerget-vdp /u:azureuser /p:Linux12345678 /v:20.73.81.44
'@