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

# Install containers feature
Enable-WindowsOptionalFeature -Online -FeatureName containers -All

# Install chocolatey
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

choco install -y vim

# Install rke2
Invoke-WebRequest -Uri https://raw.githubusercontent.com/rancher/rke2/master/install.ps1 -Outfile rke2-install.ps1
.\rke2-install.ps1 -Channel latest

mkdir /etc/rancher/rke2/

@"
server: "https://$IP:6443"
token: "secret"
# .\rke2-install.ps1 -Channel latest
# cp config.yaml /etc/rancher/rke2/config.yaml
# C:\usr\local\bin\rke2.exe agent service –add
# Start-Service -Name 'rke2'
"@ | Out-File -FilePath config.yaml

cp config.yaml C:\Users\mbuil\config.yaml