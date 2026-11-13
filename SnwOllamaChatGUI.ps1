Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# ==================== Configuration ====================
$script:OllamaHost    = "127.0.0.1"
$script:OllamaPort    = 11434
$script:OllamaChatUrl = "http://127.0.0.1:11434/api/chat"
$script:OllamaTagsUrl = "http://127.0.0.1:11434/api/tags"
$script:ModelName     = "llama3.2:1b"
$script:SystemPrompt  = "You are a helpful multilingual assistant. Always reply in the SAME language the user writes in. If the user writes in Arabic, answer in Arabic. Give clear, complete, and useful answers."
$script:OllamaProcess = $null
$script:ChatHistory   = New-Object System.Collections.ArrayList
$script:IsBusy        = $false
$script:IsRtl         = $false
$script:DiagWindow    = $null

# ==================== Main Window XAML ====================
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Ollama Chat" Height="700" Width="900"
        FlowDirection="LeftToRight"
        WindowStartupLocation="CenterScreen"
        Background="#F5F5F5">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="#E3F2FD" CornerRadius="4" Padding="8" Margin="0,0,0,6">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Ellipse x:Name="StatusDot" Grid.Column="0" Width="12" Height="12"
                         Fill="Gray" VerticalAlignment="Center" Margin="0,0,6,0"/>
                <TextBlock x:Name="StatusLabel" Grid.Column="1" Text="Checking..."
                           VerticalAlignment="Center" FontSize="13"/>
                <Button x:Name="RefreshButton" Grid.Column="2" Content="Diagnostics"
                        Width="100" Height="26" Margin="8,0,0,0"/>
                <Button x:Name="StartOllamaButton" Grid.Column="3" Content="Start Ollama"
                        Width="110" Height="26" Margin="8,0,0,0" IsEnabled="False"/>
                <Button x:Name="DirectionButton" Grid.Column="4" Content="Direction: LTR"
                        Width="120" Height="26" Margin="8,0,0,0"/>
                <TextBlock x:Name="ModelLabel" Grid.Column="5"
                           VerticalAlignment="Center" Margin="12,0,0,0"
                           FontWeight="Bold" Foreground="#2A6FDB" FontSize="12"/>
            </Grid>
        </Border>

        <Border Grid.Row="1" BorderBrush="#CCCCCC" BorderThickness="1"
                Background="White" CornerRadius="4" Padding="8">
            <ScrollViewer x:Name="ChatScroll" VerticalScrollBarVisibility="Auto">
                <StackPanel x:Name="ChatPanel"/>
            </ScrollViewer>
        </Border>

        <Grid Grid.Row="2" Margin="0,8,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBox x:Name="InputBox" Grid.Column="0" Height="70" Padding="6"
                     TextWrapping="Wrap" AcceptsReturn="True"
                     VerticalScrollBarVisibility="Auto" FontSize="14"/>
            <Button x:Name="SendButton" Grid.Column="1" Content="Send"
                    Width="90" Height="70" Margin="8,0,0,0"
                    FontSize="14" FontWeight="Bold"
                    Background="#2A6FDB" Foreground="White" BorderThickness="0"/>
        </Grid>

        <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,8,0,0">
            <Button x:Name="ExportButton" Content="Export Chat" Width="120" Height="30" Margin="0,0,8,0"/>
            <Button x:Name="ClearButton" Content="Clear Chat" Width="100" Height="30" Margin="0,0,8,0"/>
            <Button x:Name="ExitButton" Content="Exit" Width="80" Height="30"/>
        </StackPanel>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$script:Window = [Windows.Markup.XamlReader]::Load($reader)

# Store ALL UI elements in $script: scope
$script:ChatPanel      = $script:Window.FindName("ChatPanel")
$script:ChatScroll     = $script:Window.FindName("ChatScroll")
$script:InputBox       = $script:Window.FindName("InputBox")
$script:SendButton     = $script:Window.FindName("SendButton")
$script:StatusLabel    = $script:Window.FindName("StatusLabel")
$script:StatusDot      = $script:Window.FindName("StatusDot")
$script:StartOllamaBtn = $script:Window.FindName("StartOllamaButton")
$script:RefreshButton  = $script:Window.FindName("RefreshButton")
$script:DirectionBtn   = $script:Window.FindName("DirectionButton")
$script:ExportButton   = $script:Window.FindName("ExportButton")
$script:ClearButton    = $script:Window.FindName("ClearButton")
$script:ExitButton     = $script:Window.FindName("ExitButton")
$script:ModelLabel     = $script:Window.FindName("ModelLabel")

$script:ModelLabel.Text = $script:ModelName

# ==================== Helper Functions ====================

function Test-OllamaPort {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $task = $client.ConnectAsync($script:OllamaHost, $script:OllamaPort)
            if (-not $task.Wait(200)) { return $false }
            return ($task.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion)
        } finally {
            $client.Dispose()
        }
    } catch {
        return $false
    }
}

function Set-StatusUi {
    param([string]$State, [string]$Text)
    $color = switch ($State) {
        "running"  { [System.Windows.Media.Brushes]::Green }
        "stopped"  { [System.Windows.Media.Brushes]::Firebrick }
        "starting" { [System.Windows.Media.Brushes]::Orange }
        default    { [System.Windows.Media.Brushes]::Gray }
    }
    $script:StatusDot.Fill = $color
    $script:StatusLabel.Text = $Text
}

function Update-OllamaStatus {
    if (Test-OllamaPort) {
        Set-StatusUi "running" "Ollama is running"
        $script:StartOllamaBtn.IsEnabled = $false
        return $true
    } else {
        Set-StatusUi "stopped" "Ollama is stopped"
        $script:StartOllamaBtn.IsEnabled = $true
        return $false
    }
}

function Add-MessageBubble {
    param([string]$Sender, [string]$Text, [string]$Color)
    $border = New-Object System.Windows.Controls.Border
    $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
    $border.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $border.Padding = [System.Windows.Thickness]::new(10,6,10,6)
    $border.Margin = [System.Windows.Thickness]::new(0,4,0,4)
    $stack = New-Object System.Windows.Controls.StackPanel
    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Text = $Sender
    $lbl.FontWeight = "Bold"
    $lbl.FontSize = 12
    $lbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#333333")
    $lbl.Margin = [System.Windows.Thickness]::new(0,0,0,4)
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $Text
    $tb.TextWrapping = "Wrap"
    $tb.FontSize = 14
    $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#111111")
    [void]$stack.Children.Add($lbl)
    [void]$stack.Children.Add($tb)
    $border.Child = $stack
    [void]$script:ChatPanel.Children.Add($border)
    $script:ChatScroll.ScrollToEnd()
}

function Set-Direction {
    param([bool]$Rtl)
    $script:IsRtl = $Rtl
    if ($Rtl) {
        $script:Window.FlowDirection = "RightToLeft"
        $script:DirectionBtn.Content = "Direction: RTL"
    } else {
        $script:Window.FlowDirection = "LeftToRight"
        $script:DirectionBtn.Content = "Direction: LTR"
    }
}

function Start-OllamaServer {
    if ($script:IsBusy) { return }
    if (Test-OllamaPort) { Update-OllamaStatus | Out-Null; return }

    $ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
    if (-not $ollamaCmd) {
        [System.Windows.MessageBox]::Show("Ollama executable not found in PATH.", "Error") | Out-Null
        return
    }

    $script:IsBusy = $true
    Set-StatusUi "starting" "Starting Ollama..."
    $script:StartOllamaBtn.IsEnabled = $false

    try {
        $script:OllamaProcess = Start-Process -FilePath $ollamaCmd.Source `
            -ArgumentList "serve" -WindowStyle Hidden -PassThru
    } catch {
        [System.Windows.MessageBox]::Show("Failed to start: $($_.Exception.Message)", "Error") | Out-Null
        Set-StatusUi "stopped" "Start failed"
        $script:StartOllamaBtn.IsEnabled = $true
        $script:IsBusy = $false
        return
    }

    $script:StartPs = [PowerShell]::Create()
    [void]$script:StartPs.AddScript({
        param($hostIp, $port, $timeoutMs)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($sw.ElapsedMilliseconds -lt $timeoutMs) {
            $c = New-Object System.Net.Sockets.TcpClient
            try {
                $t = $c.ConnectAsync($hostIp, $port)
                if ($t.Wait(200) -and $t.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) { return $true }
            } catch {} finally { $c.Dispose() }
            Start-Sleep -Milliseconds 200
        }
        return $false
    }).AddArgument($script:OllamaHost).AddArgument($script:OllamaPort).AddArgument(15000)

    $script:StartAsync = $script:StartPs.BeginInvoke()

    $script:StartTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:StartTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $script:StartTimer.Add_Tick({
        if (-not $script:StartAsync.IsCompleted) { return }
        $script:StartTimer.Stop()
        $ok = $false
        try { $ok = $script:StartPs.EndInvoke($script:StartAsync)[0] } catch {}
        try { $script:StartPs.Dispose() } catch {}
        if ($ok) {
            Set-StatusUi "running" "Ollama is running"
            $script:StartOllamaBtn.IsEnabled = $false
        } else {
            Set-StatusUi "stopped" "Start failed - check terminal"
            $script:StartOllamaBtn.IsEnabled = $true
        }
        $script:IsBusy = $false
    })
    $script:StartTimer.Start()
}

function Export-Chat {
    if ($script:ChatHistory.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No conversation to export.", "Info") | Out-Null
        return
    }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = "Text Files (*.txt)|*.txt"
    $dlg.FileName = "OllamaChat_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    if ($dlg.ShowDialog()) {
        $lines = foreach ($m in $script:ChatHistory) {
            $who = if ($m.role -eq "user") { "You" }
                   elseif ($m.role -eq "assistant") { "Assistant" }
                   else { $m.role }
            "[$who]`r`n$($m.content)`r`n"
        }
        [System.IO.File]::WriteAllText($dlg.FileName, ($lines -join "`r`n"), [System.Text.UTF8Encoding]::new($false))
        [System.Windows.MessageBox]::Show("Exported to:`n$($dlg.FileName)", "Done") | Out-Null
    }
}

function Send-Message {
    if ($script:IsBusy) { return }

    $userText = $script:InputBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($userText)) { return }

    if (-not (Test-OllamaPort)) {
        Set-StatusUi "stopped" "Ollama is stopped"
        $script:StartOllamaBtn.IsEnabled = $true
        Add-MessageBubble -Sender "System" -Text "Ollama is not running. Click 'Start Ollama'." -Color "#FFCDD2"
        return
    }

    $script:IsBusy = $true
    Add-MessageBubble -Sender "You" -Text $userText -Color "#DCEBFF"
    [void]$script:ChatHistory.Add(@{ role = "user"; content = $userText })
    $script:InputBox.Clear()
    $script:SendButton.IsEnabled = $false
    $script:StatusLabel.Text = "Assistant is typing..."

    $messages = New-Object System.Collections.ArrayList
    [void]$messages.Add(@{ role = "system"; content = $script:SystemPrompt })
    foreach ($m in $script:ChatHistory) { [void]$messages.Add($m) }
    $payload = @{ model = $script:ModelName; messages = $messages; stream = $false } |
               ConvertTo-Json -Depth 10 -Compress

    $script:SendPs = [PowerShell]::Create()
    [void]$script:SendPs.AddScript({
        param($url, $body)
        try {
            $resp = Invoke-RestMethod -Uri $url -Method Post -Body $body `
                    -ContentType "application/json; charset=utf-8" -TimeoutSec 300
            return @{ ok = $true; content = $resp.message.content }
        } catch {
            return @{ ok = $false; error = $_.Exception.Message }
        }
    }).AddArgument($script:OllamaChatUrl).AddArgument($payload)

    $script:SendAsync = $script:SendPs.BeginInvoke()

    $script:SendTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:SendTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:SendTimer.Add_Tick({
        if (-not $script:SendAsync.IsCompleted) { return }
        $script:SendTimer.Stop()
        try {
            $result = $script:SendPs.EndInvoke($script:SendAsync)
            try { $script:SendPs.Dispose() } catch {}
            if ($result.ok) {
                Add-MessageBubble -Sender "Assistant" -Text $result.content -Color "#E8F5E9"
                [void]$script:ChatHistory.Add(@{ role = "assistant"; content = $result.content })
                Set-StatusUi "running" "Ollama is running"
            } else {
                Add-MessageBubble -Sender "Error" -Text $result.error -Color "#FFCDD2"
                if (-not (Test-OllamaPort)) {
                    Set-StatusUi "stopped" "Ollama is stopped"
                    $script:StartOllamaBtn.IsEnabled = $true
                } else {
                    Set-StatusUi "running" "Ollama is running (request error)"
                }
            }
        } catch {
            Add-MessageBubble -Sender "Error" -Text $_.Exception.Message -Color "#FFCDD2"
            try { $script:SendPs.Dispose() } catch {}
        } finally {
            $script:IsBusy = $false
            $script:SendButton.IsEnabled = $true
            $script:InputBox.Focus() | Out-Null
        }
    })
    $script:SendTimer.Start()
}

function Show-Diagnostics {
    if ($script:DiagWindow -and $script:DiagWindow.IsVisible) {
        $script:DiagWindow.Activate()
        return
    }

    [xml]$dxaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Ollama Diagnostics" Height="480" Width="780"
        WindowStartupLocation="CenterOwner"
        Background="#FAFAFA"
        FlowDirection="LeftToRight">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Text="Ollama Diagnostic Check" FontWeight="Bold"
                   FontSize="14" Margin="0,0,0,6"/>
        <Border Grid.Row="1" BorderBrush="#CCCCCC" BorderThickness="1" Background="White">
            <TextBox x:Name="LogBox" IsReadOnly="True" FontFamily="Consolas"
                     FontSize="12" VerticalScrollBarVisibility="Auto"
                     HorizontalScrollBarVisibility="Auto"
                     TextWrapping="NoWrap" Padding="6" BorderThickness="0"
                     FlowDirection="LeftToRight"/>
        </Border>
        <Button Grid.Row="2" x:Name="CloseBtn" Content="Close"
                Width="100" Height="30" HorizontalAlignment="Right" Margin="0,8,0,0"/>
    </Grid>
</Window>
"@

    $dreader = New-Object System.Xml.XmlNodeReader $dxaml
    $script:DiagWindow = [Windows.Markup.XamlReader]::Load($dreader)
    $script:DiagWindow.Owner = $script:Window

    $script:DiagLogBox = $script:DiagWindow.FindName("LogBox")
    $diagCloseBtn = $script:DiagWindow.FindName("CloseBtn")
    $diagCloseBtn.Add_Click({ $script:DiagWindow.Close() })

    $script:DiagWindow.Add_Loaded({
        $script:DiagLogBox.AppendText("Diagnostic started at $(Get-Date -Format 'HH:mm:ss')`r`n")
        $script:DiagLogBox.AppendText("Target: $($script:OllamaHost):$($script:OllamaPort)`r`n`r`n")

        $script:DiagState = "start"
        $script:DiagTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:DiagTimer.Interval = [TimeSpan]::FromMilliseconds(150)
        $script:DiagTimer.Add_Tick({
            switch ($script:DiagState) {
                "start" {
                    $script:DiagLogBox.AppendText("[Step 1/3] TCP check on $($script:OllamaHost):$($script:OllamaPort) ... ")
                    $sw = [System.Diagnostics.Stopwatch]::StartNew()
                    $tcpOk = Test-OllamaPort
                    $sw.Stop()
                    if ($tcpOk) {
                        $script:DiagLogBox.AppendText("OK ($($sw.ElapsedMilliseconds) ms)`r`n")
                        $script:DiagLogBox.ScrollToEnd()
                        $script:DiagState = "http"
                    } else {
                        $script:DiagLogBox.AppendText("FAILED ($($sw.ElapsedMilliseconds) ms)`r`n")
                        $script:DiagLogBox.AppendText("`r`n>>> RESULT: Ollama is NOT running (port closed).`r`n")
                        $script:DiagLogBox.AppendText(">>> Click 'Start Ollama' on the main window to launch it.`r`n")
                        $script:DiagLogBox.ScrollToEnd()
                        $script:DiagTimer.Stop()
                    }
                }
                "http" {
                    $script:DiagLogBox.AppendText("[Step 2/3] GET $($script:OllamaTagsUrl) ... `r`n")
                    $script:DiagLogBox.ScrollToEnd()
                    $script:DiagSw = [System.Diagnostics.Stopwatch]::StartNew()
                    $script:DiagPs = [PowerShell]::Create()
                    [void]$script:DiagPs.AddScript({
                        param($url)
                        try {
                            $r = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 5
                            return @{ ok = $true; data = $r }
                        } catch {
                            return @{ ok = $false; error = $_.Exception.Message }
                        }
                    }).AddArgument($script:OllamaTagsUrl)
                    $script:DiagAsync = $script:DiagPs.BeginInvoke()
                    $script:DiagState = "waiting"
                }
                "waiting" {
                    if (-not $script:DiagAsync -or -not $script:DiagAsync.IsCompleted) { return }
                    $script:DiagSw.Stop()
                    try {
                        $r = $script:DiagPs.EndInvoke($script:DiagAsync)
                        try { $script:DiagPs.Dispose() } catch {}
                        $script:DiagPs = $null
                        if ($r.ok) {
                            $script:DiagLogBox.AppendText("            OK ($($script:DiagSw.ElapsedMilliseconds) ms)`r`n")
                            $script:DiagLogBox.AppendText("[Step 3/3] Parsing models list ... `r`n")
                            $models = $r.data.models
                            if ($models -and $models.Count -gt 0) {
                                $script:DiagLogBox.AppendText("            Found $($models.Count) model(s):`r`n")
                                foreach ($m in $models) {
                                    $script:DiagLogBox.AppendText("              - $($m.name)`r`n")
                                }
                            } else {
                                $script:DiagLogBox.AppendText("            No models found (try: ollama pull llama3.2:1b)`r`n")
                            }
                            $script:DiagLogBox.AppendText("`r`n>>> RESULT: Ollama is RUNNING and responding.`r`n")
                        } else {
                            $script:DiagLogBox.AppendText("            FAILED ($($script:DiagSw.ElapsedMilliseconds) ms)`r`n")
                            $script:DiagLogBox.AppendText("            Error: $($r.error)`r`n")
                            $script:DiagLogBox.AppendText("`r`n>>> RESULT: Port is open but HTTP failed. Ollama may be starting up.`r`n")
                        }
                    } catch {
                        $script:DiagLogBox.AppendText("            EXCEPTION: $($_.Exception.Message)`r`n")
                    }
                    $script:DiagLogBox.ScrollToEnd()
                    $script:DiagTimer.Stop()
                }
            }
        })
        $script:DiagTimer.Start()
    })

    $script:DiagWindow.Add_Closed({
        if ($script:DiagTimer) { $script:DiagTimer.Stop() }
        if ($script:DiagPs) {
            try { $script:DiagPs.Stop() } catch {}
            try { $script:DiagPs.Dispose() } catch {}
            $script:DiagPs = $null
        }
        $script:DiagWindow = $null
    })

    [void]$script:DiagWindow.ShowDialog()
}

# ==================== Event Wiring ====================

$script:SendButton.Add_Click({ Send-Message })
$script:InputBox.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Enter -and
        -not ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift)) {
        $e.Handled = $true
        Send-Message
    }
})
$script:StartOllamaBtn.Add_Click({ Start-OllamaServer })
$script:RefreshButton.Add_Click({ Show-Diagnostics })
$script:DirectionBtn.Add_Click({ Set-Direction (-not $script:IsRtl) })
$script:ExportButton.Add_Click({ Export-Chat })
$script:ClearButton.Add_Click({
    $script:ChatHistory.Clear()
    $script:ChatPanel.Children.Clear()
    Update-OllamaStatus | Out-Null
})
$script:ExitButton.Add_Click({ $script:Window.Close() })

$script:Window.Add_Loaded({
    Update-OllamaStatus | Out-Null
    $script:InputBox.Focus() | Out-Null
})

$script:Window.Add_Closing({
    if ($script:OllamaProcess -and -not $script:OllamaProcess.HasExited) {
        try { $script:OllamaProcess.Kill() } catch {}
    }
})

# ==================== Welcome & Show ====================

Add-MessageBubble -Sender "System" `
    -Text "Welcome. Type your message and press Enter to send (Shift+Enter for a new line). You can write in Arabic, English, or any language. Use 'Diagnostics' to check Ollama status step by step, and 'Direction' to switch layout direction." `
    -Color "#FFF8E1"

[void]$script:Window.ShowDialog()
