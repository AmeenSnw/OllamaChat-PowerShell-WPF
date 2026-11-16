Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Data

# ==================== App Paths ====================
$script:AppDataDir         = Join-Path $env:APPDATA "SnwOllamaChat"
$script:SettingsFile       = Join-Path $script:AppDataDir "settings.json"
$script:ConvosDir          = Join-Path $script:AppDataDir "conversations"
if (-not (Test-Path $script:AppDataDir)) { New-Item -ItemType Directory -Path $script:AppDataDir -Force | Out-Null }
if (-not (Test-Path $script:ConvosDir))  { New-Item -ItemType Directory -Path $script:ConvosDir  -Force | Out-Null }

# ==================== Configuration ====================
$script:OllamaHost             = "127.0.0.1"
$script:OllamaPort             = 11434
$script:OllamaChatUrl          = "http://127.0.0.1:11434/api/chat"
$script:OllamaTagsUrl          = "http://127.0.0.1:11434/api/tags"
$script:ModelName              = "llama3.2:1b"
$script:SystemPrompt           = "You are a helpful multilingual assistant. Always reply in the SAME language the user writes in. If the user writes in Arabic, answer in Arabic. Give clear, complete, and useful answers. Use Markdown tables and quotes when appropriate."

# Speed Settings
$script:SpeedPreset            = "Balanced"
$script:KeepAlive              = "-1"
$script:NumCtx                 = "2048"
$script:NumThread              = "0"

# Sampling Settings
$script:Temperature            = "0.7"
$script:TopP                   = "0.9"
$script:TopK                   = "40"
$script:RepeatPenalty          = "1.1"
$script:Seed                   = "-1"

# UI & Table Preferences
$script:TableRenderMode        = "FlowTable" # "FlowTable" or "DataGrid"
$script:MaxFileSizeMB          = 5

# Runtime
$script:OllamaProcess          = $null
$script:ChatHistory            = New-Object System.Collections.ArrayList
$script:SessionLog             = New-Object System.Collections.ArrayList
$script:AttachedFiles          = New-Object System.Collections.ArrayList
$script:AllBubbles             = New-Object System.Collections.ArrayList
$script:AvailableModels        = New-Object System.Collections.ArrayList
$script:IsBusy                 = $false
$script:IsRtl                  = $false
$script:IsDarkMode             = $false
$script:ClearKeepsContext      = $true
$script:ShowCodePreview        = $true
$script:SendWithCtrlEnter      = $false
$script:DiagWindow             = $null
$script:SettingsWindow         = $null
$script:StreamQueue            = $null
$script:StreamTimer            = $null
$script:ActiveAssistantBody    = $null
$script:ActiveAssistantRich    = $null
$script:ActiveAssistantEntry   = $null
$script:CurrentAssistantText   = ""
$script:UserIsScrollingUp      = $false

# ==================== Logging & Safety Helpers ====================
function Write-SessionLog {
    param([string]$Message, [string]$Level = "INFO")
    $time = Get-Date -Format "HH:mm:ss"
    $entry = "[$time] [$Level] $Message"
    [void]$script:SessionLog.Add($entry)
    $color = switch ($Level) { "ERROR" { "Red" } "WARN" { "Yellow" } default { "Cyan" } }
    Write-Host $entry -ForegroundColor $color
}

function Invoke-SafeShowDialog {
    param($WindowObject)
    if ($null -ne $WindowObject) {
        try { return $WindowObject.ShowDialog() }
        catch { Write-SessionLog "ShowDialog error: $($_.Exception.Message)" "ERROR" }
    }
    return $null
}

# ==================== Robust File Reader ====================
function Read-FileSafely {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return "" }
    try { return [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8) } catch {}
    try { return [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::Default) } catch {}
    try { return [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::Unicode) } catch { return "" }
}

# ==================== Settings Persistence ====================
function Save-AppSettings {
    try {
        $cfg = [ordered]@{
            OllamaHost        = $script:OllamaHost
            OllamaPort        = $script:OllamaPort
            ModelName         = $script:ModelName
            SystemPrompt      = $script:SystemPrompt
            SpeedPreset       = $script:SpeedPreset
            KeepAlive         = $script:KeepAlive
            NumCtx            = $script:NumCtx
            NumThread         = $script:NumThread
            Temperature       = $script:Temperature
            TopP              = $script:TopP
            TopK              = $script:TopK
            RepeatPenalty     = $script:RepeatPenalty
            Seed              = $script:Seed
            IsDarkMode        = $script:IsDarkMode
            IsRtl             = $script:IsRtl
            ShowCodePreview   = $script:ShowCodePreview
            ClearKeepsContext = $script:ClearKeepsContext
            SendWithCtrlEnter = $script:SendWithCtrlEnter
            TableRenderMode   = $script:TableRenderMode
        }
        $json = ($cfg | ConvertTo-Json -Depth 6)
        $tempPath = "$($script:SettingsFile).tmp"
        [System.IO.File]::WriteAllText($tempPath, $json, [System.Text.Encoding]::UTF8)
        if (Test-Path $tempPath) { Move-Item -Path $tempPath -Destination $script:SettingsFile -Force }
    } catch {
        Write-SessionLog "Failed to save settings: $($_.Exception.Message)" "ERROR"
    }
}

function Load-AppSettings {
    if (-not (Test-Path $script:SettingsFile)) { return }
    try {
        $raw = Read-FileSafely -FilePath $script:SettingsFile
        if ([string]::IsNullOrWhiteSpace($raw)) { return }
        $cfg = $raw | ConvertFrom-Json
        
        if ($cfg.OllamaHost)          { $script:OllamaHost = $cfg.OllamaHost }
        if ($cfg.OllamaPort)          { $script:OllamaPort = $cfg.OllamaPort }
        if ($cfg.ModelName)           { $script:ModelName = $cfg.ModelName }
        if ($cfg.SystemPrompt)        { $script:SystemPrompt = $cfg.SystemPrompt }
        if ($cfg.SpeedPreset)         { $script:SpeedPreset = $cfg.SpeedPreset }
        if ($cfg.KeepAlive)           { $script:KeepAlive = $cfg.KeepAlive }
        if ($cfg.NumCtx)              { $script:NumCtx = $cfg.NumCtx }
        if ($cfg.NumThread)           { $script:NumThread = $cfg.NumThread }
        if ($cfg.Temperature)         { $script:Temperature = $cfg.Temperature }
        if ($cfg.TopP)                { $script:TopP = $cfg.TopP }
        if ($cfg.TopK)                { $script:TopK = $cfg.TopK }
        if ($cfg.RepeatPenalty)       { $script:RepeatPenalty = $cfg.RepeatPenalty }
        if ($cfg.Seed)                { $script:Seed = $cfg.Seed }
        if ($cfg.TableRenderMode)     { $script:TableRenderMode = $cfg.TableRenderMode }
        if ($null -ne $cfg.IsDarkMode){ $script:IsDarkMode = [bool]$cfg.IsDarkMode }
        if ($null -ne $cfg.IsRtl)     { $script:IsRtl = [bool]$cfg.IsRtl }
        if ($null -ne $cfg.ShowCodePreview)  { $script:ShowCodePreview = [bool]$cfg.ShowCodePreview }
        if ($null -ne $cfg.ClearKeepsContext){ $script:ClearKeepsContext = [bool]$cfg.ClearKeepsContext }
        if ($null -ne $cfg.SendWithCtrlEnter){ $script:SendWithCtrlEnter = [bool]$cfg.SendWithCtrlEnter }

        $script:OllamaChatUrl = "http://$($script:OllamaHost):$($script:OllamaPort)/api/chat"
        $script:OllamaTagsUrl = "http://$($script:OllamaHost):$($script:OllamaPort)/api/tags"
    } catch {
        try {
            $bak = "$($script:SettingsFile).corrupted_$(Get-Date -Format 'yyyyMMddHHmmss')"
            Move-Item -Path $script:SettingsFile -Destination $bak -Force -ErrorAction SilentlyContinue
        } catch {}
    }
}

Load-AppSettings

# ==================== Main Window XAML ====================
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        x:Name="MainWindow"
        Title="Snw Ollama Chat" Height="820" Width="1200"
        FlowDirection="LeftToRight"
        WindowStartupLocation="CenterScreen"
        Background="#F5F5F5">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Menu Bar -->
        <Menu Grid.Row="0" Background="#E3F2FD" Padding="2" x:Name="MainMenu">
            <MenuItem Header="[File]">
                <MenuItem x:Name="NewChatButton"   Header="New Chat"/>
                <MenuItem x:Name="OpenChatButton"  Header="Open Conversation..."/>
                <MenuItem x:Name="SaveChatButton"  Header="Save Conversation..."/>
                <Separator/>
                <MenuItem x:Name="ExportButton"    Header="Export Chat (txt)..."/>
                <MenuItem x:Name="SaveLogButton"   Header="Save Session Log..."/>
                <Separator/>
                <MenuItem x:Name="ExitButton"      Header="Exit"/>
            </MenuItem>
            <MenuItem Header="[Ollama]">
                <MenuItem x:Name="StartOllamaButton" Header="Start Ollama Server"/>
                <MenuItem x:Name="RefreshButton"     Header="Diagnostics..."/>
                <MenuItem x:Name="ModelsMenuButton"  Header="Manage Models..."/>
            </MenuItem>
            <MenuItem Header="[Settings]">
                <MenuItem x:Name="SettingsButton" Header="Configuration..."/>
                <MenuItem x:Name="ThemeButton"    Header="Toggle Dark/Light Theme"/>
                <MenuItem x:Name="DirectionButton" Header="Toggle Text Direction (LTR/RTL)"/>
                <MenuItem x:Name="CodePreviewMenuButton" Header="Toggle Preview Pane"/>
            </MenuItem>
            <MenuItem Header="[Clear]" x:Name="ClearButton" ToolTip="Clear chat based on Settings preference"/>
        </Menu>

        <!-- Main Content -->
        <Grid x:Name="MainContentGrid" Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*" />
                <ColumnDefinition Width="5" />
                <ColumnDefinition Width="480" />
            </Grid.ColumnDefinitions>

            <Border x:Name="ChatContainerBorder" Grid.Column="0" BorderBrush="#CCCCCC" BorderThickness="1,0,1,1"
                    Background="White" Padding="8" Margin="0,0,0,0" AllowDrop="True">
                <ScrollViewer x:Name="ChatScroll" VerticalScrollBarVisibility="Auto">
                    <StackPanel x:Name="ChatPanel"/>
                </ScrollViewer>
            </Border>

            <GridSplitter x:Name="MainSplitter" Grid.Column="1" Width="5" HorizontalAlignment="Stretch" Background="#E0E0E0" ShowsPreview="True" />

            <Border x:Name="CodePreviewBorder" Grid.Column="2" BorderBrush="#CCCCCC" BorderThickness="1,0,1,1"
                    Background="#F8F9FA" Padding="8" Margin="0,0,0,0">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <Grid Grid.Row="0" Margin="0,0,0,5">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Grid.Column="0" Text="Smart Preview (Code &amp; Embedded Web)" FontWeight="Bold" Foreground="#555555" VerticalAlignment="Center"/>
                        <StackPanel Grid.Column="1" Orientation="Horizontal">
                            <Button x:Name="ViewSourceBtn" Content="Code" Width="55" Height="22" Margin="0,0,4,0" FontSize="11" Background="#2A6FDB" Foreground="White" BorderThickness="0"/>
                            <Button x:Name="ViewWebBtn"    Content="Web Preview" Width="85" Height="22" FontSize="11" Background="#E0E0E0" Foreground="#333333" BorderThickness="0"/>
                        </StackPanel>
                    </Grid>
                    <TabControl x:Name="CodePreviewTabs" Grid.Row="1" Background="White" BorderThickness="1" BorderBrush="#CCCCCC"/>
                    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,8,0,0">
                        <Button x:Name="OpenPreviewButton" Content="External" Width="80" Height="26" Margin="0,0,6,0" Background="#E0E0E0" BorderThickness="0" ToolTip="Open in external browser/notepad"/>
                        <Button x:Name="SavePreviewButton" Content="Save" Width="80" Height="26" Margin="0,0,6,0" Background="#E0E0E0" BorderThickness="0"/>
                        <Button x:Name="SaveAllButton"     Content="Save All" Width="90" Height="26" Background="#E0E0E0" BorderThickness="0"/>
                    </StackPanel>
                </Grid>
            </Border>
        </Grid>

        <!-- Input Area -->
        <StackPanel Grid.Row="2" Margin="10,8,10,8">
            <Border x:Name="FileIndicatorBorder" Background="#E8F5E9" CornerRadius="4" Padding="6,4" Margin="0,0,0,4" Visibility="Collapsed">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock x:Name="FileIndicatorText" Grid.Column="0" Text="" VerticalAlignment="Center" FontSize="12" Foreground="#2E7D32" TextTrimming="CharacterEllipsis"/>
                    <Button x:Name="RemoveFileButton" Grid.Column="1" Content="X" Width="22" Height="22" Background="Transparent" BorderThickness="0" Foreground="#C62828" FontWeight="Bold" Cursor="Hand" ToolTip="Remove all attachments"/>
                </Grid>
            </Border>
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBox x:Name="InputBox" Grid.Column="0" Height="70" Padding="6"
                         TextWrapping="Wrap" AcceptsReturn="True" AllowDrop="True"
                         VerticalScrollBarVisibility="Auto" FontSize="14"/>
                <Button x:Name="AttachButton" Grid.Column="1" Content="Attach" Width="85" Height="70" Margin="8,0,0,0"
                        FontSize="13" Background="#E0E0E0" Foreground="#333333" BorderThickness="0"/>
                <Button x:Name="SendButton"   Grid.Column="2" Content="Send"   Width="85" Height="70" Margin="8,0,0,0"
                        FontSize="14" FontWeight="Bold" Background="#2A6FDB" Foreground="White" BorderThickness="0"/>
                <Button x:Name="StopButton"   Grid.Column="3" Content="Stop"   Width="85" Height="70" Margin="8,0,0,0"
                        FontSize="14" FontWeight="Bold" Background="#D9534F" Foreground="White" BorderThickness="0" IsEnabled="False"/>
            </Grid>
        </StackPanel>

        <!-- Status Bar -->
        <Border Grid.Row="3" Background="#EAEAEA" Padding="8,4" BorderBrush="#CCCCCC" BorderThickness="0,1,0,0">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Ellipse x:Name="StatusDot" Grid.Column="0" Width="10" Height="10" Fill="Gray" VerticalAlignment="Center" Margin="0,0,6,0"/>
                <TextBlock x:Name="StatusLabel" Grid.Column="1" Text="Checking..." VerticalAlignment="Center" FontSize="12" Foreground="#333333"/>
                <TextBlock x:Name="StatsLabel"  Grid.Column="2" Text="" VerticalAlignment="Center" FontSize="11" Foreground="#666666" Margin="0,0,10,0"/>
                <TextBlock x:Name="ModelLabel"  Grid.Column="3" Text="model" VerticalAlignment="Center" FontWeight="Bold" FontSize="12" Foreground="#2A6FDB"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

try {
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $script:Window = [Windows.Markup.XamlReader]::Load($reader)
} catch {
    [System.Windows.MessageBox]::Show("XAML Error: $($_.Exception.Message)", "Fatal Error")
    exit
}

# Store UI Elements
$script:MainContentGrid     = $script:Window.FindName("MainContentGrid")
$script:ChatContainerBorder = $script:Window.FindName("ChatContainerBorder")
$script:CodePreviewBorder   = $script:Window.FindName("CodePreviewBorder")
$script:MainSplitter        = $script:Window.FindName("MainSplitter")
$script:CodePreviewTabs     = $script:Window.FindName("CodePreviewTabs")
$script:ViewSourceBtn       = $script:Window.FindName("ViewSourceBtn")
$script:ViewWebBtn          = $script:Window.FindName("ViewWebBtn")
$script:ChatPanel           = $script:Window.FindName("ChatPanel")
$script:ChatScroll          = $script:Window.FindName("ChatScroll")
$script:InputBox            = $script:Window.FindName("InputBox")
$script:SendButton          = $script:Window.FindName("SendButton")
$script:StopButton          = $script:Window.FindName("StopButton")
$script:AttachButton        = $script:Window.FindName("AttachButton")
$script:FileIndicatorBorder = $script:Window.FindName("FileIndicatorBorder")
$script:FileIndicatorText   = $script:Window.FindName("FileIndicatorText")
$script:RemoveFileButton    = $script:Window.FindName("RemoveFileButton")
$script:StatusLabel         = $script:Window.FindName("StatusLabel")
$script:StatusDot           = $script:Window.FindName("StatusDot")
$script:StatsLabel          = $script:Window.FindName("StatsLabel")
$script:ModelLabel          = $script:Window.FindName("ModelLabel")
$script:StartOllamaBtn      = $script:Window.FindName("StartOllamaButton")
$script:RefreshButton       = $script:Window.FindName("RefreshButton")
$script:ModelsMenuButton    = $script:Window.FindName("ModelsMenuButton")
$script:SettingsButton      = $script:Window.FindName("SettingsButton")
$script:ThemeButton         = $script:Window.FindName("ThemeButton")
$script:DirectionBtn        = $script:Window.FindName("DirectionButton")
$script:CodePreviewMenuBtn  = $script:Window.FindName("CodePreviewMenuButton")
$script:ExportButton        = $script:Window.FindName("ExportButton")
$script:SaveLogButton       = $script:Window.FindName("SaveLogButton")
$script:NewChatButton       = $script:Window.FindName("NewChatButton")
$script:OpenChatButton      = $script:Window.FindName("OpenChatButton")
$script:SaveChatButton      = $script:Window.FindName("SaveChatButton")
$script:ClearButton         = $script:Window.FindName("ClearButton")
$script:ExitButton          = $script:Window.FindName("ExitButton")
$script:OpenPreviewButton   = $script:Window.FindName("OpenPreviewButton")
$script:SavePreviewButton   = $script:Window.FindName("SavePreviewButton")
$script:SaveAllButton       = $script:Window.FindName("SaveAllButton")

$script:ModelLabel.Text = $script:ModelName
$script:DirectionBtn.Header = if ($script:IsRtl) { "Toggle Text Direction (Currently: RTL)" } else { "Toggle Text Direction (Currently: LTR)" }
$script:ThemeButton.Header  = if ($script:IsDarkMode) { "Toggle Theme (Currently: Dark)" } else { "Toggle Theme (Currently: Light)" }

# ==================== Smart Scroll Tracking ====================
$script:ChatScroll.Add_ScrollChanged({
    param($s, $e)
    # If user scrolls up significantly away from the bottom (e.g., more than 40 pixels), lock manual override
    if ($s.VerticalOffset -lt ($s.ScrollableHeight - 30)) {
        $script:UserIsScrollingUp = $true
    } else {
        $script:UserIsScrollingUp = $false
    }
})

# ==================== Helpers ====================
function Brush([string]$hex) { return [System.Windows.Media.BrushConverter]::new().ConvertFromString($hex) }

function Test-OllamaPort {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $task = $client.ConnectAsync($script:OllamaHost, [int]$script:OllamaPort)
            if (-not $task.Wait(200)) { return $false }
            return ($task.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion)
        } finally { $client.Dispose() }
    } catch { return $false }
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
    $script:ModelLabel.Text = $script:ModelName
}

function Update-OllamaStatus {
    if (Test-OllamaPort) {
        Set-StatusUi "running" "Ollama is running at $($script:OllamaHost):$($script:OllamaPort)"
        $script:StartOllamaBtn.IsEnabled = $false
        return $true
    } else {
        Set-StatusUi "stopped" "Ollama is stopped"
        $script:StartOllamaBtn.IsEnabled = $true
        return $false
    }
}

function Show-OpenFileDialog {
    param([string]$Message, [string]$FilePath)
    $result = [System.Windows.MessageBox]::Show("$Message`n`nOpen now?", "Success",
        [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Information)
    if ($result -eq [System.Windows.MessageBoxResult]::Yes) { Start-Process $FilePath }
}

# ==================== Markdown Rich Text ====================
function Add-MarkdownInlines {
    param($paragraph, [string]$text, [bool]$isDark)
    if ([string]::IsNullOrEmpty($text)) { return }
    $i = 0; $len = $text.Length
    $codeBg = if ($isDark) { "#3A3A3A" } else { "#EEEEEE" }
    while ($i -lt $len) {
        $c = $text[$i]
        if ($c -eq "`n") { [void]$paragraph.Inlines.Add((New-Object System.Windows.Documents.LineBreak)); $i++; continue }
        if ($c -eq "`r") { $i++; continue }

        if ($i + 1 -lt $len -and $text[$i] -eq '*' -and $text[$i+1] -eq '*') {
            $end = $text.IndexOf('**', $i + 2)
            if ($end -gt 0) {
                $run = New-Object System.Windows.Documents.Run($text.Substring($i + 2, $end - $i - 2))
                $run.FontWeight = "Bold"
                [void]$paragraph.Inlines.Add($run)
                $i = $end + 2; continue
            }
        }
        if ($c -eq '`') {
            $end = $text.IndexOf('`', $i + 1)
            if ($end -gt 0) {
                $run = New-Object System.Windows.Documents.Run($text.Substring($i + 1, $end - $i - 1))
                $run.FontFamily = "Consolas"
                $run.Background = Brush $codeBg
                [void]$paragraph.Inlines.Add($run)
                $i = $end + 1; continue
            }
        }
        if ($c -eq '*') {
            $end = $text.IndexOf('*', $i + 1)
            if ($end -gt 0) {
                $run = New-Object System.Windows.Documents.Run($text.Substring($i + 1, $end - $i - 1))
                $run.FontStyle = "Italic"
                [void]$paragraph.Inlines.Add($run)
                $i = $end + 1; continue
            }
        }
        $next = $i + 1
        while ($next -lt $len -and -not ($text[$next] -in @('*', '`', "`n", "`r"))) { $next++ }
        [void]$paragraph.Inlines.Add((New-Object System.Windows.Documents.Run($text.Substring($i, $next - $i))))
        $i = $next
    }
}

function New-FormattedRichTextBox {
    param([string]$Text, [bool]$IsDark)
    $rtb = New-Object System.Windows.Controls.RichTextBox
    $rtb.IsReadOnly = $true
    $rtb.Background = [System.Windows.Media.Brushes]::Transparent
    $rtb.BorderThickness = New-Object System.Windows.Thickness(0)
    $rtb.Padding = New-Object System.Windows.Thickness(0)
    $rtb.Margin = New-Object System.Windows.Thickness(0, 2, 0, 2)
    $rtb.FontSize = 14
    $rtb.VerticalScrollBarVisibility = "Disabled"
    $rtb.HorizontalScrollBarVisibility = "Disabled"
    $rtb.IsDocumentEnabled = $true
    $rtb.Foreground = if ($IsDark) { Brush "#FFFFFF" } else { Brush "#111111" }
    $rtb.Document = New-Object System.Windows.Documents.FlowDocument
    $rtb.Document.PagePadding = New-Object System.Windows.Thickness(0)

    $par = New-Object System.Windows.Documents.Paragraph
    $par.Margin = New-Object System.Windows.Thickness(0)
    if (-not [string]::IsNullOrEmpty($Text)) {
        Add-MarkdownInlines -paragraph $par -text $Text -isDark $IsDark
    }
    [void]$rtb.Document.Blocks.Add($par)
    return $rtb
}

# ==================== Table Parsing & Dual In-Chat Widgets ====================
function Parse-MarkdownTableRows {
    param([string]$md)
    $rowsList = @()
    try {
        $lines = @($md -split "`r?`n")
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -match '^[\s\|:-]+$') { continue }
            $safeLine = $line.Replace('*', '').Trim()
            if (-not $safeLine.StartsWith('|')) { $safeLine = '|' + $safeLine }
            if (-not $safeLine.EndsWith('|')) { $safeLine = $safeLine + '|' }
            $rawCells = @($safeLine.Split('|'))
            if ($rawCells.Count -ge 3) {
                $cells = @()
                for ($k = 1; $k -lt ($rawCells.Count - 1); $k++) {
                    $cells += $rawCells[$k].Trim()
                }
                if ($cells.Count -gt 0) { $rowsList += , $cells }
            }
        }
    } catch {}
    return , $rowsList
}

function New-InChatCodeWidget {
    param([string]$Lang, [string]$Code, [bool]$IsDark)
    $outer = New-Object System.Windows.Controls.Border
    $outer.FlowDirection = "LeftToRight"
    $outer.CornerRadius = [System.Windows.CornerRadius]::new(6)
    $outer.BorderThickness = [System.Windows.Thickness]::new(1)
    $outer.Margin = [System.Windows.Thickness]::new(0, 6, 0, 6)
    $outer.Background = if ($IsDark) { Brush "#181818" } else { Brush "#F4F6F8" }
    $outer.BorderBrush = if ($IsDark) { Brush "#3E3E42" } else { Brush "#D0D7DE" }

    $sp = New-Object System.Windows.Controls.StackPanel

    $topBar = New-Object System.Windows.Controls.Border
    $topBar.Background = if ($IsDark) { Brush "#252526" } else { Brush "#E6EBF1" }
    $topBar.Padding = [System.Windows.Thickness]::new(8, 3, 8, 3)
    $topBar.CornerRadius = [System.Windows.CornerRadius]::new(5, 5, 0, 0)

    $grid = New-Object System.Windows.Controls.Grid
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = "*"
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = "Auto"
    [void]$grid.ColumnDefinitions.Add($c1)
    [void]$grid.ColumnDefinitions.Add($c2)

    $langLbl = New-Object System.Windows.Controls.TextBlock
    $langLbl.Text = if ([string]::IsNullOrWhiteSpace($Lang)) { "code" } else { $Lang }
    $langLbl.FontFamily = "Consolas"
    $langLbl.FontSize = 11
    $langLbl.FontWeight = "Bold"
    $langLbl.Foreground = if ($IsDark) { Brush "#9CDCFE" } else { Brush "#0969DA" }
    $langLbl.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($langLbl, 0)
    [void]$grid.Children.Add($langLbl)

    $copyCodeBtn = New-Object System.Windows.Controls.Button
    $copyCodeBtn.Content = "[Copy Code]"
    $copyCodeBtn.FontSize = 10
    $copyCodeBtn.Padding = [System.Windows.Thickness]::new(4, 1, 4, 1)
    $copyCodeBtn.Background = [System.Windows.Media.Brushes]::Transparent
    $copyCodeBtn.BorderThickness = [System.Windows.Thickness]::new(0)
    $copyCodeBtn.Foreground = if ($IsDark) { Brush "#CCCCCC" } else { Brush "#444444" }
    $copyCodeBtn.Cursor = "Hand"
    $copyCodeBtn.Tag = $Code
    $copyCodeBtn.Add_Click({
        param($s, $e)
        $e.Handled = $true
        try {
            if ($s.Tag) { [System.Windows.Clipboard]::SetText($s.Tag) | Out-Null }
            $s.Content = "[Copied!]"
        } catch {}
    })
    [System.Windows.Controls.Grid]::SetColumn($copyCodeBtn, 1)
    [void]$grid.Children.Add($copyCodeBtn)

    $topBar.Child = $grid
    [void]$sp.Children.Add($topBar)

    $codeTb = New-Object System.Windows.Controls.TextBox
    $codeTb.Text = $Code
    $codeTb.FontFamily = "Consolas"
    $codeTb.FontSize = 13
    $codeTb.IsReadOnly = $true
    $codeTb.BorderThickness = [System.Windows.Thickness]::new(0)
    $codeTb.Background = [System.Windows.Media.Brushes]::Transparent
    $codeTb.Foreground = if ($IsDark) { Brush "#D4D4D4" } else { Brush "#1F2328" }
    $codeTb.Padding = [System.Windows.Thickness]::new(8)
    $codeTb.HorizontalScrollBarVisibility = "Auto"
    $codeTb.VerticalScrollBarVisibility = "Disabled"
    $codeTb.TextWrapping = "NoWrap"
    [void]$sp.Children.Add($codeTb)

    $outer.Child = $sp
    return $outer
}

function New-InChatTableWidget {
    param([string]$MarkdownTable, [bool]$IsDark)
    $rows = Parse-MarkdownTableRows -md $MarkdownTable
    if ($rows.Count -eq 0) {
        return (New-FormattedRichTextBox -Text $MarkdownTable -IsDark $IsDark)
    }

    if ($script:TableRenderMode -eq "DataGrid") {
        try {
            $dt = New-Object System.Data.DataTable
            $headers = @($rows[0])
            for ($c = 0; $c -lt $headers.Count; $c++) {
                $colName = if ([string]::IsNullOrWhiteSpace($headers[$c])) { "Col$($c+1)" } else { $headers[$c] }
                $uniqueName = $colName; $idx = 1
                while ($dt.Columns.Contains($uniqueName)) { $uniqueName = "$colName ($idx)"; $idx++ }
                [void]$dt.Columns.Add($uniqueName)
            }
            for ($r = 1; $r -lt $rows.Count; $r++) {
                $dr = $dt.NewRow()
                $cellVals = @($rows[$r])
                for ($c = 0; $c -lt $dt.Columns.Count; $c++) {
                    $dr[$c] = if ($c -lt $cellVals.Count) { $cellVals[$c] } else { "" }
                }
                [void]$dt.Rows.Add($dr)
            }

            $dg = New-Object System.Windows.Controls.DataGrid
            $dg.ItemsSource = $dt.DefaultView
            $dg.IsReadOnly = $true
            $dg.AutoGenerateColumns = $true
            $dg.CanUserAddRows = $false
            $dg.CanUserDeleteRows = $false
            $dg.CanUserSortColumns = $true
            $dg.HeadersVisibility = "Column"
            $dg.GridLinesVisibility = "All"
            $dg.Margin = [System.Windows.Thickness]::new(0, 6, 0, 6)
            $dg.FontSize = 13
            $dg.MaxHeight = 320
            $dg.Background = if ($IsDark) { Brush "#1E1E1E" } else { Brush "#FFFFFF" }
            $dg.Foreground = if ($IsDark) { Brush "#E0E0E0" } else { Brush "#111111" }
            $dg.RowBackground = if ($IsDark) { Brush "#252526" } else { Brush "#FFFFFF" }
            $dg.AlternatingRowBackground = if ($IsDark) { Brush "#2D2D30" } else { Brush "#F4F6F8" }
            $dg.HorizontalGridLinesBrush = if ($IsDark) { Brush "#444444" } else { Brush "#D0D7DE" }
            $dg.VerticalGridLinesBrush = if ($IsDark) { Brush "#444444" } else { Brush "#D0D7DE" }
            return $dg
        } catch {}
    }

    $rtb = New-Object System.Windows.Controls.RichTextBox
    $rtb.IsReadOnly = $true
    $rtb.Background = [System.Windows.Media.Brushes]::Transparent
    $rtb.BorderThickness = New-Object System.Windows.Thickness(0)
    $rtb.Padding = New-Object System.Windows.Thickness(0)
    $rtb.Margin = New-Object System.Windows.Thickness(0, 6, 0, 6)
    $rtb.FontSize = 13
    $rtb.VerticalScrollBarVisibility = "Disabled"
    $rtb.HorizontalScrollBarVisibility = "Auto"
    $rtb.Document = New-Object System.Windows.Documents.FlowDocument
    $rtb.Document.PagePadding = New-Object System.Windows.Thickness(0)

    $table = New-Object System.Windows.Documents.Table
    $table.CellSpacing = 0
    $table.BorderBrush = if ($IsDark) { Brush "#555555" } else { Brush "#B0BEC5" }
    $table.BorderThickness = New-Object System.Windows.Thickness(1)

    $colCount = $rows[0].Count
    for ($c = 0; $c -lt $colCount; $c++) {
        $col = New-Object System.Windows.Documents.TableColumn
        [void]$table.Columns.Add($col)
    }

    $trg = New-Object System.Windows.Documents.TableRowGroup
    for ($r = 0; $r -lt $rows.Count; $r++) {
        $tr = New-Object System.Windows.Documents.TableRow
        if ($r -eq 0) {
            $tr.Background = if ($IsDark) { Brush "#2D3748" } else { Brush "#E2E8F0" }
            $tr.FontWeight = "Bold"
        } elseif ($r % 2 -eq 0) {
            $tr.Background = if ($IsDark) { Brush "#252526" } else { Brush "#F8FAFC" }
        } else {
            $tr.Background = if ($IsDark) { Brush "#1E1E1E" } else { Brush "#FFFFFF" }
        }

        $cells = @($rows[$r])
        for ($c = 0; $c -lt $colCount; $c++) {
            $val = if ($c -lt $cells.Count) { $cells[$c] } else { "" }
            $p = New-Object System.Windows.Documents.Paragraph((New-Object System.Windows.Documents.Run($val)))
            $p.Margin = New-Object System.Windows.Thickness(0)
            $p.Foreground = if ($IsDark) { Brush "#F1F5F9" } else { Brush "#0F172A" }

            $tc = New-Object System.Windows.Documents.TableCell($p)
            $tc.Padding = New-Object System.Windows.Thickness(8, 5, 8, 5)
            $tc.BorderBrush = if ($IsDark) { Brush "#444444" } else { Brush "#CBD5E1" }
            $tc.BorderThickness = New-Object System.Windows.Thickness(0.5)
            [void]$tr.Cells.Add($tc)
        }
        [void]$trg.Rows.Add($tr)
    }
    [void]$table.RowGroups.Add($trg)
    [void]$rtb.Document.Blocks.Add($table)
    return $rtb
}

# ==================== Segmented Bubble Renderer ====================
function Render-SegmentedMessage {
    param([System.Windows.Controls.StackPanel]$BodyPanel, [string]$Text, [bool]$IsDark)
    if ($null -eq $BodyPanel) { return }
    $BodyPanel.Children.Clear()

    if ([string]::IsNullOrEmpty($Text)) {
        [void]$BodyPanel.Children.Add((New-FormattedRichTextBox -Text "" -IsDark $IsDark))
        return
    }

    try {
        $matchesList = New-Object System.Collections.ArrayList

        $codeRegex = [regex]'(?s)```([a-zA-Z0-9+#-]*)?\r?\n(.*?)\r?\n?```'
        foreach ($m in $codeRegex.Matches($Text)) {
            [void]$matchesList.Add([PSCustomObject]@{
                Start = $m.Index
                Length = $m.Length
                Type = "Code"
                Lang = $m.Groups[1].Value.Trim()
                Content = $m.Groups[2].Value
            })
        }

        $tableRegex = [regex]'(?m)^[\t ]*\|.+\|[\t ]*\r?\n[\t ]*\|[\s\-:|]+\|[\t ]*\r?\n((?:^[\t ]*\|.+\|[\t ]*\r?\n?)*)'
        foreach ($m in $tableRegex.Matches($Text)) {
            $overlaps = $false
            foreach ($cm in $matchesList) {
                if ($m.Index -ge $cm.Start -and $m.Index -lt ($cm.Start + $cm.Length)) {
                    $overlaps = $true; break
                }
            }
            if (-not $overlaps) {
                [void]$matchesList.Add([PSCustomObject]@{
                    Start = $m.Index
                    Length = $m.Length
                    Type = "Table"
                    Lang = ""
                    Content = $m.Value.Trim()
                })
            }
        }

        $sorted = @($matchesList | Sort-Object Start)
        $cursor = 0

        foreach ($seg in $sorted) {
            if ($seg.Start -gt $cursor) {
                $beforeText = $Text.Substring($cursor, $seg.Start - $cursor).Trim("`r", "`n")
                if (-not [string]::IsNullOrWhiteSpace($beforeText)) {
                    [void]$BodyPanel.Children.Add((New-FormattedRichTextBox -Text $beforeText -IsDark $IsDark))
                }
            }

            if ($seg.Type -eq "Code") {
                [void]$BodyPanel.Children.Add((New-InChatCodeWidget -Lang $seg.Lang -Code $seg.Content -IsDark $IsDark))
            } elseif ($seg.Type -eq "Table") {
                [void]$BodyPanel.Children.Add((New-InChatTableWidget -MarkdownTable $seg.Content -IsDark $IsDark))
            }

            $cursor = $seg.Start + $seg.Length
        }

        if ($cursor -lt $Text.Length) {
            $afterText = $Text.Substring($cursor).Trim("`r", "`n")
            if (-not [string]::IsNullOrWhiteSpace($afterText)) {
                [void]$BodyPanel.Children.Add((New-FormattedRichTextBox -Text $afterText -IsDark $IsDark))
            }
        }
    } catch {
        $BodyPanel.Children.Clear()
        [void]$BodyPanel.Children.Add((New-FormattedRichTextBox -Text $Text -IsDark $IsDark))
    }
}

# ==================== Bubble Builder ====================
function New-MessageBubble {
    param(
        [string]$Sender,
        [string]$Text,
        [string]$LightColor,
        [string]$DarkColor,
        [hashtable]$Entry = $null,
        [string]$Role = ""
    )
    $border = New-Object System.Windows.Controls.Border
    $colorHex = if ($script:IsDarkMode) { $DarkColor } else { $LightColor }
    $border.Background = Brush $colorHex
    $border.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $border.Padding = [System.Windows.Thickness]::new(10, 6, 10, 6)
    $border.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)

    $outerStack = New-Object System.Windows.Controls.StackPanel

    $headerRow = New-Object System.Windows.Controls.StackPanel
    $headerRow.Orientation = "Horizontal"
    $headerRow.Margin = New-Object System.Windows.Thickness(0, 0, 0, 2)

    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Text = $Sender
    $lbl.FontWeight = "Bold"
    $lbl.FontSize = 12
    $lbl.Foreground = if ($script:IsDarkMode) { Brush "#BBBBBB" } else { Brush "#333333" }
    $lbl.VerticalAlignment = "Center"
    [void]$headerRow.Children.Add($lbl)

    $bodyPanel = New-Object System.Windows.Controls.StackPanel

    $btnCopy = New-Object System.Windows.Controls.Button
    $btnCopy.Content = "[Copy]"
    $btnCopy.Width = 45; $btnCopy.Height = 20
    $btnCopy.Margin = New-Object System.Windows.Thickness(6, 0, 0, 0)
    $btnCopy.Background = [System.Windows.Media.Brushes]::Transparent
    $btnCopy.BorderThickness = New-Object System.Windows.Thickness(0)
    $btnCopy.Foreground = if ($script:IsDarkMode) { Brush "#AAAAAA" } else { Brush "#555555" }
    $btnCopy.Cursor = "Hand"
    $btnCopy.ToolTip = "Copy full message"
    $btnCopy.FontSize = 10
    $btnCopy.Tag = @{ Entry = $Entry; Fallback = $Text }
    $btnCopy.Add_Click({
        param($s, $e)
        $e.Handled = $true
        try {
            $data = $s.Tag
            $copyText = if ($data.Entry -and $data.Entry.content) { $data.Entry.content } else { $data.Fallback }
            if (-not [string]::IsNullOrEmpty($copyText)) {
                [System.Windows.Clipboard]::SetText($copyText) | Out-Null
            }
        } catch {}
    })
    [void]$headerRow.Children.Add($btnCopy)

    if ($null -ne $Entry) {
        if ($Role -eq "assistant") {
            $btnRegen = New-Object System.Windows.Controls.Button
            $btnRegen.Content = "[Regen]"
            $btnRegen.Width = 48; $btnRegen.Height = 20
            $btnRegen.Margin = New-Object System.Windows.Thickness(4, 0, 0, 0)
            $btnRegen.Background = [System.Windows.Media.Brushes]::Transparent
            $btnRegen.BorderThickness = New-Object System.Windows.Thickness(0)
            $btnRegen.Foreground = if ($script:IsDarkMode) { Brush "#AAAAAA" } else { Brush "#555555" }
            $btnRegen.Cursor = "Hand"
            $btnRegen.FontSize = 10
            $btnRegen.ToolTip = "Regenerate response"
            $btnRegen.Tag = $Entry
            $btnRegen.Add_Click({
                param($s, $e)
                $e.Handled = $true
                try {
                    if ($script:IsBusy) { return }
                    $targetEntry = $s.Tag
                    if ($null -eq $targetEntry) { return }

                    $idx = -1
                    for ($i = 0; $i -lt $script:ChatHistory.Count; $i++) {
                        if ([object]::ReferenceEquals($script:ChatHistory[$i], $targetEntry)) { $idx = $i; break }
                    }
                    if ($idx -lt 0) { return }

                    $uIdx = -1
                    for ($k = $idx - 1; $k -ge 0; $k--) {
                        if ($script:ChatHistory[$k].role -eq "user") { $uIdx = $k; break }
                    }
                    if ($uIdx -lt 0) { return }

                    $userMsg = $script:ChatHistory[$uIdx]
                    while ($script:ChatHistory.Count -gt $uIdx) {
                        $script:ChatHistory.RemoveAt($script:ChatHistory.Count - 1)
                    }
                    Rebuild-ChatUI
                    $disp = if ($userMsg.display) { $userMsg.display } else { $userMsg.content }
                    Send-ChatMessage -UserEntry $userMsg -DisplayText $disp
                } catch {}
            })
            [void]$headerRow.Children.Add($btnRegen)

        } elseif ($Role -eq "user") {
            $btnEdit = New-Object System.Windows.Controls.Button
            $btnEdit.Content = "[Edit]"
            $btnEdit.Width = 38; $btnEdit.Height = 20
            $btnEdit.Margin = New-Object System.Windows.Thickness(4, 0, 0, 0)
            $btnEdit.Background = [System.Windows.Media.Brushes]::Transparent
            $btnEdit.BorderThickness = New-Object System.Windows.Thickness(0)
            $btnEdit.Foreground = if ($script:IsDarkMode) { Brush "#AAAAAA" } else { Brush "#555555" }
            $btnEdit.Cursor = "Hand"
            $btnEdit.FontSize = 10
            $btnEdit.ToolTip = "Edit and Resend"
            $btnEdit.Tag = $Entry
            $btnEdit.Add_Click({
                param($s, $e)
                $e.Handled = $true
                try {
                    if ($script:IsBusy) { return }
                    $targetEntry = $s.Tag
                    if ($null -eq $targetEntry) { return }

                    $idx = -1
                    for ($i = 0; $i -lt $script:ChatHistory.Count; $i++) {
                        if ([object]::ReferenceEquals($script:ChatHistory[$i], $targetEntry)) { $idx = $i; break }
                    }
                    if ($idx -lt 0) { return }

                    while ($script:ChatHistory.Count -gt $idx) {
                        $script:ChatHistory.RemoveAt($script:ChatHistory.Count - 1)
                    }
                    Rebuild-ChatUI
                    $editContent = if ($targetEntry.ContainsKey("display") -and -not [string]::IsNullOrEmpty($targetEntry.display)) {
                        $targetEntry.display
                    } else {
                        $targetEntry.content
                    }
                    $script:InputBox.Text = $editContent
                    $script:InputBox.CaretIndex = $script:InputBox.Text.Length
                    $script:InputBox.Focus() | Out-Null
                } catch {}
            })
            [void]$headerRow.Children.Add($btnEdit)
        }
    }

    [void]$outerStack.Children.Add($headerRow)
    [void]$outerStack.Children.Add($bodyPanel)
    $border.Child = $outerStack
    [void]$script:ChatPanel.Children.Add($border)

    if ($Role -eq "assistant" -and -not [string]::IsNullOrEmpty($Text)) {
        Render-SegmentedMessage -BodyPanel $bodyPanel -Text $Text -IsDark $script:IsDarkMode
        $rtb = $null
    } else {
        $rtb = New-FormattedRichTextBox -Text $Text -IsDark $script:IsDarkMode
        [void]$bodyPanel.Children.Add($rtb)
    }

    if (-not $script:UserIsScrollingUp) {
        $script:ChatScroll.ScrollToEnd()
    }

    if ($Sender -eq "Assistant") {
        $border.Cursor = [System.Windows.Input.Cursors]::Hand
        $border.Tag = @{ BodyPanel = $bodyPanel; Entry = $Entry; RawText = $Text }
        $border.BorderBrush = "Transparent"
        $border.BorderThickness = 0

        $border.Add_MouseLeftButtonDown({
            param($s, $e)
            $src = $e.OriginalSource
            while ($src -and $src -ne $s) {
                if ($src -is [System.Windows.Controls.Primitives.ButtonBase] -or $src -is [System.Windows.Controls.DataGrid]) { return }
                try { $src = [System.Windows.Media.VisualTreeHelper]::GetParent($src) } catch { break }
            }
            if ($script:IsBusy) { return }
            try {
                foreach ($b in $script:AllBubbles) {
                    if ($b -is [System.Windows.Controls.Border]) {
                        $b.BorderBrush = "Transparent"; $b.BorderThickness = 0
                    }
                }
                $s.BorderBrush = Brush "#2A6FDB"
                $s.BorderThickness = 2
                
                $bubbleData = $s.Tag
                $rawMd = if ($bubbleData.Entry -and $bubbleData.Entry.content) { $bubbleData.Entry.content } else { $bubbleData.RawText }
                if (-not [string]::IsNullOrWhiteSpace($rawMd)) {
                    Extract-CodePreview -Text $rawMd
                }
            } catch {}
        })
        [void]$script:AllBubbles.Add($border)
    }

    return @{ Border = $border; BodyPanel = $bodyPanel; RichTextBox = $rtb }
}

# ==================== Direction / Theme ====================
function Set-Direction {
    param([bool]$Rtl)
    $script:IsRtl = $Rtl
    if ($Rtl) {
        $script:ChatPanel.FlowDirection = "RightToLeft"
        $script:InputBox.FlowDirection = "RightToLeft"
        $script:DirectionBtn.Header = "Toggle Text Direction (Currently: RTL)"
    } else {
        $script:ChatPanel.FlowDirection = "LeftToRight"
        $script:InputBox.FlowDirection = "LeftToRight"
        $script:DirectionBtn.Header = "Toggle Text Direction (Currently: LTR)"
    }
}

function Toggle-Theme {
    $script:IsDarkMode = -not $script:IsDarkMode
    $bgWindow   = if ($script:IsDarkMode) { "#1E1E1E" } else { "#F5F5F5" }
    $bgChat     = if ($script:IsDarkMode) { "#252526" } else { "#FFFFFF" }
    $borderChat = if ($script:IsDarkMode) { "#3F3F46" } else { "#CCCCCC" }
    $bgCode     = if ($script:IsDarkMode) { "#1E1E1E" } else { "#F8F9FA" }
    $bgInput    = if ($script:IsDarkMode) { "#2D2D2D" } else { "#FFFFFF" }
    $fgInput    = if ($script:IsDarkMode) { "#FFFFFF" } else { "#000000" }

    $script:Window.Background = Brush $bgWindow
    $script:ChatContainerBorder.Background = Brush $bgChat
    $script:ChatContainerBorder.BorderBrush = Brush $borderChat
    $script:CodePreviewBorder.Background = Brush $bgCode
    $script:InputBox.Background = Brush $bgInput
    $script:InputBox.Foreground = Brush $fgInput

    $script:ThemeButton.Header = if ($script:IsDarkMode) { "Toggle Theme (Currently: Dark)" } else { "Toggle Theme (Currently: Light)" }
    if ($script:ChatHistory.Count -gt 0) { Rebuild-ChatUI }
    if (-not [string]::IsNullOrWhiteSpace($script:CurrentAssistantText)) { Extract-CodePreview -Text $script:CurrentAssistantText }
    Save-AppSettings
}

function Toggle-CodePreview {
    $script:ShowCodePreview = -not $script:ShowCodePreview
    if ($script:ShowCodePreview) {
        $script:CodePreviewBorder.Visibility = "Visible"
        $script:MainSplitter.Visibility = "Visible"
        $script:MainContentGrid.ColumnDefinitions[2].Width = New-Object System.Windows.GridLength(480)
    } else {
        $script:CodePreviewBorder.Visibility = "Collapsed"
        $script:MainSplitter.Visibility = "Collapsed"
        $script:MainContentGrid.ColumnDefinitions[2].Width = New-Object System.Windows.GridLength(0)
    }
}

# ==================== Table HTML & Embedded Web Preview ====================
function Convert-MarkdownToHtmlTable {
    param([string]$md)
    $rows = Parse-MarkdownTableRows -md $md
    if ($rows.Count -eq 0) { return "<html><body><p>Could not parse table.</p></body></html>" }
    $bg = if ($script:IsDarkMode) { "#1E1E1E" } else { "#FFFFFF" }
    $fg = if ($script:IsDarkMode) { "#E0E0E0" } else { "#333333" }
    $thBg = if ($script:IsDarkMode) { "#2D2D2D" } else { "#F0F0F0" }
    $bd = if ($script:IsDarkMode) { "#555555" } else { "#DDDDDD" }
    $dir = if ($script:IsRtl) { "rtl" } else { "ltr" }
    $align = if ($script:IsRtl) { "right" } else { "left" }
    $html = "<!DOCTYPE html><html dir='$dir'><head><meta charset='utf-8'><meta http-equiv='X-UA-Compatible' content='IE=edge'><style>body{font-family:'Segoe UI',Tahoma,sans-serif;background:$bg;color:$fg;padding:15px;}table{border-collapse:collapse;width:100%;}th,td{border:1px solid $bd;padding:10px;text-align:$align;}th{background-color:$thBg;font-weight:bold;}</style></head><body><table>"
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $tag = if ($i -eq 0) { "th" } else { "td" }
        $html += "<tr>"
        foreach ($cell in $rows[$i]) {
            $safe = $cell.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;")
            $html += "<$tag>$safe</$tag>"
        }
        $html += "</tr>"
    }
    $html += "</table></body></html>"
    return $html
}

$script:PreviewViewMode = "Code"

function Switch-PreviewViewMode {
    param([string]$Mode)
    $script:PreviewViewMode = $Mode
    if ($Mode -eq "Web") {
        $script:ViewWebBtn.Background = Brush "#2A6FDB"; $script:ViewWebBtn.Foreground = Brush "#FFFFFF"
        $script:ViewSourceBtn.Background = Brush "#E0E0E0"; $script:ViewSourceBtn.Foreground = Brush "#333333"
    } else {
        $script:ViewSourceBtn.Background = Brush "#2A6FDB"; $script:ViewSourceBtn.Foreground = Brush "#FFFFFF"
        $script:ViewWebBtn.Background = Brush "#E0E0E0"; $script:ViewWebBtn.Foreground = Brush "#333333"
    }

    foreach ($tab in $script:CodePreviewTabs.Items) {
        $tag = $tab.Tag
        if (-not $tag) { continue }
        if ($Mode -eq "Web" -and $tag.WebBrowser) {
            $tab.Content = $tag.WebBrowser
        } elseif ($tag.TextBox) {
            $tab.Content = $tag.TextBox
        }
    }
}

$script:ViewSourceBtn.Add_Click({ Switch-PreviewViewMode "Code" })
$script:ViewWebBtn.Add_Click({ Switch-PreviewViewMode "Web" })

function Extract-CodePreview {
    param([string]$Text = $script:CurrentAssistantText)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        $script:CodePreviewTabs.Items.Clear()
        return
    }
    try {
        $script:CodePreviewTabs.Items.Clear()
        $blocks = New-Object System.Collections.ArrayList

        $codeRegex = [regex]'(?s)```([a-zA-Z0-9+#-]*)?\r?\n(.*?)\r?\n?```'
        foreach ($m in $codeRegex.Matches($Text)) {
            $lang = $m.Groups[1].Value.Trim()
            if ([string]::IsNullOrWhiteSpace($lang)) { $lang = "text" }
            [void]$blocks.Add([PSCustomObject]@{ Index = $m.Index; Type = "Code"; Lang = $lang; Content = $m.Groups[2].Value })
        }

        $tableRegex = [regex]'(?m)^[\t ]*\|.+\|[\t ]*\r?\n[\t ]*\|[\s\-:|]+\|[\t ]*\r?\n((?:^[\t ]*\|.+\|[\t ]*\r?\n?)*)'
        foreach ($m in $tableRegex.Matches($Text)) {
            [void]$blocks.Add([PSCustomObject]@{ Index = $m.Index; Type = "Table"; Lang = ""; Content = $m.Value.Trim() })
        }

        $sorted = @($blocks | Sort-Object Index)
        foreach ($block in $sorted) {
            $tab = New-Object System.Windows.Controls.TabItem
            $tb = New-Object System.Windows.Controls.TextBox
            $tb.FontFamily = "Consolas"
            $tb.IsReadOnly = $true
            $tb.AcceptsReturn = $true
            $tb.TextWrapping = "NoWrap"
            $tb.VerticalScrollBarVisibility = "Auto"
            $tb.HorizontalScrollBarVisibility = "Auto"
            $tb.Padding = "5"
            if ($script:IsDarkMode) {
                $tb.Background = Brush "#2D2D2D"; $tb.Foreground = Brush "#D4D4D4"
            } else {
                $tb.Background = Brush "#FFFFFF"; $tb.Foreground = Brush "#000000"
            }

            $wb = $null
            $htmlForWeb = ""

            if ($block.Type -eq "Code") {
                $tab.Header = "Code ($($block.Lang))"
                $tb.Text = $block.Content
                $isWebRenderable = ($block.Lang -match 'html|htm|svg') -or ($block.Content -match '<html|<body|<!DOCTYPE|<svg|<div|<table|<style')
                if ($isWebRenderable) {
                    $htmlForWeb = if ($block.Content -match '<html|<!DOCTYPE') {
                        $block.Content
                    } else {
                        "<!DOCTYPE html><html><head><meta charset='utf-8'><meta http-equiv='X-UA-Compatible' content='IE=edge'></head><body>$($block.Content)</body></html>"
                    }
                }
            } else {
                $tab.Header = "Table"
                $htmlForWeb = Convert-MarkdownToHtmlTable -md $block.Content
                $tb.Text = $htmlForWeb
            }

            if (-not [string]::IsNullOrEmpty($htmlForWeb)) {
                try {
                    $wb = New-Object System.Windows.Controls.WebBrowser
                    $wb.NavigateToString($htmlForWeb)
                } catch { $wb = $null }
            }

            $tab.Tag = @{
                Type       = $block.Type
                Lang       = $block.Lang
                Raw        = $block.Content
                Html       = $htmlForWeb
                TextBox    = $tb
                WebBrowser = $wb
            }

            if ($script:PreviewViewMode -eq "Web" -and $null -ne $wb) {
                $tab.Content = $wb
            } else {
                $tab.Content = $tb
            }
            [void]$script:CodePreviewTabs.Items.Add($tab)
        }
    } catch {}
}

function Get-ActiveContent {
    if ($script:CodePreviewTabs.Items.Count -eq 0) { return $null }
    $tab = $script:CodePreviewTabs.SelectedItem
    if (-not $tab) { return $null }
    return $tab.Tag
}

function Open-CodePreview {
    $content = Get-ActiveContent
    if (-not $content) { return }
    try {
        if ($content.Type -eq "Table") {
            $temp = [System.IO.Path]::GetTempFileName().Replace(".tmp", ".html")
            [System.IO.File]::WriteAllText($temp, $content.Html, [System.Text.Encoding]::UTF8)
            Start-Process $temp
        } else {
            $isBrowser = ($content.Lang -match 'html|htm|svg|xml|javascript|js|css') -or ($content.Raw -match '<html|<body|<!DOCTYPE|<svg|<script')
            if ($isBrowser) {
                $ext = if ($content.Raw -match '<svg') { ".svg" } else { ".html" }
                $temp = [System.IO.Path]::GetTempFileName().Replace(".tmp", $ext)
                [System.IO.File]::WriteAllText($temp, $content.Raw, [System.Text.Encoding]::UTF8)
                Start-Process $temp
            } else {
                $temp = [System.IO.Path]::GetTempFileName().Replace(".tmp", ".txt")
                [System.IO.File]::WriteAllText($temp, $content.Raw, [System.Text.Encoding]::UTF8)
                Start-Process notepad.exe -ArgumentList $temp
            }
        }
    } catch {}
}

function Save-CodePreview {
    $content = Get-ActiveContent
    if (-not $content) { return }
    try {
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        if ($content.Type -eq "Table") {
            $dlg.Filter = "HTML Files (*.html)|*.html|All Files (*.*)|*.*"
            $dlg.FileName = "Table_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
            if ($dlg.ShowDialog()) {
                [System.IO.File]::WriteAllText($dlg.FileName, $content.Html, [System.Text.Encoding]::UTF8)
                Show-OpenFileDialog -Message "Saved to:`n$($dlg.FileName)" -FilePath $dlg.FileName
            }
        } else {
            $dlg.Filter = "Text Files (*.txt)|*.txt|HTML Files (*.html)|*.html|All Files (*.*)|*.*"
            $dlg.FileName = "Code_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
            if ($content.Raw -match '<html|<body|<!DOCTYPE') { $dlg.FilterIndex = 2 }
            if ($dlg.ShowDialog()) {
                [System.IO.File]::WriteAllText($dlg.FileName, $content.Raw, [System.Text.Encoding]::UTF8)
                Show-OpenFileDialog -Message "Saved to:`n$($dlg.FileName)" -FilePath $dlg.FileName
            }
        }
    } catch {}
}

function Save-AllCode {
    if ($script:CodePreviewTabs.Items.Count -eq 0) { return }
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Folder to save all blocks"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $i = 1
        try {
            foreach ($tab in $script:CodePreviewTabs.Items) {
                $content = $tab.Tag
                if (-not $content) { continue }
                if ($content.Type -eq "Table") {
                    $file = Join-Path $dlg.SelectedPath "Block_$($i)_Table.html"
                    [System.IO.File]::WriteAllText($file, $content.Html, [System.Text.Encoding]::UTF8)
                } else {
                    $ext = if ($content.Raw -match '<html|<body|<!DOCTYPE') { ".html" } else { ".txt" }
                    $file = Join-Path $dlg.SelectedPath "Block_$($i)_Code$ext"
                    [System.IO.File]::WriteAllText($file, $content.Raw, [System.Text.Encoding]::UTF8)
                }
                $i++
            }
            Show-OpenFileDialog -Message "All blocks saved to:`n$($dlg.SelectedPath)" -FilePath $dlg.SelectedPath
        } catch {}
    }
}

function Save-SessionLog {
    if ($script:SessionLog.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No log data.", "Info") | Out-Null
        return
    }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = "Log Files (*.txt)|*.txt"
    $dlg.FileName = "OllamaLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    if ($dlg.ShowDialog()) {
        [System.IO.File]::WriteAllLines($dlg.FileName, $script:SessionLog, [System.Text.UTF8Encoding]::new($false))
        Show-OpenFileDialog -Message "Log saved to:`n$($dlg.FileName)" -FilePath $dlg.FileName
    }
}

# ==================== Ollama Server Control ====================
function Start-OllamaServer {
    if ($script:IsBusy) { return }
    if (Test-OllamaPort) {
        Update-OllamaStatus | Out-Null
        return
    }
    $ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
    if (-not $ollamaCmd) {
        [System.Windows.MessageBox]::Show("Ollama executable not found in PATH.", "Error") | Out-Null
        return
    }
    $script:IsBusy = $true
    Set-StatusUi "starting" "Starting Ollama..."
    $script:StartOllamaBtn.IsEnabled = $false
    try {
        $script:OllamaProcess = Start-Process -FilePath $ollamaCmd.Source -ArgumentList "serve" -WindowStyle Hidden -PassThru
    } catch {
        [System.Windows.MessageBox]::Show("Failed: $($_.Exception.Message)", "Error") | Out-Null
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
                $t = $c.ConnectAsync($hostIp, [int]$port)
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
            Set-StatusUi "stopped" "Start failed"
            $script:StartOllamaBtn.IsEnabled = $true
        }
        $script:IsBusy = $false
    })
    $script:StartTimer.Start()
}

function Stop-Generation {
    if (-not $script:IsBusy) { return }
    if ($script:StreamTimer) { $script:StreamTimer.Stop() }
    if ($script:SendPs) {
        try { $script:SendPs.Stop() } catch {}
        try { $script:SendPs.Dispose() } catch {}
        $script:SendPs = $null
    }
    $script:IsBusy = $false
    $script:SendButton.IsEnabled = $true
    $script:StopButton.IsEnabled = $false
    Set-StatusUi "running" "Generation stopped by user."
    if ($null -ne $script:CurrentAssistantText) {
        $script:CurrentAssistantText += "`n[Stopped by user]"
        if ($script:ActiveAssistantBody) {
            Render-SegmentedMessage -BodyPanel $script:ActiveAssistantBody -Text $script:CurrentAssistantText -IsDark $script:IsDarkMode
        }
        if ($script:ActiveAssistantEntry) {
            $script:ActiveAssistantEntry.content = $script:CurrentAssistantText
            $script:ActiveAssistantEntry.stopped = $true
            [void]$script:ChatHistory.Add($script:ActiveAssistantEntry)
        } else {
            [void]$script:ChatHistory.Add(@{ role = "assistant"; content = $script:CurrentAssistantText; stopped = $true })
        }
    }
    $script:InputBox.Focus() | Out-Null
}

# ==================== Models ====================
function Refresh-ModelsList {
    try {
        $r = Invoke-RestMethod -Uri $script:OllamaTagsUrl -Method Get -TimeoutSec 5
        $script:AvailableModels.Clear()
        foreach ($m in $r.models) { [void]$script:AvailableModels.Add($m.name) }
        return $true
    } catch { return $false }
}

function Show-PullModelDialog {
    param([System.Windows.Window]$OwnerWindow = $script:Window)
    if ($script:IsBusy) { return }
    [xml]$pxaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Pull Model" Height="240" Width="480"
        WindowStartupLocation="CenterOwner" Background="#FAFAFA">
    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Text="Model name (e.g. llama3.2:1b, mistral:7b):" FontWeight="SemiBold" Margin="0,0,0,6"/>
        <TextBox Grid.Row="1" x:Name="PullNameInput" Height="28" Padding="4" FontSize="13"/>
        <TextBlock Grid.Row="2" x:Name="PullStatusText" Text="" FontFamily="Consolas" FontSize="11" Margin="0,8,0,0" TextWrapping="Wrap" Foreground="#555"/>
        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,8,0,0">
            <Button x:Name="PullGoBtn" Content="Pull" Width="90" Height="30" Margin="0,0,8,0" Background="#2A6FDB" Foreground="White" FontWeight="Bold"/>
            <Button x:Name="PullCancelBtn" Content="Close" Width="80" Height="30"/>
        </StackPanel>
    </Grid>
</Window>
"@
    $pr = New-Object System.Xml.XmlNodeReader $pxaml
    $pullWin = [Windows.Markup.XamlReader]::Load($pr)
    if ($null -ne $OwnerWindow) { $pullWin.Owner = $OwnerWindow }
    $nameBox = $pullWin.FindName("PullNameInput")
    $status = $pullWin.FindName("PullStatusText")
    $goBtn = $pullWin.FindName("PullGoBtn")
    $cancelBtn = $pullWin.FindName("PullCancelBtn")
    $nameBox.Text = $script:ModelName
    $cancelBtn.Add_Click({ $pullWin.Close() })

    $pullQueue = $null
    $pullPs = $null
    $pullTimer = $null

    $goBtn.Add_Click({
        if ([string]::IsNullOrWhiteSpace($nameBox.Text)) { return }
        $modelToPull = $nameBox.Text.Trim()
        $goBtn.IsEnabled = $false
        $nameBox.IsEnabled = $false
        $status.Text = "Starting..."
        $pullQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
        $pullPs = [PowerShell]::Create()
        [void]$pullPs.AddScript({
            param($url, $model, $queue)
            try {
                Add-Type -AssemblyName System.Net.Http
                $body = @{ model = $model; stream = $true } | ConvertTo-Json
                $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, $url)
                $req.Content = [System.Net.Http.StringContent]::new($body, [System.Text.Encoding]::UTF8, "application/json")
                $client = [System.Net.Http.HttpClient]::new()
                $client.Timeout = [TimeSpan]::FromHours(2)
                $resp = $client.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
                if ($resp.IsSuccessStatusCode) {
                    $stream = $resp.Content.ReadAsStreamAsync().Result
                    $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
                    while (($line = $reader.ReadLine()) -ne $null) {
                        if (-not [string]::IsNullOrWhiteSpace($line)) { $queue.Enqueue($line) }
                    }
                    $reader.Dispose(); $stream.Dispose()
                } else {
                    $queue.Enqueue("__ERR__HTTP $($resp.StatusCode)")
                }
                $client.Dispose()
            } catch { $queue.Enqueue("__ERR__$($_.Exception.Message)") }
            $queue.Enqueue("__DONE__")
        }).AddArgument("http://$($script:OllamaHost):$($script:OllamaPort)/api/pull").AddArgument($modelToPull).AddArgument($pullQueue)
        $async = $pullPs.BeginInvoke()

        $pullTimer = New-Object System.Windows.Threading.DispatcherTimer
        $pullTimer.Interval = [TimeSpan]::FromMilliseconds(200)
        $pullTimer.Add_Tick({
            $chunk = $null
            while ($pullQueue.TryDequeue([ref]$chunk)) {
                if ($chunk -eq "__DONE__") {
                    $pullTimer.Stop()
                    try { $pullPs.EndInvoke($async) } catch {}
                    try { $pullPs.Dispose() } catch {}
                    $status.Text = "Done. Refreshing models..."
                    Refresh-ModelsList | Out-Null
                    $goBtn.IsEnabled = $true
                    $nameBox.IsEnabled = $true
                    return
                }
                if ($chunk -like "__ERR__*") {
                    $status.Text = "ERROR: $($chunk.Substring(7))"
                    continue
                }
                try {
                    $j = $chunk | ConvertFrom-Json
                    if ($j.status) {
                        $line = $j.status
                        if ($j.total -and $j.completed -and $j.total -gt 0) {
                            $pct = [math]::Round(($j.completed / $j.total) * 100, 1)
                            $line += "  ($pct%)"
                        }
                        $status.Text = $line
                    }
                } catch {}
            }
        })
        $pullTimer.Start()
    })

    $pullWin.Add_Closed({
        if ($pullTimer) { $pullTimer.Stop() }
        if ($pullPs) { try { $pullPs.Stop() } catch {}; try { $pullPs.Dispose() } catch {} }
    })

    Invoke-SafeShowDialog -WindowObject $pullWin
}

function Show-ManageModelsDialog {
    Refresh-ModelsList | Out-Null
    $items = if ($script:AvailableModels.Count -gt 0) { ($script:AvailableModels -join "`n") } else { "(none installed yet)" }
    [System.Windows.MessageBox]::Show("Installed models:`n`n$items`n`nCurrent model: $($script:ModelName)", "Models") | Out-Null
    Show-PullModelDialog -OwnerWindow $script:Window
}

# ==================== File Attach ====================
function Add-AttachmentFile {
    param([string]$FilePath)
    try {
        $sizeMB = [math]::Round((Get-Item $FilePath).Length / 1MB, 2)
        if ($sizeMB -gt $script:MaxFileSizeMB) {
            $ans = [System.Windows.MessageBox]::Show(
                "File '$([System.IO.Path]::GetFileName($FilePath))' is $sizeMB MB (limit $($script:MaxFileSizeMB) MB).`nContinue?",
                "Large file", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
            if ($ans -ne [System.Windows.MessageBoxResult]::Yes) { return }
        }
        [void]$script:AttachedFiles.Add($FilePath)
    } catch {}
}

function Update-AttachmentIndicator {
    if ($script:AttachedFiles.Count -eq 0) {
        $script:FileIndicatorText.Text = ""
        $script:FileIndicatorBorder.Visibility = [System.Windows.Visibility]::Collapsed
        return
    }
    $names = ($script:AttachedFiles | ForEach-Object { [System.IO.Path]::GetFileName($_) }) -join ", "
    $script:FileIndicatorText.Text = "Attached $($script:AttachedFiles.Count) file(s): $names"
    $script:FileIndicatorBorder.Visibility = [System.Windows.Visibility]::Visible
}

function Attach-File {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Multiselect = $true
    $dlg.Filter = "All Supported|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.txt;*.log;*.md;*.ps1;*.py;*.json;*.csv;*.html;*.js|Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif|Text & Code|*.txt;*.log;*.md;*.ps1;*.py;*.json;*.csv;*.html;*.js|All Files (*.*)|*.*"
    if ($dlg.ShowDialog()) {
        foreach ($f in $dlg.FileNames) { Add-AttachmentFile $f }
        Update-AttachmentIndicator
    }
}

function Clear-Attachment {
    $script:AttachedFiles.Clear()
    Update-AttachmentIndicator
}

# ==================== Save/Load Conversations ====================
function Save-ChatConversation {
    if ($script:ChatHistory.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Nothing to save.", "Info") | Out-Null
        return
    }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = "Chat Session (*.json)|*.json|All Files (*.*)|*.*"
    $dlg.InitialDirectory = $script:ConvosDir
    $dlg.FileName = "Chat_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    if ($dlg.ShowDialog()) {
        try {
            $data = [ordered]@{
                Version = "0.040"
                SavedAt = (Get-Date -Format 'o')
                Model   = $script:ModelName
                SystemPrompt = $script:SystemPrompt
                Messages = $script:ChatHistory
            }
            ($data | ConvertTo-Json -Depth 12) | Out-File -FilePath $dlg.FileName -Encoding UTF8
            Show-OpenFileDialog -Message "Saved to:`n$($dlg.FileName)" -FilePath $dlg.FileName
        } catch {
            [System.Windows.MessageBox]::Show("Failed: $($_.Exception.Message)", "Error") | Out-Null
        }
    }
}

function Load-ChatConversation {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = "Chat Session (*.json)|*.json|All Files (*.*)|*.*"
    $dlg.InitialDirectory = $script:ConvosDir
    if (-not $dlg.ShowDialog()) { return }
    try {
        $raw = Read-FileSafely -FilePath $dlg.FileName
        $data = $raw | ConvertFrom-Json
        $script:ChatHistory.Clear()
        foreach ($m in $data.Messages) {
            $entry = @{ role = $m.role; content = $m.content }
            if ($m.PSObject.Properties.Match('display').Count) { $entry.display = $m.display }
            if ($m.PSObject.Properties.Match('images').Count -and $m.images) { $entry.images = @($m.images) }
            if ($m.PSObject.Properties.Match('stopped').Count -and $m.stopped) { $entry.stopped = $true }
            [void]$script:ChatHistory.Add($entry)
        }
        Rebuild-ChatUI
    } catch {
        [System.Windows.MessageBox]::Show("Failed: $($_.Exception.Message)", "Error") | Out-Null
    }
}

function New-ChatConversation {
    $ans = [System.Windows.MessageBox]::Show("Clear current chat and history?", "New Chat",
        [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    if ($ans -eq [System.Windows.MessageBoxResult]::Yes) {
        $script:ChatHistory.Clear()
        $script:ChatPanel.Children.Clear()
        $script:AllBubbles.Clear()
        $script:CodePreviewTabs.Items.Clear()
        Clear-Attachment
        $script:StatsLabel.Text = ""
        [void](New-MessageBubble -Sender "System" -Text "New chat started." -LightColor "#FFF8E1" -DarkColor "#5A4A1E")
    }
}

# ==================== UI Rebuild ====================
function Rebuild-ChatUI {
    $script:ChatPanel.Children.Clear()
    $script:AllBubbles.Clear()
    $script:CodePreviewTabs.Items.Clear()
    foreach ($msg in $script:ChatHistory) {
        if ($msg.role -eq "user") {
            $display = if ($msg.display) { $msg.display } else { $msg.content }
            [void](New-MessageBubble -Sender "You" -Text $display -LightColor "#DCEBFF" -DarkColor "#1F3864" -Entry $msg -Role "user")
        } elseif ($msg.role -eq "assistant") {
            [void](New-MessageBubble -Sender "Assistant" -Text $msg.content -LightColor "#E8F5E9" -DarkColor "#2D5A27" -Entry $msg -Role "assistant")
        }
    }
    $script:ChatScroll.ScrollToEnd()
}

function Export-Chat {
    if ($script:ChatHistory.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No conversation.", "Info") | Out-Null
        return
    }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = "Text Files (*.txt)|*.txt"
    $dlg.FileName = "OllamaChat_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    if ($dlg.ShowDialog()) {
        $lines = foreach ($m in $script:ChatHistory) {
            $who = if ($m.role -eq "user") { "You" } elseif ($m.role -eq "assistant") { "Assistant" } else { $m.role }
            "[$who]`r`n$($m.content)`r`n"
        }
        [System.IO.File]::WriteAllText($dlg.FileName, ($lines -join "`r`n"), [System.Text.UTF8Encoding]::new($false))
        Show-OpenFileDialog -Message "Exported to:`n$($dlg.FileName)" -FilePath $dlg.FileName
    }
}

# ==================== Settings Window ====================
function Show-SettingsWindow {
    if ($script:SettingsWindow -and $script:SettingsWindow.IsVisible) {
        $script:SettingsWindow.Activate(); return
    }

    [xml]$sxaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Ollama Configuration" Height="690" Width="580"
        WindowStartupLocation="CenterOwner" Background="#FAFAFA" FlowDirection="LeftToRight">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/><RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TabControl Grid.Row="0" Background="White">
            <TabItem Header="General">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <Grid Margin="15">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,15">
                            <StackPanel Margin="0,0,10,0">
                                <TextBlock Text="Host IP:" FontWeight="SemiBold" Margin="0,0,0,4"/>
                                <TextBox x:Name="HostInput" Width="180" Height="28" Padding="4" FontSize="13"/>
                            </StackPanel>
                            <StackPanel>
                                <TextBlock Text="Port:" FontWeight="SemiBold" Margin="0,0,0,4"/>
                                <TextBox x:Name="PortInput" Width="100" Height="28" Padding="4" FontSize="13"/>
                            </StackPanel>
                        </StackPanel>

                        <StackPanel Grid.Row="1" Margin="0,0,0,15">
                            <TextBlock Text="Model Name:" FontWeight="SemiBold" Margin="0,0,0,4"/>
                            <StackPanel Orientation="Horizontal">
                                <ComboBox x:Name="ModelComboInput" Width="360" Height="28" IsEditable="True" FontSize="13"/>
                                <Button x:Name="RefreshModelsBtn" Content="Refresh" Width="55" Height="28" Margin="4,0,0,0" ToolTip="Refresh models list"/>
                                <Button x:Name="PullModelBtn" Content="Pull" Width="70" Height="28" Margin="4,0,0,0" ToolTip="Pull a new model"/>
                            </StackPanel>
                        </StackPanel>

                        <StackPanel Grid.Row="2" Margin="0,0,0,15">
                            <TextBlock Text="System Prompt:" FontWeight="SemiBold" Margin="0,0,0,4"/>
                            <TextBox x:Name="PromptInput" Height="90" Padding="4" FontSize="12" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto"/>
                        </StackPanel>

                        <StackPanel Grid.Row="3" Margin="0,0,0,15">
                            <TextBlock Text="In-Chat Table Display Mode:" FontWeight="SemiBold" Margin="0,0,0,4"/>
                            <ComboBox x:Name="TableModeCombo" Height="28" FontSize="13">
                                <ComboBoxItem Content="FlowDocument Table (Clean, Integrated)" Tag="FlowTable"/>
                                <ComboBoxItem Content="Interactive DataGrid (Sortable, Selectable Cells)" Tag="DataGrid"/>
                            </ComboBox>
                        </StackPanel>

                        <CheckBox x:Name="KeepContextCheckbox" Grid.Row="4" Content="Keep AI memory (context) when clicking 'Clear Chat'" Margin="0,5,0,5" FontWeight="SemiBold"/>
                        <CheckBox x:Name="ShowCodeCheckbox"     Grid.Row="5" Content="Show Preview pane" Margin="0,5,0,5" FontWeight="SemiBold"/>
                        <CheckBox x:Name="SendWithCtrlEnterCheckbox" Grid.Row="6" Content="Send with Ctrl+Enter (Enter adds new line)" Margin="0,5,0,5" FontWeight="SemiBold"/>

                        <TextBlock Grid.Row="7" Text="Settings are saved automatically to %APPDATA%\SnwOllamaChat\settings.json" FontSize="11" Foreground="Gray" Margin="0,10,0,0" TextWrapping="Wrap"/>
                    </Grid>
                </ScrollViewer>
            </TabItem>

            <TabItem Header="Model Speed">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <Grid Margin="15">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <StackPanel Grid.Row="0" Margin="0,0,0,15">
                            <TextBlock Text="Speed Preset:" FontWeight="Bold" Margin="0,0,0,4"/>
                            <ComboBox x:Name="SpeedPresetInput" Height="28" FontSize="13">
                                <ComboBoxItem Content="Max Speed" Tag="Max"/>
                                <ComboBoxItem Content="Balanced (Recommended)" Tag="Balanced"/>
                                <ComboBoxItem Content="Quality (Default)" Tag="Quality"/>
                                <ComboBoxItem Content="Custom (Manual)" Tag="Custom"/>
                            </ComboBox>
                        </StackPanel>

                        <StackPanel Grid.Row="1" Margin="0,0,0,15">
                            <TextBlock Text="Keep Alive:" FontWeight="SemiBold" Margin="0,0,0,4"/>
                            <ComboBox x:Name="KeepAliveInput" Height="28" FontSize="13">
                                <ComboBoxItem Content="-1 (Forever)" Tag="-1"/>
                                <ComboBoxItem Content="1h (1 Hour)" Tag="1h"/>
                                <ComboBoxItem Content="5m (Default)" Tag="5m"/>
                                <ComboBoxItem Content="0 (Unload Immediately)" Tag="0"/>
                            </ComboBox>
                        </StackPanel>

                        <StackPanel Grid.Row="2" Margin="0,0,0,15">
                            <TextBlock Text="Context Window (num_ctx):" FontWeight="SemiBold" Margin="0,0,0,4"/>
                            <ComboBox x:Name="NumCtxInput" Height="28" FontSize="13">
                                <ComboBoxItem Content="1024" Tag="1024"/>
                                <ComboBoxItem Content="2048" Tag="2048"/>
                                <ComboBoxItem Content="4096" Tag="4096"/>
                                <ComboBoxItem Content="8192" Tag="8192"/>
                            </ComboBox>
                        </StackPanel>

                        <StackPanel Grid.Row="3" Margin="0,0,0,15">
                            <TextBlock Text="CPU Threads (num_thread):" FontWeight="SemiBold" Margin="0,0,0,4"/>
                            <ComboBox x:Name="NumThreadInput" Height="28" FontSize="13">
                                <ComboBoxItem Content="0 (Auto)" Tag="0"/>
                                <ComboBoxItem Content="4" Tag="4"/>
                                <ComboBoxItem Content="6" Tag="6"/>
                                <ComboBoxItem Content="8" Tag="8"/>
                                <ComboBoxItem Content="12" Tag="12"/>
                                <ComboBoxItem Content="16" Tag="16"/>
                            </ComboBox>
                        </StackPanel>
                    </Grid>
                </ScrollViewer>
            </TabItem>

            <TabItem Header="Sampling">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <Grid Margin="15">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <StackPanel Grid.Row="0" Margin="0,0,0,12">
                            <TextBlock Text="Temperature (0.0 – 2.0):" FontWeight="SemiBold" Margin="0,0,0,4"/>
                            <TextBox x:Name="TempInput" Width="120" Height="28" Padding="4" FontSize="13" HorizontalAlignment="Left"/>
                        </StackPanel>

                        <StackPanel Grid.Row="1" Margin="0,0,0,12">
                            <TextBlock Text="Top P (0.0 – 1.0):" FontWeight="SemiBold" Margin="0,0,0,4"/>
                            <TextBox x:Name="TopPInput" Width="120" Height="28" Padding="4" FontSize="13" HorizontalAlignment="Left"/>
                        </StackPanel>

                        <StackPanel Grid.Row="2" Margin="0,0,0,12">
                            <TextBlock Text="Top K (0 = disabled):" FontWeight="SemiBold" Margin="0,0,0,4"/>
                            <TextBox x:Name="TopKInput" Width="120" Height="28" Padding="4" FontSize="13" HorizontalAlignment="Left"/>
                        </StackPanel>

                        <StackPanel Grid.Row="3" Margin="0,0,0,12">
                            <TextBlock Text="Repeat Penalty:" FontWeight="SemiBold" Margin="0,0,0,4"/>
                            <TextBox x:Name="RepPenInput" Width="120" Height="28" Padding="4" FontSize="13" HorizontalAlignment="Left"/>
                        </StackPanel>

                        <StackPanel Grid.Row="4" Margin="0,0,0,12">
                            <TextBlock Text="Seed (-1 = random):" FontWeight="SemiBold" Margin="0,0,0,4"/>
                            <TextBox x:Name="SeedInput" Width="120" Height="28" Padding="4" FontSize="13" HorizontalAlignment="Left"/>
                        </StackPanel>

                        <Button Grid.Row="5" x:Name="ResetSamplingBtn" Content="Reset Defaults" Width="130" Height="28" HorizontalAlignment="Left" Margin="0,10,0,0"/>
                    </Grid>
                </ScrollViewer>
            </TabItem>
        </TabControl>

        <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
            <Button x:Name="SaveSettingsBtn" Content="Save &amp; Apply" Width="120" Height="32" Margin="0,0,8,0" Background="#2A6FDB" Foreground="White" FontWeight="Bold"/>
            <Button x:Name="CloseSettingsBtn" Content="Cancel" Width="80" Height="32"/>
        </StackPanel>
    </Grid>
</Window>
"@
    $sreader = New-Object System.Xml.XmlNodeReader $sxaml
    $script:SettingsWindow = [Windows.Markup.XamlReader]::Load($sreader)
    $script:SettingsWindow.Owner = $script:Window

    $hostBox = $script:SettingsWindow.FindName("HostInput")
    $portBox = $script:SettingsWindow.FindName("PortInput")
    $modelCombo = $script:SettingsWindow.FindName("ModelComboInput")
    $refreshModelsBtn = $script:SettingsWindow.FindName("RefreshModelsBtn")
    $pullModelBtn = $script:SettingsWindow.FindName("PullModelBtn")
    $promptBox = $script:SettingsWindow.FindName("PromptInput")
    $tableModeCombo = $script:SettingsWindow.FindName("TableModeCombo")
    $keepContextCheck = $script:SettingsWindow.FindName("KeepContextCheckbox")
    $showCodeCheck = $script:SettingsWindow.FindName("ShowCodeCheckbox")
    $sendCtrlEnterCheck = $script:SettingsWindow.FindName("SendWithCtrlEnterCheckbox")
    $presetBox = $script:SettingsWindow.FindName("SpeedPresetInput")
    $keepAliveBox = $script:SettingsWindow.FindName("KeepAliveInput")
    $numCtxBox = $script:SettingsWindow.FindName("NumCtxInput")
    $numThreadBox = $script:SettingsWindow.FindName("NumThreadInput")
    $tempBox = $script:SettingsWindow.FindName("TempInput")
    $topPBox = $script:SettingsWindow.FindName("TopPInput")
    $topKBox = $script:SettingsWindow.FindName("TopKInput")
    $repPenBox = $script:SettingsWindow.FindName("RepPenInput")
    $seedBox = $script:SettingsWindow.FindName("SeedInput")
    $resetSamplingBtn = $script:SettingsWindow.FindName("ResetSamplingBtn")
    $saveBtn = $script:SettingsWindow.FindName("SaveSettingsBtn")
    $closeBtn = $script:SettingsWindow.FindName("CloseSettingsBtn")

    $hostBox.Text = $script:OllamaHost
    $portBox.Text = $script:OllamaPort
    $promptBox.Text = $script:SystemPrompt
    $keepContextCheck.IsChecked = $script:ClearKeepsContext
    $showCodeCheck.IsChecked = $script:ShowCodePreview
    $sendCtrlEnterCheck.IsChecked = $script:SendWithCtrlEnter
    $tempBox.Text = $script:Temperature
    $topPBox.Text = $script:TopP
    $topKBox.Text = $script:TopK
    $repPenBox.Text = $script:RepeatPenalty
    $seedBox.Text = $script:Seed

    Refresh-ModelsList | Out-Null
    foreach ($m in $script:AvailableModels) { [void]$modelCombo.Items.Add($m) }
    $modelCombo.Text = $script:ModelName

    function Select-ComboTag($combo, $tag) {
        foreach ($item in $combo.Items) {
            if ($item.Tag -eq $tag) { $combo.SelectedItem = $item; break }
        }
    }
    Select-ComboTag $tableModeCombo $script:TableRenderMode
    Select-ComboTag $presetBox $script:SpeedPreset
    Select-ComboTag $keepAliveBox $script:KeepAlive
    Select-ComboTag $numCtxBox $script:NumCtx
    Select-ComboTag $numThreadBox $script:NumThread

    function Update-ManualInputsState {
        $custom = ($presetBox.SelectedItem -and $presetBox.SelectedItem.Tag -eq "Custom")
        $keepAliveBox.IsEnabled = $custom
        $numCtxBox.IsEnabled = $custom
        $numThreadBox.IsEnabled = $custom
    }
    Update-ManualInputsState

    $presetBox.Add_SelectionChanged({
        if (-not $presetBox.SelectedItem) { return }
        $tag = $presetBox.SelectedItem.Tag
        if ($tag -eq "Max") {
            Select-ComboTag $keepAliveBox "-1"; Select-ComboTag $numCtxBox "1024"; Select-ComboTag $numThreadBox "0"
        } elseif ($tag -eq "Balanced") {
            Select-ComboTag $keepAliveBox "-1"; Select-ComboTag $numCtxBox "2048"; Select-ComboTag $numThreadBox "0"
        } elseif ($tag -eq "Quality") {
            Select-ComboTag $keepAliveBox "5m"; Select-ComboTag $numCtxBox "4096"; Select-ComboTag $numThreadBox "0"
        }
        Update-ManualInputsState
    })

    $refreshModelsBtn.Add_Click({
        $ok = Refresh-ModelsList
        $modelCombo.Items.Clear()
        foreach ($m in $script:AvailableModels) { [void]$modelCombo.Items.Add($m) }
        $modelCombo.Text = $script:ModelName
    })

    $pullModelBtn.Add_Click({
        Show-PullModelDialog -OwnerWindow $script:SettingsWindow
        $modelCombo.Items.Clear()
        foreach ($m in $script:AvailableModels) { [void]$modelCombo.Items.Add($m) }
        if ($script:AvailableModels.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($script:ModelName)) {
            $modelCombo.Text = $script:ModelName
        }
    })

    $resetSamplingBtn.Add_Click({
        $tempBox.Text = "0.7"; $topPBox.Text = "0.9"; $topKBox.Text = "40"; $repPenBox.Text = "1.1"; $seedBox.Text = "-1"
    })

    $saveBtn.Add_Click({
        $oldTableMode = $script:TableRenderMode
        $script:OllamaHost = $hostBox.Text.Trim()
        $script:OllamaPort = $portBox.Text.Trim()
        $script:OllamaChatUrl = "http://$($script:OllamaHost):$($script:OllamaPort)/api/chat"
        $script:OllamaTagsUrl = "http://$($script:OllamaHost):$($script:OllamaPort)/api/tags"
        $script:ModelName = $modelCombo.Text.Trim()
        $script:SystemPrompt = $promptBox.Text.Trim()
        $script:TableRenderMode = if ($tableModeCombo.SelectedItem) { $tableModeCombo.SelectedItem.Tag } else { "FlowTable" }
        $script:ClearKeepsContext = [bool]$keepContextCheck.IsChecked
        $script:SendWithCtrlEnter = [bool]$sendCtrlEnterCheck.IsChecked
        $script:SpeedPreset = $presetBox.SelectedItem.Tag
        $script:KeepAlive = $keepAliveBox.SelectedItem.Tag
        $script:NumCtx = $numCtxBox.SelectedItem.Tag
        $script:NumThread = $numThreadBox.SelectedItem.Tag
        $script:Temperature = $tempBox.Text.Trim()
        $script:TopP = $topPBox.Text.Trim()
        $script:TopK = $topKBox.Text.Trim()
        $script:RepeatPenalty = $repPenBox.Text.Trim()
        $script:Seed = $seedBox.Text.Trim()

        $newShow = [bool]$showCodeCheck.IsChecked
        if ($newShow -ne $script:ShowCodePreview) { Toggle-CodePreview }

        $script:ModelLabel.Text = $script:ModelName
        Update-OllamaStatus | Out-Null
        Save-AppSettings

        if ($oldTableMode -ne $script:TableRenderMode -and $script:ChatHistory.Count -gt 0) {
            Rebuild-ChatUI
        }
        $script:SettingsWindow.Close()
    })

    $closeBtn.Add_Click({ $script:SettingsWindow.Close() })
    Invoke-SafeShowDialog -WindowObject $script:SettingsWindow
}

# ==================== Payload Builder ====================
function Build-OptionsHash {
    $h = @{}
    $v = 0
    if ([int]::TryParse($script:NumCtx, [ref]$v) -and $v -gt 0)         { $h["num_ctx"] = $v }
    if ([int]::TryParse($script:NumThread, [ref]$v) -and $v -gt 0)      { $h["num_thread"] = $v }
    $d = 0.0
    if ([double]::TryParse($script:Temperature, [ref]$d))               { $h["temperature"] = $d }
    if ([double]::TryParse($script:TopP, [ref]$d) -and $d -ge 0 -and $d -le 1) { $h["top_p"] = $d }
    if ([int]::TryParse($script:TopK, [ref]$v) -and $v -ge 0)           { $h["top_k"] = $v }
    if ([double]::TryParse($script:RepeatPenalty, [ref]$d) -and $d -gt 0) { $h["repeat_penalty"] = $d }
    if ([int]::TryParse($script:Seed, [ref]$v) -and $v -ne -1)          { $h["seed"] = $v }
    return $h
}

# ==================== Chat Send ====================
function Send-ChatMessage {
    param([hashtable]$UserEntry, [string]$DisplayText)
    if ($script:IsBusy) { return }
    if (-not $UserEntry) { return }

    if ($script:AvailableModels.Count -gt 0 -and -not ($script:AvailableModels -contains $script:ModelName)) {
        $ans = [System.Windows.MessageBox]::Show(
            "Model '$($script:ModelName)' not found in installed list.`nContinue anyway?",
            "Model not found", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($ans -ne [System.Windows.MessageBoxResult]::Yes) { return }
    }

    $script:IsBusy = $true
    $script:UserIsScrollingUp = $false # Reset manual scroll lock on new prompt
    [void]$script:ChatHistory.Add($UserEntry)
    [void](New-MessageBubble -Sender "You" -Text $DisplayText -LightColor "#DCEBFF" -DarkColor "#1F3864" -Entry $UserEntry -Role "user")

    $script:SendButton.IsEnabled = $false
    $script:StopButton.IsEnabled = $true
    $script:StatusLabel.Text = "Assistant is streaming..."

    $assistantEntry = @{ role = "assistant"; content = "" }
    $script:ActiveAssistantEntry = $assistantEntry
    $bubbleRefs = New-MessageBubble -Sender "Assistant" -Text "" -LightColor "#E8F5E9" -DarkColor "#2D5A27" -Entry $assistantEntry -Role "assistant"
    $script:ActiveAssistantBody = $bubbleRefs.BodyPanel
    $script:ActiveAssistantRich = $bubbleRefs.RichTextBox

    foreach ($b in $script:AllBubbles) {
        if ($b -is [System.Windows.Controls.Border]) {
            $b.BorderBrush = "Transparent"; $b.BorderThickness = 0
        }
    }
    if ($bubbleRefs.Border) {
        $bubbleRefs.Border.BorderBrush = Brush "#2A6FDB"
        $bubbleRefs.Border.BorderThickness = 2
    }

    $script:CurrentAssistantText = ""
    $script:CodePreviewTabs.Items.Clear()
    $script:StatsLabel.Text = ""

    $messages = New-Object System.Collections.ArrayList
    [void]$messages.Add(@{ role = "system"; content = $script:SystemPrompt })
    foreach ($m in $script:ChatHistory) {
        $entry = @{ role = $m.role; content = $m.content }
        if ($m.images) { $entry["images"] = @($m.images) }
        [void]$messages.Add($entry)
    }

    $optionsHash = Build-OptionsHash
    $payloadHash = @{
        model = $script:ModelName
        messages = $messages
        stream = $true
        keep_alive = $script:KeepAlive
    }
    if ($optionsHash.Count -gt 0) { $payloadHash["options"] = $optionsHash }
    $payload = $payloadHash | ConvertTo-Json -Depth 10 -Compress

    $script:StreamQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

    $script:SendPs = [PowerShell]::Create()
    [void]$script:SendPs.AddScript({
        param($url, $body, $queue)
        try {
            Add-Type -AssemblyName System.Net.Http
            $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, $url)
            $request.Content = [System.Net.Http.StringContent]::new($body, [System.Text.Encoding]::UTF8, "application/json")
            $client = [System.Net.Http.HttpClient]::new()
            $client.Timeout = [TimeSpan]::FromMinutes(10)
            $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
            if ($response.IsSuccessStatusCode) {
                $stream = $response.Content.ReadAsStreamAsync().Result
                $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
                while (($line = $reader.ReadLine()) -ne $null) {
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }
                    try {
                        $json = $line | ConvertFrom-Json
                        if ($json.done) {
                            $stats = @{
                                prompt_eval_count = $json.prompt_eval_count
                                eval_count        = $json.eval_count
                                eval_duration     = $json.eval_duration
                                total_duration    = $json.total_duration
                            } | ConvertTo-Json -Compress
                            $queue.Enqueue("__STATS__:$stats")
                            break
                        }
                        $chunkText = $null
                        if ($json.message -and $json.message.content) { $chunkText = $json.message.content }
                        elseif ($json.response) { $chunkText = $json.response }
                        if (-not [string]::IsNullOrEmpty($chunkText)) { $queue.Enqueue($chunkText) }
                    } catch {}
                }
                $reader.Dispose(); $stream.Dispose()
            } else {
                $queue.Enqueue("`r`n[Error: HTTP $($response.StatusCode)]")
            }
            $client.Dispose()
        } catch {
            $queue.Enqueue("`r`n[Error: $($_.Exception.Message)]")
        }
        $queue.Enqueue("__DONE__")
    }).AddArgument($script:OllamaChatUrl).AddArgument($payload).AddArgument($script:StreamQueue)

    $script:SendAsync = $script:SendPs.BeginInvoke()

    $script:StreamTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:StreamTimer.Interval = [TimeSpan]::FromMilliseconds(40)
    
    $script:StreamTimer.Add_Tick({
        try {
            $chunk = $null
            $pendingBuffer = ""
            $isDone = $false

            while ($script:StreamQueue.TryDequeue([ref]$chunk)) {
                if ($chunk -like "__STATS__:*") {
                    try {
                        $j = $chunk.Substring(9) | ConvertFrom-Json
                        $inTok  = if ($j.prompt_eval_count) { [int]$j.prompt_eval_count } else { 0 }
                        $outTok = if ($j.eval_count)        { [int]$j.eval_count }        else { 0 }
                        $durNs  = if ($j.eval_duration)     { [double]$j.eval_duration }   else { 0 }
                        $tps = if ($durNs -gt 0) { [math]::Round($outTok / ($durNs / 1e9), 1) } else { 0 }
                        $ctx = 0; [void][int]::TryParse($script:NumCtx, [ref]$ctx)
                        $usage = if ($ctx -gt 0) { [math]::Round(($inTok + $outTok) / $ctx * 100, 1) } else { 0 }
                        $script:StatsLabel.Text = "In: $inTok | Out: $outTok | $tps tok/s | Ctx: $usage%"
                    } catch {}
                    continue
                }
                if ($chunk -eq "__DONE__") {
                    $isDone = $true
                    break
                }
                $pendingBuffer += $chunk
            }

            if ($pendingBuffer.Length -gt 0) {
                $script:CurrentAssistantText += $pendingBuffer
                if ($script:ActiveAssistantRich) {
                    try { $script:ActiveAssistantRich.AppendText($pendingBuffer) } catch {}
                }
                if (-not $script:UserIsScrollingUp) {
                    $script:ChatScroll.ScrollToEnd()
                }
            }

            if ($isDone) {
                $script:StreamTimer.Stop()
                try { $script:SendPs.EndInvoke($script:SendAsync) } catch {}
                try { $script:SendPs.Dispose() } catch {}
                $script:SendPs = $null

                if ($script:ActiveAssistantBody) {
                    Render-SegmentedMessage -BodyPanel $script:ActiveAssistantBody -Text $script:CurrentAssistantText -IsDark $script:IsDarkMode
                }
                if ($script:ShowCodePreview) {
                    Extract-CodePreview -Text $script:CurrentAssistantText
                }
                if ($script:ActiveAssistantEntry) {
                    $script:ActiveAssistantEntry.content = $script:CurrentAssistantText
                    [void]$script:ChatHistory.Add($script:ActiveAssistantEntry)
                } else {
                    [void]$script:ChatHistory.Add(@{ role = "assistant"; content = $script:CurrentAssistantText })
                }
                $script:IsBusy = $false
                $script:SendButton.IsEnabled = $true
                $script:StopButton.IsEnabled = $false
                Set-StatusUi "running" "Ollama is running at $($script:OllamaHost):$($script:OllamaPort)"
                if (-not $script:UserIsScrollingUp) {
                    $script:ChatScroll.ScrollToEnd()
                }
                $script:InputBox.Focus() | Out-Null
            }
        } catch {
            Write-SessionLog "StreamTimer error: $($_.Exception.Message)" "ERROR"
        }
    })
    $script:StreamTimer.Start()
}

function Send-Message {
    if ($script:IsBusy) { return }
    $userText = $script:InputBox.Text.Trim()
    $hasFiles = $script:AttachedFiles.Count -gt 0
    if ([string]::IsNullOrWhiteSpace($userText) -and -not $hasFiles) { return }

    if (-not (Test-OllamaPort)) {
        Set-StatusUi "stopped" "Ollama is stopped"
        $script:StartOllamaBtn.IsEnabled = $true
        [void](New-MessageBubble -Sender "System" -Text "Ollama is not running. Click 'Start Ollama'." -LightColor "#FFCDD2" -DarkColor "#5A2E2E")
        return
    }

    $displayText = $userText
    $apiContent = $userText
    $images = New-Object System.Collections.ArrayList

    if ($hasFiles) {
        foreach ($fp in $script:AttachedFiles) {
            $fileName = [System.IO.Path]::GetFileName($fp)
            $ext = [System.IO.Path]::GetExtension($fp).ToLower()
            $isImage = @(".png", ".jpg", ".jpeg", ".bmp", ".gif") -contains $ext
            if ($isImage) {
                try {
                    $bytes = [System.IO.File]::ReadAllBytes($fp)
                    $b64 = [Convert]::ToBase64String($bytes)
                    [void]$images.Add($b64)
                    $displayText += "`n[Attached Image: $fileName]"
                } catch {}
            } else {
                $fc = Read-FileSafely -FilePath $fp
                $apiContent += "`n`n--- File: $fileName ---`n$fc`n------------------------"
                $displayText += "`n[Attached File: $fileName]"
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($userText) -and $hasFiles) {
        $apiContent = "Please analyze the attached files. $apiContent"
        $displayText = $displayText.Trim()
    }

    $userEntry = @{ role = "user"; content = $apiContent; display = $displayText }
    if ($images.Count -gt 0) { $userEntry["images"] = @($images) }

    $script:InputBox.Clear()
    Clear-Attachment
    Send-ChatMessage -UserEntry $userEntry -DisplayText $displayText
}

# ==================== Diagnostics ====================
function Show-Diagnostics {
    if ($script:DiagWindow -and $script:DiagWindow.IsVisible) {
        $script:DiagWindow.Activate(); return
    }
    [xml]$dxaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Ollama Diagnostics" Height="480" Width="780"
        WindowStartupLocation="CenterOwner" Background="#FAFAFA" FlowDirection="LeftToRight">
    <Grid Margin="10">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Text="Ollama Diagnostic Check" FontWeight="Bold" FontSize="14" Margin="0,0,0,6"/>
        <Border Grid.Row="1" BorderBrush="#CCCCCC" BorderThickness="1" Background="White">
            <TextBox x:Name="LogBox" IsReadOnly="True" FontFamily="Consolas" FontSize="12" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="NoWrap" Padding="6" BorderThickness="0"/>
        </Border>
        <Button Grid.Row="2" x:Name="CloseBtn" Content="Close" Width="100" Height="30" HorizontalAlignment="Right" Margin="0,8,0,0"/>
    </Grid>
</Window>
"@
    $dr = New-Object System.Xml.XmlNodeReader $dxaml
    $script:DiagWindow = [Windows.Markup.XamlReader]::Load($dr)
    $script:DiagWindow.Owner = $script:Window
    $script:DiagLogBox = $script:DiagWindow.FindName("LogBox")
    $dclose = $script:DiagWindow.FindName("CloseBtn")
    $dclose.Add_Click({ $script:DiagWindow.Close() })

    $script:DiagWindow.Add_Loaded({
        $script:DiagLogBox.AppendText("Diagnostic started at $(Get-Date -Format 'HH:mm:ss')`r`n")
        $script:DiagLogBox.AppendText("Target: $($script:OllamaHost):$($script:OllamaPort)`r`n`r`n")
        $script:DiagState = "start"
        $script:DiagTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:DiagTimer.Interval = [TimeSpan]::FromMilliseconds(150)
        $script:DiagTimer.Add_Tick({
            switch ($script:DiagState) {
                "start" {
                    $tcpOk = Test-OllamaPort
                    if ($tcpOk) { $script:DiagLogBox.AppendText("[Step 1] TCP OK.`r`n"); $script:DiagState = "http" }
                    else { $script:DiagLogBox.AppendText("[Step 1] TCP FAILED.`r`n"); $script:DiagTimer.Stop() }
                }
                "http" {
                    $script:DiagPs = [PowerShell]::Create()
                    [void]$script:DiagPs.AddScript({
                        param($url)
                        try { return @{ ok = $true; data = (Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 5) } }
                        catch { return @{ ok = $false; error = $_.Exception.Message } }
                    }).AddArgument($script:OllamaTagsUrl)
                    $script:DiagAsync = $script:DiagPs.BeginInvoke()
                    $script:DiagState = "waiting"
                }
                "waiting" {
                    if (-not $script:DiagAsync -or -not $script:DiagAsync.IsCompleted) { return }
                    try {
                        $r = $script:DiagPs.EndInvoke($script:DiagAsync)
                        try { $script:DiagPs.Dispose() } catch {}
                        $script:DiagPs = $null
                        if ($r.ok) {
                            $script:DiagLogBox.AppendText("[Step 2] HTTP OK.`r`n")
                            $n = 0
                            if ($r.data.models) { $n = $r.data.models.Count }
                            $script:DiagLogBox.AppendText("[Info] Installed models: $n`r`n")
                            foreach ($mm in $r.data.models) { $script:DiagLogBox.AppendText("   - $($mm.name)`r`n") }
                        } else {
                            $script:DiagLogBox.AppendText("[Step 2] HTTP failed: $($r.error)`r`n")
                        }
                    } catch {}
                    $script:DiagTimer.Stop()
                }
            }
        })
        $script:DiagTimer.Start()
    })
    $script:DiagWindow.Add_Closed({
        if ($script:DiagTimer) { $script:DiagTimer.Stop() }
        if ($script:DiagPs) { try { $script:DiagPs.Stop() } catch {}; try { $script:DiagPs.Dispose() } catch {}; $script:DiagPs = $null }
        $script:DiagWindow = $null
    })
    Invoke-SafeShowDialog -WindowObject $script:DiagWindow
}

# ==================== Drag & Drop ====================
function Setup-DragDrop {
    param($control)
    $control.AllowDrop = $true
    $control.Add_DragOver({
        param($s, $e)
        if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
            $e.Effects = [System.Windows.DragDropEffects]::Copy
        } else {
            $e.Effects = [System.Windows.DragDropEffects]::None
        }
        $e.Handled = $true
    })
    $control.Add_Drop({
        param($s, $e)
        if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
            $files = $e.Data.GetData([System.Windows.DataFormats]::FileDrop)
            foreach ($f in $files) { Add-AttachmentFile $f }
            Update-AttachmentIndicator
        }
        $e.Handled = $true
    })
}
Setup-DragDrop $script:ChatContainerBorder
Setup-DragDrop $script:InputBox

# ==================== Event Wiring ====================
$script:SendButton.Add_Click({ Send-Message })
$script:StopButton.Add_Click({ Stop-Generation })
$script:AttachButton.Add_Click({ Attach-File })
$script:RemoveFileButton.Add_Click({ Clear-Attachment })
$script:OpenPreviewButton.Add_Click({ Open-CodePreview })
$script:SavePreviewButton.Add_Click({ Save-CodePreview })
$script:SaveAllButton.Add_Click({ Save-AllCode })

$script:InputBox.Add_PreviewKeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
        $mods = $e.KeyboardDevice.Modifiers
        $hasCtrl  = ($mods -band [System.Windows.Input.ModifierKeys]::Control) -ne 0
        $hasShift = ($mods -band [System.Windows.Input.ModifierKeys]::Shift) -ne 0
        if ($hasCtrl) { $e.Handled = $true; Send-Message }
        elseif (-not $hasShift -and -not $script:SendWithCtrlEnter) { $e.Handled = $true; Send-Message }
    }
})

$script:StartOllamaBtn.Add_Click({ Start-OllamaServer })
$script:RefreshButton.Add_Click({ Show-Diagnostics })
$script:ModelsMenuButton.Add_Click({ Show-ManageModelsDialog })
$script:SettingsButton.Add_Click({ Show-SettingsWindow })
$script:ThemeButton.Add_Click({ Toggle-Theme })
$script:DirectionBtn.Add_Click({ Set-Direction (-not $script:IsRtl); Save-AppSettings })
$script:CodePreviewMenuBtn.Add_Click({ Toggle-CodePreview })
$script:ExportButton.Add_Click({ Export-Chat })
$script:SaveLogButton.Add_Click({ Save-SessionLog })
$script:NewChatButton.Add_Click({ New-ChatConversation })
$script:OpenChatButton.Add_Click({ Load-ChatConversation })
$script:SaveChatButton.Add_Click({ Save-ChatConversation })

$script:ClearButton.Add_Click({
    $script:ChatPanel.Children.Clear()
    $script:CodePreviewTabs.Items.Clear()
    $script:AllBubbles.Clear()
    Clear-Attachment
    $script:StatsLabel.Text = ""
    if (-not $script:ClearKeepsContext) {
        $script:ChatHistory.Clear()
    }
    Update-OllamaStatus | Out-Null
})

$script:ExitButton.Add_Click({ $script:Window.Close() })

$script:Window.Add_Loaded({
    Update-OllamaStatus | Out-Null
    $script:InputBox.Focus() | Out-Null
    if ($script:IsDarkMode) {
        $script:IsDarkMode = $false
        Toggle-Theme
    }
    if ($script:IsRtl) { Set-Direction $true } else { Set-Direction $false }
    if ($script:ShowCodePreview -eq $false) { Toggle-CodePreview }
    Refresh-ModelsList | Out-Null
})

$script:Window.Add_Closing({
    if ($script:StreamTimer) { try { $script:StreamTimer.Stop() } catch {} }
    if ($script:StartTimer)  { try { $script:StartTimer.Stop()  } catch {} }
    if ($script:SendPs) {
        try { $script:SendPs.Stop() } catch {}
        try { $script:SendPs.Dispose() } catch {}
    }
    if ($script:StartPs) {
        try { $script:StartPs.Stop() } catch {}
        try { $script:StartPs.Dispose() } catch {}
    }
    Save-AppSettings
    if ($script:OllamaProcess -and -not $script:OllamaProcess.HasExited) {
        try { $script:OllamaProcess.Kill() } catch {}
    }
})

# ==================== Welcome ====================
[void](New-MessageBubble -Sender "System" -Text "Welcome! v0.040 ready (Smart Free Scroll added)." -LightColor "#FFF8E1" -DarkColor "#5A4A1E")

try { [void]$script:Window.ShowDialog() }
catch {
    [System.Windows.MessageBox]::Show("Runtime Error: $($_.Exception.Message)`n`n$($_.ScriptStackTrace)", "Fatal Error")
}
