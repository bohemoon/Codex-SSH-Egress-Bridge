[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SshHost,

    [ValidateRange(1, 65535)]
    [int]$RemoteSocksPort = 10809,

    [string]$SshConfig,

    [ValidateRange(1, 3600)]
    [int]$RetrySeconds = 10,

    [switch]$Once
)

$ErrorActionPreference = 'Stop'
$ssh = Get-Command ssh.exe -ErrorAction Stop

if (-not $SshConfig) {
    $SshConfig = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.ssh\config'
}
if (-not (Test-Path -LiteralPath $SshConfig -PathType Leaf)) {
    throw "SSH config not found. Pass -SshConfig explicitly."
}

$stateRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'codex-ssh-eg'
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
$logPath = Join-Path $stateRoot 'reverse-socks.log'

$identity = "$SshHost`:$RemoteSocksPort"
$sha256 = [Security.Cryptography.SHA256]::Create()
try {
    $hashBytes = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity))
}
finally {
    $sha256.Dispose()
}
$mutexSuffix = ([BitConverter]::ToString($hashBytes).Replace('-', '')).Substring(0, 16)
$mutex = [Threading.Mutex]::new($false, "Local\CodexSshEg_$mutexSuffix")
if (-not $mutex.WaitOne(0)) {
    throw "A tunnel with the same SSH host and port is already running."
}

$sshArgs = @(
    '-F', $SshConfig,
    '-N', '-T',
    '-R', "127.0.0.1:$RemoteSocksPort",
    '-o', 'BatchMode=yes',
    '-o', 'ServerAliveInterval=30',
    '-o', 'ServerAliveCountMax=3',
    '-o', 'ExitOnForwardFailure=yes',
    '-o', 'ConnectTimeout=15',
    '-o', 'TCPKeepAlive=yes',
    $SshHost
)

try {
    do {
        if ((Test-Path -LiteralPath $logPath) -and
            (Get-Item -LiteralPath $logPath).Length -gt 5MB) {
            Move-Item -LiteralPath $logPath -Destination "$logPath.1" -Force
        }

        Add-Content -LiteralPath $logPath -Value "[$(Get-Date -Format o)] starting tunnel"
        & $ssh.Source @sshArgs *>> $logPath
        $exitCode = $LASTEXITCODE
        Add-Content -LiteralPath $logPath -Value (
            "[$(Get-Date -Format o)] ssh exited with code $exitCode"
        )

        if (-not $Once) {
            Start-Sleep -Seconds $RetrySeconds
        }
    } while (-not $Once)
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
