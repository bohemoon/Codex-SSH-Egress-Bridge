[CmdletBinding()]
param([switch]$SelfTest)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:TunnelScript = Join-Path $PSScriptRoot 'start-reverse-socks.ps1'
$script:TunnelLog = Join-Path (
    Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'codex-ssh-eg'
) 'reverse-socks.log'
$script:TunnelProcess = $null

function Get-SshAliases {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }
    $aliases = New-Object System.Collections.Generic.List[string]
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -notmatch '^\s*Host\s+(.+?)\s*$') { continue }
        foreach ($name in ($Matches[1] -split '\s+')) {
            if ($name -and $name -notmatch '[*?!]' -and -not $aliases.Contains($name)) {
                $aliases.Add($name)
            }
        }
    }
    return $aliases.ToArray()
}

function Get-NativeCommand {
    param([string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "未找到 $Name。请先安装 Windows OpenSSH Client。"
    }
    return $command.Source
}

if ($SelfTest) {
    if (-not (Test-Path -LiteralPath $script:TunnelScript -PathType Leaf)) {
        throw 'Tunnel script is missing.'
    }
    $example = Join-Path $script:ProjectRoot 'examples\ssh-config.example'
    if (@(Get-SshAliases -Path $example) -notcontains 'example-remote') {
        throw 'SSH alias parser self-test failed.'
    }
    [void](Get-NativeCommand 'ssh.exe')
    [void](Get-NativeCommand 'scp.exe')
    Write-Output 'GUI self-test OK'
    exit 0
}

[System.Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object System.Windows.Forms.Form
$form.Text = 'codex-ssh-egress-bridge'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(940, 700)
$form.MinimumSize = New-Object System.Drawing.Size(880, 650)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 88
$header.BackColor = [System.Drawing.Color]::FromArgb(26, 42, 68)
$form.Controls.Add($header)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Codex SSH 出口桥接'
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 20)
$title.ForeColor = [System.Drawing.Color]::White
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(24, 14)
$header.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Windows 控制连接与部署，Codex 运行在远端 Linux；配置和日志不会上传。'
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(205, 218, 235)
$subtitle.AutoSize = $true
$subtitle.Location = New-Object System.Drawing.Point(27, 54)
$header.Controls.Add($subtitle)

function New-Group {
    param([string]$Text, [int]$Top, [int]$Height)
    $group = New-Object System.Windows.Forms.GroupBox
    $group.Text = $Text
    $group.Left = 18
    $group.Top = $Top
    $group.Width = 904
    $group.Height = $Height
    $group.Anchor = 'Top,Left,Right'
    $group.BackColor = [System.Drawing.Color]::White
    $form.Controls.Add($group)
    return $group
}

function New-Button {
    param(
        [System.Windows.Forms.Control]$Parent,
        [string]$Text,
        [int]$Left,
        [int]$Top,
        [int]$Width = 125,
        [switch]$Primary
    )
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.SetBounds($Left, $Top, $Width, 34)
    $button.FlatStyle = 'Flat'
    if ($Primary) {
        $button.BackColor = [System.Drawing.Color]::FromArgb(31, 111, 235)
        $button.ForeColor = [System.Drawing.Color]::White
        $button.FlatAppearance.BorderSize = 0
    }
    $Parent.Controls.Add($button)
    return $button
}

function Add-Log {
    param([string]$Text)
    $logBox.AppendText(
        ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Text) +
        [Environment]::NewLine
    )
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.ScrollToCaret()
}

function Set-Status {
    param([string]$Text, [string]$Kind = 'idle')
    $statusLabel.Text = $Text
    switch ($Kind) {
        'ok' { $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(20, 130, 75) }
        'error' { $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(190, 45, 45) }
        'working' { $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(180, 110, 0) }
        default { $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(90, 98, 108) }
    }
}

function Get-Settings {
    $alias = $aliasBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($alias) -or $alias -notmatch '^[A-Za-z0-9._-]+$') {
        throw 'SSH 别名只允许字母、数字、点、下划线和短横线。'
    }
    $config = $configBox.Text.Trim()
    if (-not (Test-Path -LiteralPath $config -PathType Leaf)) {
        throw 'SSH 配置文件不存在。'
    }
    return @{
        Alias = $alias
        Config = (Resolve-Path -LiteralPath $config).Path
        SocksPort = [int]$socksPort.Value
        HttpPort = [int]$httpPort.Value
    }
}

function Run-UiAction {
    param([string]$Name, [scriptblock]$Action)
    try {
        $form.UseWaitCursor = $true
        $form.Enabled = $false
        Set-Status "$Name：进行中…" 'working'
        Add-Log "$Name：开始"
        $form.Refresh()
        & $Action
        Set-Status "$Name：完成" 'ok'
        Add-Log "$Name：完成"
    }
    catch {
        Set-Status "$Name：失败" 'error'
        Add-Log "$Name：$($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "$Name 失败",
            'OK',
            'Error'
        ) | Out-Null
    }
    finally {
        $form.Enabled = $true
        $form.UseWaitCursor = $false
    }
}

function Refresh-Aliases {
    $current = $aliasBox.Text
    $aliasBox.Items.Clear()
    foreach ($name in @(Get-SshAliases -Path $configBox.Text.Trim())) {
        [void]$aliasBox.Items.Add($name)
    }
    if ($current) {
        $aliasBox.Text = $current
    }
    elseif ($aliasBox.Items.Count -gt 0) {
        $aliasBox.SelectedIndex = 0
    }
    Add-Log "读取到 $($aliasBox.Items.Count) 个 SSH 别名。"
}

$connection = New-Group '1. 选择远端并测试连接' 100 142
$configLabel = New-Object System.Windows.Forms.Label
$configLabel.Text = 'SSH 配置'
$configLabel.SetBounds(18, 32, 75, 24)
$connection.Controls.Add($configLabel)
$configBox = New-Object System.Windows.Forms.TextBox
$configBox.SetBounds(95, 28, 620, 28)
$configBox.Anchor = 'Top,Left,Right'
$configBox.Text = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.ssh\config'
$connection.Controls.Add($configBox)
$browseButton = New-Button $connection '浏览…' 728 26 72
$refreshButton = New-Button $connection '刷新别名' 808 26 78

$aliasLabel = New-Object System.Windows.Forms.Label
$aliasLabel.Text = 'SSH 别名'
$aliasLabel.SetBounds(18, 80, 75, 24)
$connection.Controls.Add($aliasLabel)
$aliasBox = New-Object System.Windows.Forms.ComboBox
$aliasBox.SetBounds(95, 75, 230, 28)
$connection.Controls.Add($aliasBox)

$socksLabel = New-Object System.Windows.Forms.Label
$socksLabel.Text = 'SOCKS 端口'
$socksLabel.SetBounds(348, 80, 90, 24)
$connection.Controls.Add($socksLabel)
$socksPort = New-Object System.Windows.Forms.NumericUpDown
$socksPort.SetBounds(438, 75, 88, 28)
$socksPort.Minimum = 1
$socksPort.Maximum = 65535
$socksPort.Value = 10809
$connection.Controls.Add($socksPort)

$httpLabel = New-Object System.Windows.Forms.Label
$httpLabel.Text = 'HTTP 端口'
$httpLabel.SetBounds(548, 80, 82, 24)
$connection.Controls.Add($httpLabel)
$httpPort = New-Object System.Windows.Forms.NumericUpDown
$httpPort.SetBounds(630, 75, 88, 28)
$httpPort.Minimum = 1
$httpPort.Maximum = 65535
$httpPort.Value = 17898
$connection.Controls.Add($httpPort)
$testButton = New-Button $connection '测试 SSH' 748 73 138 -Primary

$tunnel = New-Group '2. 启动 Windows 隧道' 252 96
$startButton = New-Button $tunnel '启动隧道' 18 36 125 -Primary
$stopButton = New-Button $tunnel '停止隧道' 153 36 115
$tunnelLogButton = New-Button $tunnel '查看隧道日志' 278 36 145
$tunnelLabel = New-Object System.Windows.Forms.Label
$tunnelLabel.Text = '● 尚未启动'
$tunnelLabel.SetBounds(455, 43, 260, 26)
$tunnelLabel.ForeColor = [System.Drawing.Color]::FromArgb(90, 98, 108)
$tunnel.Controls.Add($tunnelLabel)

$remote = New-Group '3. 部署、验证并打开远端 Codex' 358 116
$wrapCheck = New-Object System.Windows.Forms.CheckBox
$wrapCheck.Text = '安装为默认 codex 命令（已有旧 wrapper 时不要勾选）'
$wrapCheck.SetBounds(18, 27, 490, 26)
$remote.Controls.Add($wrapCheck)
$deployButton = New-Button $remote '部署 / 安装' 18 65 130 -Primary
$verifyButton = New-Button $remote '验证网络' 158 65 115
$diagnoseButton = New-Button $remote '只读诊断' 283 65 115
$openButton = New-Button $remote '打开远端 Codex' 408 65 160
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.SetBounds(600, 73, 270, 25)
$remote.Controls.Add($statusLabel)
Set-Status '等待操作'

$logGroup = New-Group '运行记录（分享前请脱敏）' 484 198
$logGroup.Anchor = 'Top,Bottom,Left,Right'
$logBox = New-Object System.Windows.Forms.RichTextBox
$logBox.SetBounds(12, 26, 878, 158)
$logBox.Anchor = 'Top,Bottom,Left,Right'
$logBox.ReadOnly = $true
$logBox.BackColor = [System.Drawing.Color]::FromArgb(17, 24, 39)
$logBox.ForeColor = [System.Drawing.Color]::FromArgb(220, 230, 240)
$logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$logGroup.Controls.Add($logBox)

$browseButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = '选择 SSH config'
    $dialog.FileName = 'config'
    $dialog.Filter = 'SSH config|config|所有文件|*.*'
    if ($dialog.ShowDialog() -eq 'OK') {
        $configBox.Text = $dialog.FileName
        Refresh-Aliases
    }
})
$refreshButton.Add_Click({
    try { Refresh-Aliases } catch { Add-Log $_.Exception.Message }
})

$testButton.Add_Click({
    Run-UiAction '测试 SSH' {
        $settings = Get-Settings
        $ssh = Get-NativeCommand 'ssh.exe'
        $arguments = @(
            '-F', $settings.Config,
            '-o', 'BatchMode=yes',
            '-o', 'ConnectTimeout=10',
            $settings.Alias,
            "printf 'SSH_OK\n'"
        )
        $output = & $ssh @arguments 2>&1
        foreach ($line in $output) { Add-Log ([string]$line) }
        if ($LASTEXITCODE -ne 0) { throw "SSH 返回退出码 $LASTEXITCODE" }
    }
})

$startButton.Add_Click({
    Run-UiAction '启动隧道' {
        $settings = Get-Settings
        if ($script:TunnelProcess) {
            $script:TunnelProcess.Refresh()
            if (-not $script:TunnelProcess.HasExited) {
                throw '隧道已经由本界面启动。'
            }
        }
        $arguments = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', ('"' + $script:TunnelScript + '"'),
            '-SshHost', $settings.Alias,
            '-RemoteSocksPort', [string]$settings.SocksPort,
            '-SshConfig', ('"' + $settings.Config + '"')
        )
        $parameters = @{
            FilePath = (Get-Process -Id $PID).Path
            ArgumentList = $arguments
            WindowStyle = 'Hidden'
            PassThru = $true
        }
        $script:TunnelProcess = Start-Process @parameters
        $tunnelLabel.Text = '● 正在运行'
        $tunnelLabel.ForeColor = [System.Drawing.Color]::FromArgb(20, 130, 75)
    }
})

$stopButton.Add_Click({
    Run-UiAction '停止隧道' {
        if (-not $script:TunnelProcess) {
            throw '本界面没有启动中的隧道。'
        }
        $script:TunnelProcess.Refresh()
        if (-not $script:TunnelProcess.HasExited) {
            $output = & taskkill.exe /PID $script:TunnelProcess.Id /T /F 2>&1
            foreach ($line in $output) { Add-Log ([string]$line) }
        }
        $script:TunnelProcess = $null
        $tunnelLabel.Text = '● 已停止'
        $tunnelLabel.ForeColor = [System.Drawing.Color]::FromArgb(90, 98, 108)
    }
})

$tunnelLogButton.Add_Click({
    if (Test-Path -LiteralPath $script:TunnelLog -PathType Leaf) {
        Start-Process notepad.exe -ArgumentList ('"' + $script:TunnelLog + '"')
    }
    else { Add-Log '隧道日志尚未生成。' }
})

$deployButton.Add_Click({
    Run-UiAction '部署远端' {
        $settings = Get-Settings
        $ssh = Get-NativeCommand 'ssh.exe'
        $scp = Get-NativeCommand 'scp.exe'
        $mkdirArgs = @(
            '-F', $settings.Config,
            '-o', 'BatchMode=yes',
            '-o', 'ConnectTimeout=10',
            $settings.Alias,
            'mkdir -p ~/codex-ssh-egress-bridge'
        )
        $output = & $ssh @mkdirArgs 2>&1
        foreach ($line in $output) { Add-Log ([string]$line) }
        if ($LASTEXITCODE -ne 0) { throw "创建远端目录失败，退出码 $LASTEXITCODE" }

        $destination = $settings.Alias + ':~/codex-ssh-egress-bridge/'
        $copyArgs = @(
            '-F', $settings.Config,
            '-r',
            (Join-Path $script:ProjectRoot 'src'),
            (Join-Path $script:ProjectRoot 'scripts'),
            (Join-Path $script:ProjectRoot 'pyproject.toml'),
            $destination
        )
        $output = & $scp @copyArgs 2>&1
        foreach ($line in $output) { Add-Log ([string]$line) }
        if ($LASTEXITCODE -ne 0) { throw "复制项目失败，退出码 $LASTEXITCODE" }

        $install = 'cd ~/codex-ssh-egress-bridge && SOCKS_PORT=' +
            $settings.SocksPort + ' HTTP_PROXY_PORT=' + $settings.HttpPort +
            ' bash scripts/linux/install.sh'
        if ($wrapCheck.Checked) { $install += ' --wrap-codex' }
        $output = & $ssh -F $settings.Config -o BatchMode=yes $settings.Alias $install 2>&1
        foreach ($line in $output) { Add-Log ([string]$line) }
        if ($LASTEXITCODE -ne 0) { throw "远端安装失败，退出码 $LASTEXITCODE" }
    }
})

$verifyButton.Add_Click({
    Run-UiAction '验证网络' {
        $settings = Get-Settings
        $ssh = Get-NativeCommand 'ssh.exe'
        $output = & $ssh -F $settings.Config -o BatchMode=yes $settings.Alias (
            '~/.local/bin/codex-ssh-eg-verify'
        ) 2>&1
        foreach ($line in $output) { Add-Log ([string]$line) }
        if ($LASTEXITCODE -ne 0) { throw "验证失败，退出码 $LASTEXITCODE" }
    }
})

$diagnoseButton.Add_Click({
    Run-UiAction '只读诊断' {
        $settings = Get-Settings
        $ssh = Get-NativeCommand 'ssh.exe'
        $output = & $ssh -F $settings.Config -o BatchMode=yes $settings.Alias (
            '~/.local/bin/codex-ssh-eg-diagnose'
        ) 2>&1
        foreach ($line in $output) { Add-Log ([string]$line) }
        if ($LASTEXITCODE -ne 0) { throw "诊断失败，退出码 $LASTEXITCODE" }
    }
})

$openButton.Add_Click({
    try {
        $settings = Get-Settings
        $ssh = Get-NativeCommand 'ssh.exe'
        $escapedSsh = $ssh.Replace("'", "''")
        $escapedConfig = $settings.Config.Replace("'", "''")
        $escapedAlias = $settings.Alias.Replace("'", "''")
        $command = "& '$escapedSsh' -t -F '$escapedConfig' '$escapedAlias' 'cd ~ && ~/.local/bin/codex-ssh-eg'"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        Start-Process powershell.exe -ArgumentList @(
            '-NoExit', '-NoProfile', '-EncodedCommand', $encoded
        )
        Add-Log '已打开新的远端 Codex 终端。'
    }
    catch { Add-Log "打开 Codex 失败：$($_.Exception.Message)" }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    if ($script:TunnelProcess) {
        try {
            $script:TunnelProcess.Refresh()
            if ($script:TunnelProcess.HasExited) {
                $tunnelLabel.Text = '● 已退出，请查看日志'
                $tunnelLabel.ForeColor = [System.Drawing.Color]::FromArgb(190, 45, 45)
                $script:TunnelProcess = $null
            }
        }
        catch {
            $tunnelLabel.Text = '● 状态未知'
            $tunnelLabel.ForeColor = [System.Drawing.Color]::FromArgb(190, 45, 45)
        }
    }
})
$timer.Start()

$form.Add_FormClosing({
    if ($script:TunnelProcess) {
        $script:TunnelProcess.Refresh()
        if (-not $script:TunnelProcess.HasExited) {
            $answer = [System.Windows.Forms.MessageBox]::Show(
                '隧道仍在运行。退出时一并停止吗？选择“否”会让它继续运行。',
                '隧道正在运行',
                'YesNoCancel',
                'Question'
            )
            if ($answer -eq 'Cancel') {
                $_.Cancel = $true
                return
            }
            if ($answer -eq 'Yes') {
                & taskkill.exe /PID $script:TunnelProcess.Id /T /F | Out-Null
            }
        }
    }
})

try { Refresh-Aliases } catch { Add-Log '请选择 SSH config 文件。' }
Add-Log '按 1 → 2 → 3 操作。默认不会覆盖现有 codex 命令。'
[void]$form.ShowDialog()
$timer.Stop()
