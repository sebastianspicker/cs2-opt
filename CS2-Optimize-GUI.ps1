#Requires -RunAsAdministrator
# ==============================================================================
#  CS2-Optimize-GUI.ps1  —  WPF Dashboard
#  Launch via START-GUI.bat
# ==============================================================================

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms   # for Clipboard
Add-Type -AssemblyName Microsoft.VisualBasic  # for InputBox

$Script:Root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $MyInvocation.MyCommand.Path -Parent }

. "$Script:Root\config.env.ps1"
. "$Script:Root\helpers.ps1"
. "$Script:Root\helpers\step-catalog.ps1"
. "$Script:Root\helpers\system-analysis.ps1"

# ── Async engine ──────────────────────────────────────────────────────────────
$Script:Pool   = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, 3)
$Script:Pool.Open()
$Script:UISync    = [hashtable]::Synchronized(@{})
$Script:Closing   = $false
$Script:AsyncTimers = [System.Collections.Generic.List[System.Windows.Threading.DispatcherTimer]]::new()

function Invoke-Async {
    param([scriptblock]$Work, [object[]]$WorkArgs = @(), [scriptblock]$OnDone = {})
    $rs = [System.Management.Automation.PowerShell]::Create()
    $rs.RunspacePool = $Script:Pool
    [void]$rs.AddScript($Work)
    foreach ($a in $WorkArgs) { [void]$rs.AddArgument($a) }
    $handle = $rs.BeginInvoke()
    $timer  = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $capturedHandle = $handle
    $capturedRs     = $rs
    $capturedDone   = $OnDone
    $timer.Add_Tick({
        if ($Script:Closing) {
            $timer.Stop()
            try { $capturedRs.Stop(); $capturedRs.Dispose() } catch {}
            return
        }
        if ($capturedHandle.IsCompleted) {
            $timer.Stop()
            try { $capturedRs.EndInvoke($capturedHandle) } catch { $Script:UISync.AsyncError = $_.Exception.Message }
            finally { $capturedRs.Dispose() }
            & $capturedDone
        }
    }.GetNewClosure())
    $Script:AsyncTimers.Add($timer)
    $timer.Start()
}

function New-Brush { [System.Windows.Media.BrushConverter]::new().ConvertFromString($args[0]) }

# ── XAML ──────────────────────────────────────────────────────────────────────
[xml]$XAML = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="CS2 Optimize" Width="1140" Height="720"
    MinWidth="900" MinHeight="560"
    WindowStyle="None" ResizeMode="CanResizeWithGrip"
    Background="#111111">

  <Window.Resources>
    <SolidColorBrush x:Key="BgMain"    Color="#111111"/>
    <SolidColorBrush x:Key="BgSide"    Color="#0d0d0d"/>
    <SolidColorBrush x:Key="BgCard"    Color="#1c1c1c"/>
    <SolidColorBrush x:Key="BgHeader"  Color="#0d0d0d"/>
    <SolidColorBrush x:Key="Accent"    Color="#e8520a"/>
    <SolidColorBrush x:Key="Success"   Color="#22c55e"/>
    <SolidColorBrush x:Key="Warning"   Color="#fbbf24"/>
    <SolidColorBrush x:Key="Danger"    Color="#ef4444"/>
    <SolidColorBrush x:Key="TextPri"   Color="#f0f0f0"/>
    <SolidColorBrush x:Key="TextMuted" Color="#6b7280"/>
    <SolidColorBrush x:Key="Border"    Color="#2a2a2a"/>

    <Style x:Key="NavBtn" TargetType="Button">
      <Setter Property="Background"              Value="Transparent"/>
      <Setter Property="Foreground"              Value="#6b7280"/>
      <Setter Property="BorderThickness"         Value="0"/>
      <Setter Property="Height"                  Value="42"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Padding"                 Value="18,0,0,0"/>
      <Setter Property="FontSize"                Value="13"/>
      <Setter Property="Cursor"                  Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}"
                    BorderThickness="3,0,0,0" BorderBrush="Transparent">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#1a1a1a"/>
                <Setter Property="Foreground" Value="#e5e5e5"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="NavBtnActive" TargetType="Button" BasedOn="{StaticResource NavBtn}">
      <Setter Property="Foreground" Value="#f0f0f0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="#1e1e1e" BorderThickness="3,0,0,0" BorderBrush="#e8520a">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="AccBtn" TargetType="Button">
      <Setter Property="Background"      Value="#e8520a"/>
      <Setter Property="Foreground"      Value="White"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding"         Value="16,7"/>
      <Setter Property="FontSize"        Value="12"/>
      <Setter Property="Cursor"          Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}"
                    CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#cc4708"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Background" Value="#3d3d3d"/>
                <Setter Property="Foreground" Value="#555"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="SecBtn" TargetType="Button">
      <Setter Property="Background"      Value="#252525"/>
      <Setter Property="Foreground"      Value="#e0e0e0"/>
      <Setter Property="BorderBrush"     Value="#3a3a3a"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding"         Value="12,7"/>
      <Setter Property="FontSize"        Value="12"/>
      <Setter Property="Cursor"          Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#303030"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="CardBorder" TargetType="Border">
      <Setter Property="Background"       Value="#1c1c1c"/>
      <Setter Property="BorderBrush"      Value="#2a2a2a"/>
      <Setter Property="BorderThickness"  Value="1"/>
      <Setter Property="CornerRadius"     Value="6"/>
      <Setter Property="Padding"          Value="14"/>
    </Style>

    <Style TargetType="DataGrid">
      <Setter Property="Background"               Value="#161616"/>
      <Setter Property="Foreground"               Value="#e0e0e0"/>
      <Setter Property="BorderThickness"          Value="0"/>
      <Setter Property="RowBackground"            Value="#161616"/>
      <Setter Property="AlternatingRowBackground" Value="#1b1b1b"/>
      <Setter Property="GridLinesVisibility"      Value="Horizontal"/>
      <Setter Property="HorizontalGridLinesBrush" Value="#252525"/>
      <Setter Property="AutoGenerateColumns"      Value="False"/>
      <Setter Property="CanUserAddRows"           Value="False"/>
      <Setter Property="CanUserDeleteRows"        Value="False"/>
      <Setter Property="SelectionMode"            Value="Single"/>
      <Setter Property="FontSize"                 Value="12"/>
      <Setter Property="RowHeight"                Value="28"/>
    </Style>

    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background"      Value="#0f0f0f"/>
      <Setter Property="Foreground"      Value="#6b7280"/>
      <Setter Property="BorderBrush"     Value="#2a2a2a"/>
      <Setter Property="BorderThickness" Value="0,0,0,1"/>
      <Setter Property="Padding"         Value="10,6"/>
      <Setter Property="FontSize"        Value="11"/>
      <Setter Property="FontWeight"      Value="SemiBold"/>
    </Style>

    <Style TargetType="DataGridCell">
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding"         Value="10,0"/>
      <Setter Property="Foreground"      Value="#e0e0e0"/>
    </Style>

    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="#e0e0e0"/>
    </Style>

    <Style TargetType="TextBox">
      <Setter Property="Background"      Value="#1c1c1c"/>
      <Setter Property="Foreground"      Value="#e0e0e0"/>
      <Setter Property="BorderBrush"     Value="#3a3a3a"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding"         Value="8,5"/>
      <Setter Property="FontSize"        Value="12"/>
      <Setter Property="CaretBrush"      Value="#e8520a"/>
    </Style>

    <Style TargetType="ComboBox">
      <Setter Property="Background"      Value="#1c1c1c"/>
      <Setter Property="Foreground"      Value="#e0e0e0"/>
      <Setter Property="BorderBrush"     Value="#3a3a3a"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding"         Value="8,5"/>
      <Setter Property="FontSize"        Value="12"/>
    </Style>

    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#e0e0e0"/>
      <Setter Property="FontSize"   Value="12"/>
    </Style>

    <Style TargetType="RadioButton">
      <Setter Property="Foreground" Value="#e0e0e0"/>
      <Setter Property="FontSize"   Value="12"/>
    </Style>

    <Style TargetType="ProgressBar">
      <Setter Property="Background" Value="#252525"/>
      <Setter Property="Foreground" Value="#e8520a"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Height"     Value="5"/>
    </Style>

    <Style TargetType="Separator">
      <Setter Property="Background" Value="#2a2a2a"/>
    </Style>
  </Window.Resources>

  <!-- Root grid: title bar + body -->
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="38"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <!-- ── Title bar ──────────────────────────────────────────────────────── -->
    <Border Grid.Row="0" x:Name="TitleBar" Background="#090909">
      <Grid>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="14,0">
          <TextBlock Text="CS2" FontSize="14" FontWeight="Bold" Foreground="#e8520a"/>
          <TextBlock Text=" OPTIMIZE" FontSize="14" FontWeight="Bold" Foreground="#f0f0f0"/>
          <TextBlock Text="  v2.1" FontSize="11" Foreground="#374151" VerticalAlignment="Bottom" Margin="0,0,0,1"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="BtnMin"   Content="─" Width="44" Height="38" Background="Transparent" BorderThickness="0" Foreground="#6b7280" FontSize="11" Cursor="Hand"/>
          <Button x:Name="BtnMax"   Content="▢" Width="44" Height="38" Background="Transparent" BorderThickness="0" Foreground="#6b7280" FontSize="11" Cursor="Hand"/>
          <Button x:Name="BtnClose" Content="✕" Width="44" Height="38" Background="Transparent" BorderThickness="0" Foreground="#6b7280" FontSize="12" Cursor="Hand"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- ── Body: sidebar + content ───────────────────────────────────────── -->
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="190"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- Sidebar -->
      <Border Grid.Column="0" Background="#0d0d0d" BorderBrush="#1e1e1e" BorderThickness="0,0,1,0">
        <DockPanel LastChildFill="False">
          <StackPanel DockPanel.Dock="Top" Margin="0,6,0,0">
            <Button x:Name="NavDashboard" Content="⊞   Dashboard"  Style="{StaticResource NavBtnActive}"/>
            <Button x:Name="NavAnalyze"   Content="⌕   Analyze"    Style="{StaticResource NavBtn}"/>
            <Button x:Name="NavOptimize"  Content="⚡   Optimize"   Style="{StaticResource NavBtn}"/>
            <Button x:Name="NavBackup"    Content="⟳   Backup"     Style="{StaticResource NavBtn}"/>
            <Button x:Name="NavBenchmark" Content="◈   Benchmark"  Style="{StaticResource NavBtn}"/>
            <Button x:Name="NavVideo"     Content="▣   Video"      Style="{StaticResource NavBtn}"/>
            <Button x:Name="NavSettings"  Content="⚙   Settings"   Style="{StaticResource NavBtn}"/>
          </StackPanel>
          <StackPanel DockPanel.Dock="Bottom" Margin="14,0,14,14">
            <Separator Margin="0,0,0,10"/>
            <TextBlock x:Name="SbProfile" Text="Profile: —"   FontSize="11" Foreground="#374151"/>
            <TextBlock x:Name="SbDryRun"  Text=""             FontSize="11" Foreground="#e8520a" Margin="0,2,0,0"/>
            <TextBlock x:Name="SbPhase"   Text="Phase: —"     FontSize="11" Foreground="#374151" Margin="0,2,0,0"/>
          </StackPanel>
        </DockPanel>
      </Border>

      <!-- ════ CONTENT PANELS ════ -->
      <Grid Grid.Column="1">

        <!-- ═══ DASHBOARD ═══ -->
        <ScrollViewer x:Name="PanelDashboard" Visibility="Visible" VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="24,18,24,24">
            <TextBlock Text="Dashboard" FontSize="20" FontWeight="SemiBold" Margin="0,0,0,18"/>

            <TextBlock Text="SYSTEM" FontSize="10" FontWeight="SemiBold" Foreground="#374151" Margin="0,0,0,8"/>
            <UniformGrid Columns="4" Margin="0,0,0,10">
              <Border Style="{StaticResource CardBorder}" Margin="0,0,6,0">
                <StackPanel>
                  <TextBlock Text="CPU" FontSize="10" FontWeight="SemiBold" Foreground="#4b5563"/>
                  <TextBlock x:Name="CardCpuName"  Text="…" FontSize="12" FontWeight="SemiBold" Margin="0,5,0,2" TextTrimming="CharacterEllipsis"/>
                  <TextBlock x:Name="CardCpuTier"  Text=""  FontSize="11" Foreground="#e8520a"/>
                  <TextBlock x:Name="CardCpuExtra" Text=""  FontSize="11" Foreground="#6b7280" Margin="0,2,0,0"/>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource CardBorder}" Margin="0,0,6,0">
                <StackPanel>
                  <TextBlock Text="GPU" FontSize="10" FontWeight="SemiBold" Foreground="#4b5563"/>
                  <TextBlock x:Name="CardGpuName"   Text="…" FontSize="12" FontWeight="SemiBold" Margin="0,5,0,2" TextTrimming="CharacterEllipsis"/>
                  <TextBlock x:Name="CardGpuDriver" Text=""  FontSize="11" Foreground="#6b7280"/>
                  <TextBlock x:Name="CardGpuVendor" Text=""  FontSize="11" Foreground="#6b7280" Margin="0,2,0,0"/>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource CardBorder}" Margin="0,0,6,0">
                <StackPanel>
                  <TextBlock Text="RAM" FontSize="10" FontWeight="SemiBold" Foreground="#4b5563"/>
                  <TextBlock x:Name="CardRamSize"  Text="…" FontSize="12" FontWeight="SemiBold" Margin="0,5,0,2"/>
                  <TextBlock x:Name="CardRamSpeed" Text=""  FontSize="11" Foreground="#6b7280"/>
                  <TextBlock x:Name="CardRamXmp"   Text=""  FontSize="11" Margin="0,2,0,0"/>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource CardBorder}">
                <StackPanel>
                  <TextBlock Text="NETWORK" FontSize="10" FontWeight="SemiBold" Foreground="#4b5563"/>
                  <TextBlock x:Name="CardNicName"  Text="…" FontSize="12" FontWeight="SemiBold" Margin="0,5,0,2" TextTrimming="CharacterEllipsis"/>
                  <TextBlock x:Name="CardNicSpeed" Text=""  FontSize="11" Foreground="#6b7280"/>
                  <TextBlock x:Name="CardNicType"  Text=""  FontSize="11" Margin="0,2,0,0"/>
                </StackPanel>
              </Border>
            </UniformGrid>

            <UniformGrid Columns="2" Margin="0,0,0,20">
              <Border Style="{StaticResource CardBorder}" Margin="0,0,6,0">
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>
                  <StackPanel>
                    <TextBlock Text="OS" FontSize="10" FontWeight="SemiBold" Foreground="#4b5563"/>
                    <TextBlock x:Name="CardOsName"  Text="…" FontSize="12" FontWeight="SemiBold" Margin="0,5,0,2"/>
                    <TextBlock x:Name="CardOsBuild" Text=""  FontSize="11" Foreground="#6b7280"/>
                    <TextBlock x:Name="CardOsHags"  Text=""  FontSize="11" Margin="0,2,0,0"/>
                  </StackPanel>
                  <StackPanel Grid.Column="1" Margin="12,0,0,0">
                    <TextBlock Text="CS2" FontSize="10" FontWeight="SemiBold" Foreground="#4b5563"/>
                    <TextBlock x:Name="CardCs2Status" Text="…" FontSize="12" FontWeight="SemiBold" Margin="0,5,0,2"/>
                    <TextBlock x:Name="CardCs2Cfg"    Text=""  FontSize="11" Foreground="#6b7280"/>
                    <TextBlock x:Name="CardCs2Video"  Text=""  FontSize="11" Foreground="#6b7280" Margin="0,2,0,0"/>
                  </StackPanel>
                </Grid>
              </Border>
              <Border Style="{StaticResource CardBorder}">
                <StackPanel>
                  <TextBlock Text="PERFORMANCE" FontSize="10" FontWeight="SemiBold" Foreground="#4b5563"/>
                  <TextBlock x:Name="DashPerfBaseline" Text="No benchmark data yet" FontSize="12" Foreground="#6b7280" Margin="0,8,0,0"/>
                  <TextBlock x:Name="DashPerfLatest"   Text=""  FontSize="12" Foreground="#6b7280" Margin="0,3,0,0"/>
                  <TextBlock x:Name="DashPerfDelta"    Text=""  FontSize="14" FontWeight="SemiBold" Foreground="#22c55e" Margin="0,6,0,0"/>
                </StackPanel>
              </Border>
            </UniformGrid>

            <TextBlock Text="OPTIMIZATION STATUS" FontSize="10" FontWeight="SemiBold" Foreground="#374151" Margin="0,0,0,8"/>
            <Border Style="{StaticResource CardBorder}" Margin="0,0,0,20">
              <StackPanel>
                <Grid Margin="0,0,0,10">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="70"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="55"/>
                  </Grid.ColumnDefinitions>
                  <TextBlock Text="Phase 1" FontSize="11" Foreground="#6b7280" VerticalAlignment="Center"/>
                  <ProgressBar Grid.Column="1" x:Name="ProgressP1" Minimum="0" Maximum="38" Value="0" Margin="8,0" VerticalAlignment="Center"/>
                  <TextBlock Grid.Column="2" x:Name="ProgressP1Txt" Text="0 / 38" FontSize="11" Foreground="#6b7280" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                </Grid>
                <Grid Margin="0,0,0,10">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="70"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="55"/>
                  </Grid.ColumnDefinitions>
                  <TextBlock Text="Phase 3" FontSize="11" Foreground="#6b7280" VerticalAlignment="Center"/>
                  <ProgressBar Grid.Column="1" x:Name="ProgressP3" Minimum="0" Maximum="13" Value="0" Margin="8,0" VerticalAlignment="Center"/>
                  <TextBlock Grid.Column="2" x:Name="ProgressP3Txt" Text="0 / 13" FontSize="11" Foreground="#6b7280" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                </Grid>
                <TextBlock x:Name="DashIssueHint" Text="" FontSize="11" Foreground="#fbbf24"/>
              </StackPanel>
            </Border>

            <TextBlock Text="QUICK ACTIONS" FontSize="10" FontWeight="SemiBold" Foreground="#374151" Margin="0,0,0,8"/>
            <WrapPanel>
              <Button x:Name="BtnDashAnalyze"   Content="⌕  Analyze System"    Style="{StaticResource AccBtn}" Margin="0,0,8,8"/>
              <Button x:Name="BtnDashVerify"    Content="✓  Verify Settings"   Style="{StaticResource SecBtn}" Margin="0,0,8,8"/>
              <Button x:Name="BtnDashBackup"    Content="⟳  Backup Now"        Style="{StaticResource SecBtn}" Margin="0,0,8,8"/>
              <Button x:Name="BtnDashPhase1"    Content="▶  Run Phase 1"       Style="{StaticResource SecBtn}" Margin="0,0,8,8"/>
              <Button x:Name="BtnDashLaunchCs2" Content="⚡  Launch CS2"        Style="{StaticResource SecBtn}" Margin="0,0,8,8"/>
            </WrapPanel>
          </StackPanel>
        </ScrollViewer>

        <!-- ═══ ANALYZE ═══ -->
        <Grid x:Name="PanelAnalyze" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <Border Grid.Row="0" Background="#0d0d0d" BorderBrush="#1e1e1e" BorderThickness="0,0,0,1" Padding="24,12">
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <StackPanel>
                <TextBlock Text="Analyze System" FontSize="18" FontWeight="SemiBold"/>
                <TextBlock x:Name="AnalyzeScanTime" Text="Not yet scanned" FontSize="11" Foreground="#4b5563" Margin="0,3,0,0"/>
              </StackPanel>
              <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                <TextBlock x:Name="AnalyzeSummary" Text="" FontSize="12" Foreground="#6b7280" VerticalAlignment="Center" Margin="0,0,14,0"/>
                <Button x:Name="BtnRunAnalysis" Content="▶  Run Full Scan" Style="{StaticResource AccBtn}"/>
              </StackPanel>
            </Grid>
          </Border>
          <DataGrid Grid.Row="1" x:Name="AnalysisGrid" SelectionUnit="FullRow">
            <DataGrid.Columns>
              <DataGridTextColumn Header="Category"    Binding="{Binding Category}" Width="90"/>
              <DataGridTextColumn Header="Group"       Binding="{Binding Group}"    Width="100"/>
              <DataGridTextColumn Header="Item"        Binding="{Binding Item}"     Width="*"/>
              <DataGridTextColumn Header="Current"     Binding="{Binding Current}"  Width="130"/>
              <DataGridTextColumn Header="Recommended" Binding="{Binding Recommended}" Width="120"/>
              <DataGridTemplateColumn Header="Status"  Width="85">
                <DataGridTemplateColumn.CellTemplate>
                  <DataTemplate>
                    <TextBlock Text="{Binding StatusLabel}" Foreground="{Binding StatusColor}"
                               FontWeight="SemiBold" VerticalAlignment="Center" Margin="6,0"/>
                  </DataTemplate>
                </DataGridTemplateColumn.CellTemplate>
              </DataGridTemplateColumn>
              <DataGridTextColumn Header="Step"   Binding="{Binding StepRef}" Width="65"/>
              <DataGridTextColumn Header="Impact" Binding="{Binding Impact}"  Width="200"/>
            </DataGrid.Columns>
          </DataGrid>
          <Border Grid.Row="2" Background="#0d0d0d" BorderBrush="#1e1e1e" BorderThickness="0,1,0,0" Padding="24,10">
            <StackPanel Orientation="Horizontal">
              <Button x:Name="BtnAnalyzeGotoOpt" Content="→  Open in Optimize" Style="{StaticResource AccBtn}" Margin="0,0,8,0"/>
              <Button x:Name="BtnAnalyzeExport"  Content="⤓  Export Report"    Style="{StaticResource SecBtn}"/>
            </StackPanel>
          </Border>
        </Grid>

        <!-- ═══ OPTIMIZE ═══ -->
        <Grid x:Name="PanelOptimize" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <Border Grid.Row="0" Background="#0d0d0d" BorderBrush="#1e1e1e" BorderThickness="0,0,0,1" Padding="24,12">
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <StackPanel>
                <TextBlock Text="Optimize" FontSize="18" FontWeight="SemiBold"/>
                <TextBlock Text="Steps run in terminal windows — safe, nothing applied silently" FontSize="11" Foreground="#4b5563" Margin="0,3,0,0"/>
              </StackPanel>
              <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                <ComboBox x:Name="OptFilterCat"    Width="110" Margin="0,0,8,0"/>
                <ComboBox x:Name="OptFilterStatus" Width="110" Margin="0,0,8,0"/>
                <Button x:Name="BtnOptPhase1" Content="▶  Phase 1" Style="{StaticResource AccBtn}" Margin="0,0,8,0"/>
                <Button x:Name="BtnOptPhase3" Content="▶  Phase 3" Style="{StaticResource SecBtn}"/>
              </StackPanel>
            </Grid>
          </Border>
          <DataGrid Grid.Row="1" x:Name="OptimizeGrid" SelectionUnit="FullRow">
            <DataGrid.Columns>
              <DataGridTextColumn Header="Ph"    Binding="{Binding PhLabel}"    Width="30"/>
              <DataGridTextColumn Header="Step"  Binding="{Binding StepLabel}"  Width="40"/>
              <DataGridTextColumn Header="Cat."  Binding="{Binding Category}"   Width="80"/>
              <DataGridTextColumn Header="Title" Binding="{Binding Title}"      Width="*"/>
              <DataGridTemplateColumn Header="Tier" Width="38">
                <DataGridTemplateColumn.CellTemplate>
                  <DataTemplate>
                    <TextBlock Text="{Binding TierLabel}" Foreground="{Binding TierColor}"
                               FontWeight="SemiBold" VerticalAlignment="Center" Margin="4,0"/>
                  </DataTemplate>
                </DataGridTemplateColumn.CellTemplate>
              </DataGridTemplateColumn>
              <DataGridTemplateColumn Header="Risk" Width="80">
                <DataGridTemplateColumn.CellTemplate>
                  <DataTemplate>
                    <TextBlock Text="{Binding Risk}" Foreground="{Binding RiskColor}"
                               VerticalAlignment="Center" Margin="6,0"/>
                  </DataTemplate>
                </DataGridTemplateColumn.CellTemplate>
              </DataGridTemplateColumn>
              <DataGridTemplateColumn Header="Status" Width="90">
                <DataGridTemplateColumn.CellTemplate>
                  <DataTemplate>
                    <TextBlock Text="{Binding StatusLabel}" Foreground="{Binding StatusColor}"
                               FontWeight="SemiBold" VerticalAlignment="Center" Margin="6,0"/>
                  </DataTemplate>
                </DataGridTemplateColumn.CellTemplate>
              </DataGridTemplateColumn>
              <DataGridTextColumn Header="Reboot?" Binding="{Binding RebootLabel}" Width="60"/>
              <DataGridTextColumn Header="Expected" Binding="{Binding EstLabel}"   Width="110"/>
            </DataGrid.Columns>
          </DataGrid>
          <Border Grid.Row="2" Background="#0d0d0d" BorderBrush="#1e1e1e" BorderThickness="0,1,0,0" Padding="24,10">
            <StackPanel Orientation="Horizontal">
              <Button x:Name="BtnOptFullSetup" Content="▶  Full Setup (Phase 1 → 2 → 3)" Style="{StaticResource AccBtn}" Margin="0,0,8,0"/>
              <Button x:Name="BtnOptVerify"    Content="✓  Verify All"                   Style="{StaticResource SecBtn}"/>
            </StackPanel>
          </Border>
        </Grid>

        <!-- ═══ BACKUP ═══ -->
        <Grid x:Name="PanelBackup" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <Border Grid.Row="0" Background="#0d0d0d" BorderBrush="#1e1e1e" BorderThickness="0,0,0,1" Padding="24,12">
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <StackPanel>
                <TextBlock Text="Backup &amp; Restore" FontSize="18" FontWeight="SemiBold"/>
                <TextBlock x:Name="BackupSummary" Text="Loading…" FontSize="11" Foreground="#4b5563" Margin="0,3,0,0"/>
              </StackPanel>
              <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                <Button x:Name="BtnBackupRefresh" Content="↺  Refresh"      Style="{StaticResource SecBtn}" Margin="0,0,8,0"/>
                <Button x:Name="BtnBackupExport"  Content="⤓  Export JSON"  Style="{StaticResource SecBtn}" Margin="0,0,8,0"/>
                <Button x:Name="BtnRestoreAll"    Content="↺  Restore All"  Style="{StaticResource AccBtn}"/>
              </StackPanel>
            </Grid>
          </Border>
          <DataGrid Grid.Row="1" x:Name="BackupGrid" SelectionUnit="FullRow">
            <DataGrid.Columns>
              <DataGridTextColumn Header="Step"     Binding="{Binding Step}"      Width="160"/>
              <DataGridTextColumn Header="Type"     Binding="{Binding Type}"      Width="80"/>
              <DataGridTextColumn Header="Key"      Binding="{Binding Key}"       Width="*"/>
              <DataGridTextColumn Header="Original" Binding="{Binding Original}"  Width="120"/>
              <DataGridTextColumn Header="Timestamp" Binding="{Binding Timestamp}" Width="130"/>
            </DataGrid.Columns>
          </DataGrid>
          <Border Grid.Row="2" Background="#0d0d0d" BorderBrush="#1e1e1e" BorderThickness="0,1,0,0" Padding="24,10">
            <StackPanel Orientation="Horizontal">
              <Button x:Name="BtnRestoreStep" Content="↺  Restore Selected Step" Style="{StaticResource AccBtn}" Margin="0,0,8,0"/>
              <Button x:Name="BtnClearBackup" Content="🗑  Clear All"             Style="{StaticResource SecBtn}"/>
            </StackPanel>
          </Border>
        </Grid>

        <!-- ═══ BENCHMARK ═══ -->
        <Grid x:Name="PanelBenchmark" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="180"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <Border Grid.Row="0" Background="#0d0d0d" BorderBrush="#1e1e1e" BorderThickness="0,0,0,1" Padding="24,12">
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <TextBlock Text="Benchmark &amp; FPS Cap" FontSize="18" FontWeight="SemiBold" VerticalAlignment="Center"/>
              <Button Grid.Column="1" x:Name="BtnBenchAdd" Content="+  Add Result" Style="{StaticResource AccBtn}"/>
            </Grid>
          </Border>
          <Border Grid.Row="1" Background="#141414" BorderBrush="#1e1e1e" BorderThickness="0,0,0,1">
            <Canvas x:Name="BenchChart" Margin="50,14,20,26"/>
          </Border>
          <DataGrid Grid.Row="2" x:Name="BenchGrid" SelectionUnit="FullRow">
            <DataGrid.Columns>
              <DataGridTextColumn Header="#"       Binding="{Binding Index}"    Width="35"/>
              <DataGridTextColumn Header="Date"    Binding="{Binding Date}"     Width="90"/>
              <DataGridTextColumn Header="Label"   Binding="{Binding Label}"    Width="*"/>
              <DataGridTextColumn Header="Avg FPS" Binding="{Binding AvgFps}"   Width="70"/>
              <DataGridTextColumn Header="1% Low"  Binding="{Binding P1Fps}"    Width="65"/>
              <DataGridTemplateColumn Header="Δ Avg" Width="65">
                <DataGridTemplateColumn.CellTemplate>
                  <DataTemplate>
                    <TextBlock Text="{Binding DeltaAvg}" Foreground="{Binding DeltaColor}" FontWeight="SemiBold" VerticalAlignment="Center" Margin="6,0"/>
                  </DataTemplate>
                </DataGridTemplateColumn.CellTemplate>
              </DataGridTemplateColumn>
              <DataGridTemplateColumn Header="Δ 1%" Width="65">
                <DataGridTemplateColumn.CellTemplate>
                  <DataTemplate>
                    <TextBlock Text="{Binding DeltaP1}" Foreground="{Binding DeltaColor}" FontWeight="SemiBold" VerticalAlignment="Center" Margin="6,0"/>
                  </DataTemplate>
                </DataGridTemplateColumn.CellTemplate>
              </DataGridTemplateColumn>
            </DataGrid.Columns>
          </DataGrid>
          <!-- FPS Cap bar -->
          <Border Grid.Row="3" Background="#0d0d0d" BorderBrush="#1e1e1e" BorderThickness="0,1,0,0" Padding="24,10">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="220"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <TextBlock Grid.Column="0" Text="FPS Cap " FontSize="13" FontWeight="SemiBold" VerticalAlignment="Center"/>
              <TextBox   Grid.Column="1" x:Name="BenchVprof" ToolTip="Paste [VProf] FPS: Avg=… line here"/>
              <Button    Grid.Column="2" x:Name="BtnBenchParse" Content="Parse" Style="{StaticResource SecBtn}" Margin="8,0"/>
              <TextBlock Grid.Column="3" x:Name="BenchCapLabel" Text="" VerticalAlignment="Center" FontSize="12" Foreground="#6b7280" Margin="16,0,8,0"/>
              <TextBlock Grid.Column="4" x:Name="BenchCapValue" Text="" VerticalAlignment="Center" FontSize="20" FontWeight="Bold" Foreground="#e8520a" Margin="0,0,14,0"/>
              <Button    Grid.Column="6" x:Name="BtnBenchCopy" Content="📋  Copy Cap" Style="{StaticResource SecBtn}"/>
            </Grid>
          </Border>
        </Grid>

        <!-- ═══ VIDEO ═══ -->
        <Grid x:Name="PanelVideo" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <Border Grid.Row="0" Background="#0d0d0d" BorderBrush="#1e1e1e" BorderThickness="0,0,0,1" Padding="24,12">
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <StackPanel>
                <TextBlock Text="Video Settings" FontSize="18" FontWeight="SemiBold"/>
                <TextBlock x:Name="VideoTxtPath" Text="Searching for video.txt…" FontSize="11" Foreground="#4b5563" Margin="0,3,0,0"/>
              </StackPanel>
              <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                <ComboBox x:Name="VideoTierPicker" Width="100" Margin="0,0,8,0"/>
                <Button   x:Name="BtnVideoWrite"   Content="Write video.txt" Style="{StaticResource AccBtn}"/>
              </StackPanel>
            </Grid>
          </Border>
          <DataGrid Grid.Row="1" x:Name="VideoGrid" SelectionUnit="FullRow">
            <DataGrid.Columns>
              <DataGridTextColumn Header="Setting"     Binding="{Binding Setting}"     Width="*"/>
              <DataGridTextColumn Header="Your Value"  Binding="{Binding YourValue}"   Width="120"/>
              <DataGridTextColumn Header="Recommended" Binding="{Binding Recommended}" Width="120"/>
              <DataGridTemplateColumn Header="Status"  Width="80">
                <DataGridTemplateColumn.CellTemplate>
                  <DataTemplate>
                    <TextBlock Text="{Binding StatusLabel}" Foreground="{Binding StatusColor}"
                               FontWeight="SemiBold" VerticalAlignment="Center" Margin="6,0"/>
                  </DataTemplate>
                </DataGridTemplateColumn.CellTemplate>
              </DataGridTemplateColumn>
              <DataGridTextColumn Header="Notes" Binding="{Binding Notes}" Width="220"/>
            </DataGrid.Columns>
          </DataGrid>
          <Border Grid.Row="2" Background="#0d0d0d" BorderBrush="#1e1e1e" BorderThickness="0,1,0,0" Padding="24,10">
            <StackPanel Orientation="Horizontal">
              <TextBlock x:Name="VideoSummary" Text="" VerticalAlignment="Center" Margin="0,0,16,0" FontSize="12" Foreground="#6b7280"/>
              <Button x:Name="BtnVideoWriteFooter" Content="Write video.txt  (renames original → .bak)" Style="{StaticResource AccBtn}"/>
            </StackPanel>
          </Border>
        </Grid>

        <!-- ═══ SETTINGS ═══ -->
        <ScrollViewer x:Name="PanelSettings" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="24,18,24,24" MaxWidth="580">
            <TextBlock Text="Settings" FontSize="20" FontWeight="SemiBold" Margin="0,0,0,20"/>

            <TextBlock Text="PROFILE" FontSize="10" FontWeight="SemiBold" Foreground="#374151" Margin="0,0,0,8"/>
            <Border Style="{StaticResource CardBorder}" Margin="0,0,0,20">
              <StackPanel>
                <RadioButton x:Name="RadioSafe"        GroupName="Profile" Content="Safe  —  Proven T1 tweaks only. Auto-applied. No risk."          Margin="0,0,0,8"/>
                <RadioButton x:Name="RadioRecommended" GroupName="Profile" Content="Recommended  —  T1+T2 moderate tweaks with confirmation prompts." Margin="0,0,0,8"/>
                <RadioButton x:Name="RadioCompetitive" GroupName="Profile" Content="Competitive  —  All tiers. Everything the suite offers."          Margin="0,0,0,8"/>
                <RadioButton x:Name="RadioCustom"      GroupName="Profile" Content="Custom  —  Full detail card for every step. Manual approval."/>
              </StackPanel>
            </Border>

            <CheckBox x:Name="ChkDryRun" Content="DRY-RUN mode  —  preview all changes without applying anything" Margin="0,0,0,20"/>

            <TextBlock Text="REGION" FontSize="10" FontWeight="SemiBold" Foreground="#374151" Margin="0,0,0,8"/>
            <Border Style="{StaticResource CardBorder}" Margin="0,0,0,20">
              <StackPanel>
                <TextBlock Text="Affects mm_dedicated_search_maxping in optimization.cfg" FontSize="11" Foreground="#6b7280" Margin="0,0,0,10"/>
                <RadioButton x:Name="RegEU"     GroupName="Region" Content="Europe (40 ms)"        Margin="0,0,0,6"/>
                <RadioButton x:Name="RegNA"     GroupName="Region" Content="North America (80 ms)" Margin="0,0,0,6"/>
                <RadioButton x:Name="RegAsia"   GroupName="Region" Content="Asia-Pacific (150 ms)" Margin="0,0,0,6"/>
                <StackPanel Orientation="Horizontal">
                  <RadioButton x:Name="RegCustom" GroupName="Region" Content="Custom:" VerticalAlignment="Center"/>
                  <TextBox x:Name="RegCustomVal" Width="60" Margin="8,0,4,0" Text="80"/>
                  <TextBlock Text=" ms" Foreground="#6b7280" VerticalAlignment="Center"/>
                </StackPanel>
              </StackPanel>
            </Border>

            <TextBlock Text="FIRST-TIME SETUP" FontSize="10" FontWeight="SemiBold" Foreground="#374151" Margin="0,0,0,8"/>
            <Border Style="{StaticResource CardBorder}" Margin="0,0,0,20">
              <StackPanel>
                <TextBlock TextWrapping="Wrap" Foreground="#9ca3af" FontSize="12" Margin="0,0,0,12"
                           Text="First-time optimization requires all 3 phases in sequence. Phases 1→2→3 require reboots and run in terminal. Phase 2 runs in Safe Mode for GPU driver replacement."/>
                <Button x:Name="BtnSettingsPhase1" Content="▶  Launch Full Setup (Phase 1)" Style="{StaticResource AccBtn}" HorizontalAlignment="Left"/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <TextBlock Text="CS2 Optimization Suite  v2.1" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,4"/>
                <TextBlock Text="MIT License · github.com/…/cs2-opt" FontSize="11" Foreground="#4b5563"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>

      </Grid><!-- end content panels -->
    </Grid><!-- end body grid -->
  </Grid><!-- end root grid -->
</Window>
'@

# ── Load window ───────────────────────────────────────────────────────────────
$reader = [System.Xml.XmlNodeReader]::new($XAML)
$Window = [Windows.Markup.XamlReader]::Load($reader)

# ── Named element shortcuts ───────────────────────────────────────────────────
function El { $Window.FindName($args[0]) }

# ── Window chrome ─────────────────────────────────────────────────────────────
(El "TitleBar").Add_MouseLeftButtonDown({ $Window.DragMove() })
(El "BtnMin").Add_Click({ $Window.WindowState = "Minimized" })
(El "BtnMax").Add_Click({ $Window.WindowState = if ($Window.WindowState -eq "Maximized") { "Normal" } else { "Maximized" } })
(El "BtnClose").Add_Click({ $Window.Close() })

# ── Navigation ────────────────────────────────────────────────────────────────
$Script:AllPanels = "PanelDashboard","PanelAnalyze","PanelOptimize","PanelBackup","PanelBenchmark","PanelVideo","PanelSettings"
$Script:NavMap    = @{
    "PanelDashboard"  = "NavDashboard"
    "PanelAnalyze"    = "NavAnalyze"
    "PanelOptimize"   = "NavOptimize"
    "PanelBackup"     = "NavBackup"
    "PanelBenchmark"  = "NavBenchmark"
    "PanelVideo"      = "NavVideo"
    "PanelSettings"   = "NavSettings"
}
$Script:ActivePanel = "PanelDashboard"

$ActiveStyle   = $Window.Resources["NavBtnActive"]
$InactiveStyle = $Window.Resources["NavBtn"]

function Switch-Panel {
    param([string]$PanelName, [scriptblock]$OnSwitch = $null)
    foreach ($p in $Script:AllPanels) {
        (El $p).Visibility = if ($p -eq $PanelName) { "Visible" } else { "Collapsed" }
    }
    foreach ($kv in $Script:NavMap.GetEnumerator()) {
        (El $kv.Value).Style = if ($kv.Key -eq $PanelName) { $ActiveStyle } else { $InactiveStyle }
    }
    $Script:ActivePanel = $PanelName
    if ($OnSwitch) { & $OnSwitch }
}

(El "NavDashboard").Add_Click({ Switch-Panel "PanelDashboard"; Load-Dashboard })
(El "NavAnalyze"  ).Add_Click({ Switch-Panel "PanelAnalyze" ; Start-Analysis })
(El "NavOptimize" ).Add_Click({ Switch-Panel "PanelOptimize" ; Load-Optimize  })
(El "NavBackup"   ).Add_Click({ Switch-Panel "PanelBackup"   ; Load-Backup    })
(El "NavBenchmark").Add_Click({ Switch-Panel "PanelBenchmark"; Load-Benchmark })
(El "NavVideo"    ).Add_Click({ Switch-Panel "PanelVideo"    ; Load-Video     })
(El "NavSettings" ).Add_Click({ Switch-Panel "PanelSettings" ; Load-Settings  })

# ── Sidebar status helpers ────────────────────────────────────────────────────
function Update-SidebarStatus {
    $state = $null
    try { if (Test-Path $CFG_StateFile) { $state = Get-Content $CFG_StateFile -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } } catch {}
    $prof = if ($state) { $state.profile } else { "—" }
    $dry  = if ($state -and $state.mode -eq "DRY-RUN") { "DRY-RUN ON" } else { "" }
    $Window.Dispatcher.Invoke({
        (El "SbProfile").Text = "Profile: $prof"
        (El "SbDryRun" ).Text = $dry
    })
}

# ── Load panel functions and event handlers ─────────────────────────────────
. "$Script:Root\helpers\gui-panels.ps1"

# ══════════════════════════════════════════════════════════════════════════════
# STARTUP
# ══════════════════════════════════════════════════════════════════════════════
$Window.Add_Loaded({
    Update-SidebarStatus
    Load-Dashboard
})

$Window.Add_Closed({
    $Script:Closing = $true
    foreach ($t in $Script:AsyncTimers) { try { $t.Stop() } catch {} }
    try { $Script:Pool.Close(); $Script:Pool.Dispose() } catch {}
})

$Window.ShowDialog() | Out-Null
