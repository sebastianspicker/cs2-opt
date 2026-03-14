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
$Script:UISync = [hashtable]::Synchronized(@{})

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
        if ($capturedHandle.IsCompleted) {
            $timer.Stop()
            try { $capturedRs.EndInvoke($capturedHandle) } catch {}
            & $capturedDone
        }
    }.GetNewClosure())
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
    try { if (Test-Path $CFG_StateFile) { $state = Get-Content $CFG_StateFile | ConvertFrom-Json } } catch {}
    $prof = if ($state) { $state.profile } else { "—" }
    $dry  = if ($state -and $state.dryRun) { "DRY-RUN ON" } else { "" }
    $Window.Dispatcher.Invoke({
        (El "SbProfile").Text = "Profile: $prof"
        (El "SbDryRun" ).Text = $dry
    })
}

# ══════════════════════════════════════════════════════════════════════════════
# DASHBOARD
# ══════════════════════════════════════════════════════════════════════════════
function Load-Dashboard {
    # Progress from progress.json
    try {
        $prog = Load-Progress
        if ($prog) {
            $p1Done = if ($prog.phase -eq 1) { ($prog.completedSteps | Where-Object { $_ -le 38 }).Count } else { 38 }
            $p3Done = if ($prog.phase -eq 3) { ($prog.completedSteps | Where-Object { $_ -le 13 }).Count } else { 0 }
            $Window.Dispatcher.Invoke({
                (El "ProgressP1").Value   = $p1Done
                (El "ProgressP1Txt").Text = "$p1Done / 38"
                (El "ProgressP3").Value   = $p3Done
                (El "ProgressP3Txt").Text = "$p3Done / 13"
            })
        }
    } catch {}

    # Benchmark history
    try {
        $hist = Get-BenchmarkHistory
        if ($hist -and $hist.Count -ge 2) {
            $first = $hist[0]; $last = $hist[-1]
            $dAvg  = if ($first.avgFps -gt 0) { [math]::Round(($last.avgFps - $first.avgFps) / $first.avgFps * 100, 1) } else { 0 }
            $dP1   = if ($first.p1Fps -gt 0)  { [math]::Round(($last.p1Fps  - $first.p1Fps)  / $first.p1Fps  * 100, 1) } else { 0 }
            $Window.Dispatcher.Invoke({
                (El "DashPerfBaseline").Text = "Baseline:  avg $($first.avgFps) fps   1%low $($first.p1Fps) fps"
                (El "DashPerfLatest"  ).Text = "Latest:    avg $($last.avgFps) fps   1%low $($last.p1Fps) fps"
                $sign   = if ($dAvg -gt 0) { "+" } else { "" }
                $signP1 = if ($dP1  -gt 0) { "+" } else { "" }
                (El "DashPerfDelta"   ).Text = "Δ avg: ${sign}${dAvg}%   Δ 1%low: ${signP1}${dP1}%"
                (El "DashPerfDelta"   ).Foreground = if ($dAvg -gt 0) { New-Brush "#22c55e" } else { New-Brush "#ef4444" }
            })
        } elseif ($hist -and $hist.Count -eq 1) {
            $Window.Dispatcher.Invoke({ (El "DashPerfBaseline").Text = "Baseline: avg $($hist[0].avgFps) fps  1%low $($hist[0].p1Fps) fps" })
        }
    } catch {}

    # Hardware (async)
    Invoke-Async -Work {
        param($ScriptRoot, $UISync)
        . "$ScriptRoot\config.env.ps1"
        . "$ScriptRoot\helpers.ps1"
        try {
            $cpu  = (Get-CimInstance Win32_Processor -Property Name -ErrorAction SilentlyContinue | Select-Object -First 1).Name
            $gpu  = Get-NvidiaDriverVersion
            $gpuN = if ($gpu) { $gpu.Name } else {
                (Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1).Caption }
            $gpuD = if ($gpu) { "Driver $($gpu.Version)" } else { "" }
            $ram  = Get-RamInfo
            $dc   = Test-DualChannel
            $nic  = Get-ActiveNicAdapter
            $os   = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
            $hags = try { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" -ErrorAction Stop).HwSchMode } catch { $null }
            $cs2  = Get-CS2InstallPath
            $stPath = if ($ScriptRoot) { (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath } else { $null }
            $vtxt = if ($stPath) { Get-ChildItem "$stPath\userdata\*\730\local\cfg\video.txt" -ErrorAction SilentlyContinue | Select-Object -First 1 } else { $null }
            $optExists = if ($cs2) { Test-Path "$cs2\game\csgo\cfg\optimization.cfg" } else { $false }
            $UISync.Hw = @{
                CpuName  = $cpu
                GpuName  = $gpuN; GpuDriver = $gpuD
                RamGb    = if ($ram) { "$($ram.TotalGB) GB" } else { "?" }
                RamSpeed = if ($ram) { "$($ram.ActiveMhz) MHz$(if ($ram.XmpActive) {' XMP'} else {' (JEDEC)'})" } else { "" }
                RamXmp   = if ($ram) { if ($ram.XmpActive) { "✓ XMP active" } else { "⚠ XMP not active" } } else { "" }
                RamXmpOk = if ($ram) { $ram.XmpActive } else { $false }
                DualCh   = if ($dc) { $dc.Reason } else { "" }
                DualChOk = if ($dc) { $dc.DualChannel } else { $false }
                NicName  = if ($nic) { $nic.Name } else { "Not found" }
                NicSpeed = if ($nic) { "$([math]::Round($nic.LinkSpeed/1e6)) Mbps" } else { "" }
                NicType  = if ($nic) { "✓ Wired" } else { "⚠ No active wired NIC" }
                NicOk    = ($null -ne $nic)
                OsName   = if ($os) { $os.Caption -replace "Microsoft Windows ", "Windows " } else { "?" }
                OsBuild  = if ($os) { "Build $($os.BuildNumber)" } else { "" }
                HagsStr  = switch ($hags) { 2 {"HAGS: Enabled"} 1 {"HAGS: Disabled"} $null {"HAGS: Not set"} default {"HAGS: $hags"} }
                Cs2Found = ($null -ne $cs2)
                Cs2Path  = if ($cs2) { "CS2 installed" } else { "CS2 not found" }
                OptCfg   = if ($optExists) { "optimization.cfg: present" } else { "optimization.cfg: missing" }
                VideoTxt = if ($vtxt) { "video.txt: present" } else { "video.txt: missing" }
                OptOk    = $optExists
                VtxtOk   = ($null -ne $vtxt)
            }
        } catch { $UISync.HwErr = $_.Exception.Message }
        $UISync.HwDone = $true
    } -WorkArgs @($Script:Root, $Script:UISync) -OnDone {
        $hw = $Script:UISync.Hw
        if (-not $hw) { return }
        (El "CardCpuName" ).Text = $hw.CpuName ?? "Unknown CPU"
        (El "CardCpuTier" ).Text = ""
        (El "CardCpuExtra").Text = ""
        (El "CardGpuName"  ).Text = $hw.GpuName   ?? "Unknown GPU"
        (El "CardGpuDriver").Text = $hw.GpuDriver
        (El "CardGpuVendor").Text = ""
        (El "CardRamSize" ).Text = $hw.RamGb
        (El "CardRamSpeed").Text = $hw.RamSpeed
        (El "CardRamXmp"  ).Text = $hw.RamXmp
        (El "CardRamXmp"  ).Foreground = if ($hw.RamXmpOk) { New-Brush "#22c55e" } else { New-Brush "#fbbf24" }
        (El "CardNicName" ).Text = $hw.NicName
        (El "CardNicSpeed").Text = $hw.NicSpeed
        (El "CardNicType" ).Text = $hw.NicType
        (El "CardNicType" ).Foreground = if ($hw.NicOk) { New-Brush "#22c55e" } else { New-Brush "#fbbf24" }
        (El "CardOsName"  ).Text = $hw.OsName
        (El "CardOsBuild" ).Text = $hw.OsBuild
        (El "CardOsHags"  ).Text = $hw.HagsStr
        (El "CardCs2Status").Text = $hw.Cs2Path
        (El "CardCs2Status").Foreground = if ($hw.Cs2Found) { New-Brush "#22c55e" } else { New-Brush "#ef4444" }
        (El "CardCs2Cfg"  ).Text = $hw.OptCfg
        (El "CardCs2Cfg"  ).Foreground = if ($hw.OptOk)  { New-Brush "#22c55e" } else { New-Brush "#fbbf24" }
        (El "CardCs2Video").Text = $hw.VideoTxt
        (El "CardCs2Video").Foreground = if ($hw.VtxtOk) { New-Brush "#22c55e" } else { New-Brush "#fbbf24" }
    }.GetNewClosure()
}

# Quick action buttons
(El "BtnDashAnalyze"  ).Add_Click({ Switch-Panel "PanelAnalyze"; Start-Analysis })
(El "BtnDashVerify"   ).Add_Click({ Launch-Terminal "Verify-Settings.ps1" })
(El "BtnDashBackup"   ).Add_Click({ Switch-Panel "PanelBackup"; Load-Backup })
(El "BtnDashPhase1"   ).Add_Click({ Launch-Terminal "Run-Optimize.ps1" })
(El "BtnDashLaunchCs2").Add_Click({ Start-Process "steam://rungameid/730" })

# ══════════════════════════════════════════════════════════════════════════════
# ANALYZE
# ══════════════════════════════════════════════════════════════════════════════
function Start-Analysis {
    (El "BtnRunAnalysis").IsEnabled = $false
    (El "BtnRunAnalysis").Content   = "Scanning…"
    (El "AnalyzeScanTime").Text     = "Scanning…"
    (El "AnalysisGrid").ItemsSource = $null

    Invoke-Async -Work {
        param($ScriptRoot, $UISync)
        . "$ScriptRoot\config.env.ps1"
        . "$ScriptRoot\helpers.ps1"
        . "$ScriptRoot\helpers\system-analysis.ps1"
        try { $UISync.AnalysisResults = Invoke-SystemAnalysis }
        catch { $UISync.AnalysisError = $_.Exception.Message }
        $UISync.AnalysisDone = $true
    } -WorkArgs @($Script:Root, $Script:UISync) -OnDone {
        $res = $Script:UISync.AnalysisResults
        if (-not $res) { $res = @() }
        (El "AnalysisGrid").ItemsSource = $res
        $ok   = @($res | Where-Object Status -eq "OK").Count
        $warn = @($res | Where-Object Status -eq "WARN").Count
        $err  = @($res | Where-Object Status -eq "ERR").Count
        (El "AnalyzeSummary" ).Text = "✓ $ok   ⚠ $warn   ✗ $err"
        (El "AnalyzeScanTime").Text = "Last scan: $(Get-Date -Format 'HH:mm  dd-MMM-yyyy')  ·  $($res.Count) checks"
        (El "BtnRunAnalysis" ).IsEnabled = $true
        (El "BtnRunAnalysis" ).Content   = "▶  Run Full Scan"
        if ($warn + $err -gt 0) {
            (El "DashIssueHint").Text = "⚠  $($warn+$err) item(s) need attention — see Analyze panel"
        }
        $Script:UISync.AnalysisDone = $false
    }.GetNewClosure()
}

(El "BtnRunAnalysis"   ).Add_Click({ Start-Analysis })
(El "BtnAnalyzeGotoOpt").Add_Click({ Switch-Panel "PanelOptimize"; Load-Optimize })
(El "BtnAnalyzeExport" ).Add_Click({
    $res = (El "AnalysisGrid").ItemsSource
    if (-not $res) { return }
    $dlg = [Microsoft.Win32.SaveFileDialog]::new()
    $dlg.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
    $dlg.FileName = "cs2-analyze-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
    if ($dlg.ShowDialog()) {
        try {
            $res | Export-Csv -Path $dlg.FileName -NoTypeInformation -Encoding UTF8
            [System.Windows.MessageBox]::Show("Exported to:`n$($dlg.FileName)", "Export Complete")
        } catch {
            [System.Windows.MessageBox]::Show("Export failed:`n$_`n`nCheck that the file is not open in another program.", "Export Error", "OK", "Error")
        }
    }
})

# ══════════════════════════════════════════════════════════════════════════════
# OPTIMIZE
# ══════════════════════════════════════════════════════════════════════════════
function Load-Optimize {
    $prog = $null
    try { $prog = Load-Progress } catch {}
    $completed = if ($prog) { $prog.completedSteps } else { @() }
    $skipped   = if ($prog) { $prog.skippedSteps }   else { @() }

    $estimates = $CFG_ImprovementEstimates

    $rows = foreach ($s in $SCRIPT:StepCatalog) {
        $stepKey   = if ($s.Phase -eq 3) { $s.Step + 100 } else { $s.Step }
        $isDone    = $completed -contains $stepKey
        $isSkipped = $skipped   -contains $stepKey

        $statusLabel = if ($s.CheckOnly) { "—  Check" } elseif ($isDone) { "✓  Done" } elseif ($isSkipped) { "—  Skipped" } else { "○  Pending" }
        $statusColor = if ($s.CheckOnly) { "#6b7280" } elseif ($isDone) { "#22c55e" } elseif ($isSkipped) { "#374151" } else { "#fbbf24" }

        $tierColor = switch ($s.Tier) { 1 { "#22c55e" } 2 { "#fbbf24" } 3 { "#e8520a" } default { "#6b7280" } }
        $riskColor = switch ($s.Risk) {
            "SAFE"       { "#22c55e" } "MODERATE"   { "#fbbf24" }
            "AGGRESSIVE" { "#e8520a" } "CRITICAL"   { "#ef4444" }
            default      { "#6b7280" }
        }

        $est = ""
        if ($s.EstKey -and $estimates.ContainsKey($s.EstKey)) {
            $e = $estimates[$s.EstKey]
            if ($e.P1LowMin -ne 0 -or $e.P1LowMax -ne 0) {
                $est = "+$($e.P1LowMin)-$($e.P1LowMax)% P1"
            }
        }

        [PSCustomObject]@{
            PhLabel     = "P$($s.Phase)"
            StepLabel   = "$($s.Step)"
            Category    = $s.Category
            Title       = $s.Title
            Tier        = $s.Tier
            TierLabel   = "T$($s.Tier)"
            TierColor   = $tierColor
            Risk        = $s.Risk
            RiskColor   = $riskColor
            StatusLabel = $statusLabel
            StatusColor = $statusColor
            RebootLabel = if ($s.Reboot) { "Yes" } else { "" }
            EstLabel    = $est
            _Step       = $s
        }
    }

    $SCRIPT:OptimizeAllRows = $rows
    (El "OptimizeGrid").ItemsSource = $rows

    # Populate category filter
    $cats = @("All") + ($rows | Select-Object -ExpandProperty Category -Unique | Sort-Object)
    (El "OptFilterCat").ItemsSource   = $cats
    (El "OptFilterCat").SelectedIndex = 0

    $statuses = @("All", "Pending", "Done", "Skipped")
    (El "OptFilterStatus").ItemsSource   = $statuses
    (El "OptFilterStatus").SelectedIndex = 0
}

(El "OptFilterCat"   ).Add_SelectionChanged({ Filter-OptimizeGrid })
(El "OptFilterStatus").Add_SelectionChanged({ Filter-OptimizeGrid })

function Filter-OptimizeGrid {
    $cat    = (El "OptFilterCat").SelectedItem
    $status = (El "OptFilterStatus").SelectedItem
    $all    = $SCRIPT:OptimizeAllRows
    if (-not $all) { return }
    $filtered = $all | Where-Object {
        ($cat    -eq "All" -or $_.Category -eq $cat) -and
        ($status -eq "All" -or $_.StatusLabel -eq $status)
    }
    (El "OptimizeGrid").ItemsSource = @($filtered)
}

(El "BtnOptPhase1"   ).Add_Click({ Launch-Terminal "Run-Optimize.ps1" })
(El "BtnOptPhase3"   ).Add_Click({ Launch-Terminal "PostReboot-Setup.ps1" })
(El "BtnOptFullSetup").Add_Click({ Launch-Terminal "Run-Optimize.ps1" })
(El "BtnOptVerify"   ).Add_Click({ Launch-Terminal "Verify-Settings.ps1" })

# ══════════════════════════════════════════════════════════════════════════════
# BACKUP
# ══════════════════════════════════════════════════════════════════════════════
function Load-Backup {
    try {
        $bd = Get-BackupData
        if (-not $bd -or -not $bd.entries) {
            (El "BackupSummary").Text = "No backups found in backup.json"
            (El "BackupGrid").ItemsSource = $null
            return
        }
        $entries = $bd.entries
        (El "BackupSummary").Text = "$($entries.Count) backup entries  ·  Created $($bd.created)"

        $rows = foreach ($e in $entries) {
            $key = switch ($e.type) {
                "registry"      { "$($e.path)  →  $($e.name)" }
                "service"       { $e.name }
                "bootconfig"    { $e.key }
                "powerplan"     { "Power Plan: $($e.originalName)" }
                "drs"           { "DRS Profile: $($e.profile)  ($($e.settings.Count) settings)" }
                "scheduledtask" { "Task: $($e.taskName)" }
                default         { "$($e.type)" }
            }
            $orig = switch ($e.type) {
                "registry"      { if ($e.existed) { "$($e.originalValue)" } else { "(new key)" } }
                "service"       { "$($e.originalStartType) / $($e.originalStatus)" }
                "bootconfig"    { if ($e.existed) { $e.originalValue } else { "(new)" } }
                "powerplan"     { $e.originalGuid }
                "drs"           { "$($e.settings.Count) settings" }
                "scheduledtask" { if ($e.existed) { "existed" } else { "(new)" } }
                default         { "" }
            }
            [PSCustomObject]@{
                Step      = $e.step
                Type      = $e.type
                Key       = $key
                Original  = $orig
                Timestamp = $e.timestamp
                _Entry    = $e
            }
        }
        (El "BackupGrid").ItemsSource = $rows
    } catch {
        (El "BackupSummary").Text = "Error loading backup.json: $($_.Exception.Message)"
    }
}

(El "BtnBackupRefresh").Add_Click({ Load-Backup })

(El "BtnBackupExport").Add_Click({
    $src = "$CFG_WorkDir\backup.json"
    if (-not (Test-Path $src)) { [System.Windows.MessageBox]::Show("backup.json not found.","Export"); return }
    $dlg = [Microsoft.Win32.SaveFileDialog]::new()
    $dlg.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
    $dlg.FileName = "cs2-backup-$(Get-Date -Format 'yyyyMMdd-HHmm').json"
    if ($dlg.ShowDialog()) { Copy-Item $src $dlg.FileName -Force; [System.Windows.MessageBox]::Show("Exported to:`n$($dlg.FileName)","Export Complete") }
})

(El "BtnRestoreAll").Add_Click({
    $r = [System.Windows.MessageBox]::Show("Restore ALL backed-up settings?`nThis will undo every change the suite made.","Restore All","YesNo","Warning")
    if ($r -eq "Yes") {
        try {
            Restore-AllChanges
            [System.Windows.MessageBox]::Show("All settings restored successfully.","Restore Complete")
            Load-Backup
        } catch {
            [System.Windows.MessageBox]::Show("Restore error: $($_.Exception.Message)","Restore Failed","OK","Error")
        }
    }
})

(El "BtnRestoreStep").Add_Click({
    $sel = (El "BackupGrid").SelectedItem
    if (-not $sel) { [System.Windows.MessageBox]::Show("Select a row first.","Restore Step"); return }
    $stepTitle = $sel.Step
    $r = [System.Windows.MessageBox]::Show("Restore all changes from:`n`"$stepTitle`"?","Restore Step","YesNo","Question")
    if ($r -eq "Yes") {
        try {
            Restore-StepChanges $stepTitle
            [System.Windows.MessageBox]::Show("Restore complete for:`n$stepTitle","Done")
            Load-Backup
        } catch { [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)","Restore Failed") }
    }
})

(El "BtnClearBackup").Add_Click({
    $r = [System.Windows.MessageBox]::Show("Delete all backup data?`nThis cannot be undone.","Clear Backups","YesNo","Warning")
    if ($r -eq "Yes") {
        if (Test-Path "$CFG_WorkDir\backup.json") { Remove-Item "$CFG_WorkDir\backup.json" -Force }
        Load-Backup
    }
})

# ══════════════════════════════════════════════════════════════════════════════
# BENCHMARK
# ══════════════════════════════════════════════════════════════════════════════
function Load-Benchmark {
    try {
        $hist = Get-BenchmarkHistory
        if (-not $hist -or $hist.Count -eq 0) {
            (El "BenchGrid").ItemsSource = $null
            return
        }

        $rows = for ($i = 0; $i -lt $hist.Count; $i++) {
            $h = $hist[$i]
            $dAvg = if ($i -eq 0) { "—" } else {
                $prev = $hist[$i - 1]
                $d = [math]::Round(($h.avgFps - $prev.avgFps) / $prev.avgFps * 100, 1)
                if ($d -gt 0) { "+$d%" } else { "$d%" }
            }
            $dP1 = if ($i -eq 0) { "—" } else {
                $prev = $hist[$i - 1]
                $d = if ($prev.p1Fps -gt 0) { [math]::Round(($h.p1Fps - $prev.p1Fps) / $prev.p1Fps * 100, 1) } else { 0 }
                if ($d -gt 0) { "+$d%" } else { "$d%" }
            }
            $dc = if ($i -eq 0 -or $dAvg -eq "—") { "#6b7280" } elseif ($dAvg.StartsWith("+")) { "#22c55e" } else { "#ef4444" }
            $dateStr = try { [datetime]::ParseExact($h.timestamp,"yyyy-MM-dd HH:mm:ss",$null).ToString("dd-MMM HH:mm") } catch { $h.timestamp }
            [PSCustomObject]@{
                Index      = $h.index
                Date       = $dateStr
                Label      = $h.label
                AvgFps     = [math]::Round($h.avgFps, 0)
                P1Fps      = [math]::Round($h.p1Fps,  0)
                DeltaAvg   = $dAvg
                DeltaP1    = $dP1
                DeltaColor = $dc
            }
        }
        (El "BenchGrid").ItemsSource = $rows
        Draw-BenchChart $hist
    } catch { }
}

function Draw-BenchChart {
    param($hist)
    $canvas = El "BenchChart"
    $canvas.Children.Clear()
    if (-not $hist -or $hist.Count -lt 2) { return }

    # Wait for layout
    $canvas.UpdateLayout()
    $w = if ($canvas.ActualWidth  -gt 0) { $canvas.ActualWidth  } else { 600 }
    $h = if ($canvas.ActualHeight -gt 0) { $canvas.ActualHeight } else { 130 }

    $allFps = ($hist | ForEach-Object { $_.avgFps, $_.p1Fps }) | Measure-Object -Maximum -Minimum
    $maxF = $allFps.Maximum * 1.08
    $minF = $allFps.Minimum * 0.92
    $range = $maxF - $minF
    if ($range -le 0) { $range = 1 }

    $xStep = $w / ($hist.Count - 1)
    $toY   = { param($v) $h - (($v - $minF) / $range * $h) }

    # Grid lines
    foreach ($pct in @(0.25, 0.5, 0.75)) {
        $y = $h * $pct
        $gl = [System.Windows.Shapes.Line]::new()
        $gl.X1 = 0; $gl.X2 = $w; $gl.Y1 = $y; $gl.Y2 = $y
        $gl.Stroke = New-Brush "#252525"; $gl.StrokeThickness = 1
        $canvas.Children.Add($gl) | Out-Null
    }

    # Build point collections
    $avgPts = [System.Windows.Media.PointCollection]::new()
    $p1Pts  = [System.Windows.Media.PointCollection]::new()
    for ($i = 0; $i -lt $hist.Count; $i++) {
        $x = $i * $xStep
        $avgPts.Add([System.Windows.Point]::new($x, (& $toY $hist[$i].avgFps))) | Out-Null
        $p1Pts.Add( [System.Windows.Point]::new($x, (& $toY $hist[$i].p1Fps ))) | Out-Null
    }

    # Avg line
    $avgLine = [System.Windows.Shapes.Polyline]::new()
    $avgLine.Points = $avgPts
    $avgLine.Stroke = New-Brush "#e8520a"; $avgLine.StrokeThickness = 2
    $canvas.Children.Add($avgLine) | Out-Null

    # P1 line
    $p1Line = [System.Windows.Shapes.Polyline]::new()
    $p1Line.Points = $p1Pts
    $p1Line.Stroke = New-Brush "#22c55e"; $p1Line.StrokeThickness = 2; $p1Line.StrokeDashArray = "4,3"
    $canvas.Children.Add($p1Line) | Out-Null

    # Dots + x-axis labels
    for ($i = 0; $i -lt $hist.Count; $i++) {
        $x = $i * $xStep
        foreach ($pts in @($avgPts, $p1Pts)) {
            $dot = [System.Windows.Shapes.Ellipse]::new()
            $dot.Width = 6; $dot.Height = 6
            $dot.Fill = if ($pts -eq $avgPts) { New-Brush "#e8520a" } else { New-Brush "#22c55e" }
            [System.Windows.Controls.Canvas]::SetLeft($dot, $pts[$i].X - 3)
            [System.Windows.Controls.Canvas]::SetTop( $dot, $pts[$i].Y - 3)
            $canvas.Children.Add($dot) | Out-Null
        }
        # x-label
        $lbl = [System.Windows.Controls.TextBlock]::new()
        $lbl.Text = try { [datetime]::ParseExact($hist[$i].timestamp,"yyyy-MM-dd HH:mm:ss",$null).ToString("d-MMM") } catch { "$($i+1)" }
        $lbl.FontSize = 9; $lbl.Foreground = New-Brush "#4b5563"
        [System.Windows.Controls.Canvas]::SetLeft($lbl, $x - 16)
        [System.Windows.Controls.Canvas]::SetTop( $lbl, $h + 4)
        $canvas.Children.Add($lbl) | Out-Null
    }

    # Y-axis label
    $yLbl = [System.Windows.Controls.TextBlock]::new()
    $yLbl.Text = "FPS"; $yLbl.FontSize = 9; $yLbl.Foreground = New-Brush "#4b5563"
    [System.Windows.Controls.Canvas]::SetLeft($yLbl, -28)
    [System.Windows.Controls.Canvas]::SetTop( $yLbl, $h / 2 - 8)
    $canvas.Children.Add($yLbl) | Out-Null

    # Legend
    $leg = [System.Windows.Controls.TextBlock]::new()
    $leg.Text = "— Avg FPS   - - 1% Low"; $leg.FontSize = 9; $leg.Foreground = New-Brush "#6b7280"
    [System.Windows.Controls.Canvas]::SetLeft($leg, $w - 120)
    [System.Windows.Controls.Canvas]::SetTop( $leg, -16)
    $canvas.Children.Add($leg) | Out-Null
}

# FPS Cap
(El "BtnBenchParse").Add_Click({
    $raw = (El "BenchVprof").Text.Trim()
    if ($raw -match "Avg\s*=\s*([\d.]+)") {
        $avg = [double]$Matches[1]
        $cap = [math]::Max($CFG_FpsCap_Min, [int]($avg - [math]::Round($avg * $CFG_FpsCap_Percent)))
        (El "BenchCapLabel").Text = "→  Cap:"
        (El "BenchCapValue").Text = "$cap"
        $Script:UISync.LastCap = $cap
    } else {
        (El "BenchCapLabel").Text = "⚠  No [VProf] FPS line detected"
        (El "BenchCapValue").Text = ""
    }
})

(El "BtnBenchCopy").Add_Click({
    $cap = $Script:UISync.LastCap
    if ($cap) { [System.Windows.Clipboard]::SetText("$cap") }
})

(El "BtnBenchAdd").Add_Click({
    $raw = (El "BenchVprof").Text.Trim()
    if ($raw -match "Avg\s*=\s*([\d.]+).*P1\s*=\s*([\d.]+)") {
        $avg = [double]$Matches[1]; $p1 = [double]$Matches[2]
        $lbl = [Microsoft.VisualBasic.Interaction]::InputBox("Label for this benchmark result:", "Add Result", "")
        Add-BenchmarkResult -AvgFps $avg -P1Fps $p1 -Label $lbl -Runs 1
        Load-Benchmark
    } else {
        [System.Windows.MessageBox]::Show("Paste a [VProf] FPS: Avg=… P1=… line first.","Add Result")
    }
})

# ══════════════════════════════════════════════════════════════════════════════
# VIDEO
# ══════════════════════════════════════════════════════════════════════════════
$Script:VideoTxtPath = $null

function Load-Video {
    # Populate tier picker
    if ((El "VideoTierPicker").Items.Count -eq 0) {
        foreach ($t in @("Auto","HIGH","MID","LOW")) { (El "VideoTierPicker").Items.Add($t) | Out-Null }
        (El "VideoTierPicker").SelectedIndex = 0
    }

    $steamPath = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
    $vtxt = if ($steamPath) {
        Get-ChildItem "$steamPath\userdata\*\730\local\cfg\video.txt" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }

    if ($vtxt) {
        $Script:VideoTxtPath = $vtxt.FullName
        (El "VideoTxtPath").Text = $vtxt.FullName
    } else {
        (El "VideoTxtPath").Text = "video.txt not found — launch CS2 once to generate it"
        (El "BtnVideoWrite").IsEnabled = $false
        (El "BtnVideoWriteFooter").IsEnabled = $false
        return
    }

    Refresh-VideoGrid
}

# Single source of truth for video tier presets (V=value, N=note for display)
$Script:VideoPresets = @{
    "HIGH" = @{
        "setting.msaa_samples"              = @{ V="4";  N="4x MSAA — better 1% lows than None (ThourCS2)" }
        "setting.mat_vsync"                 = @{ V="0";  N="Always OFF — adds render queue latency" }
        "setting.fullscreen"                = @{ V="1";  N="Exclusive fullscreen — bypasses DWM compositor" }
        "setting.r_low_latency"             = @{ V="1";  N="NVIDIA Reflex On — saves 3-4ms input latency" }
        "setting.r_csgo_fsr_upsample"       = @{ V="0";  N="FSR OFF — artifacts harm enemy recognition" }
        "setting.shaderquality"             = @{ V="1";  N="High — GPU has headroom at this tier" }
        "setting.r_texturefilteringquality" = @{ V="5";  N="AF16x — near-zero cost on modern GPUs" }
        "setting.r_csgo_cmaa_enable"        = @{ V="0";  N="Off — MSAA handles AA" }
        "setting.r_aoproxy_enable"          = @{ V="0";  N="AO off — purely cosmetic, up to 6% FPS cost" }
        "setting.sc_hdr_enabled_override"   = @{ V="3";  N="Performance — Quality washes out sun/window areas" }
        "setting.r_particle_max_detail_level"=@{ V="0";  N="Low particles — no competitive disadvantage" }
        "setting.csm_enabled"               = @{ V="1";  N="Shadows ON — foot shadows reveal enemy positions" }
    }
    "MID" = @{
        "setting.msaa_samples"              = @{ V="4";  N="4x — or 2x if below 200 avg FPS" }
        "setting.mat_vsync"                 = @{ V="0";  N="Always OFF" }
        "setting.fullscreen"                = @{ V="1";  N="Exclusive fullscreen" }
        "setting.r_low_latency"             = @{ V="1";  N="NVIDIA Reflex On" }
        "setting.r_csgo_fsr_upsample"       = @{ V="0";  N="FSR OFF" }
        "setting.shaderquality"             = @{ V="0";  N="Low — saves GPU headroom on mid-tier" }
        "setting.r_texturefilteringquality" = @{ V="5";  N="AF16x" }
        "setting.r_csgo_cmaa_enable"        = @{ V="0";  N="Off — MSAA handles AA" }
        "setting.r_aoproxy_enable"          = @{ V="0";  N="AO off" }
        "setting.sc_hdr_enabled_override"   = @{ V="3";  N="Performance" }
        "setting.r_particle_max_detail_level"=@{ V="0";  N="Low" }
        "setting.csm_enabled"               = @{ V="1";  N="Shadows ON" }
    }
    "LOW" = @{
        "setting.msaa_samples"              = @{ V="0";  N="None + CMAA2 — free AA alternative" }
        "setting.mat_vsync"                 = @{ V="0";  N="Always OFF" }
        "setting.fullscreen"                = @{ V="1";  N="Exclusive fullscreen — critical for FPS" }
        "setting.r_low_latency"             = @{ V="1";  N="NVIDIA Reflex On" }
        "setting.r_csgo_fsr_upsample"       = @{ V="0";  N="FSR OFF" }
        "setting.shaderquality"             = @{ V="0";  N="Low" }
        "setting.r_texturefilteringquality" = @{ V="0";  N="Bilinear — legacy for max FPS" }
        "setting.r_csgo_cmaa_enable"        = @{ V="1";  N="CMAA2 ON — near-zero cost AA when MSAA=0" }
        "setting.r_aoproxy_enable"          = @{ V="0";  N="AO off" }
        "setting.sc_hdr_enabled_override"   = @{ V="3";  N="Performance" }
        "setting.r_particle_max_detail_level"=@{ V="0";  N="Low" }
        "setting.csm_enabled"               = @{ V="1";  N="Shadows ON — keep even on low-end" }
    }
}

function Get-ResolvedVideoTier {
    param([string]$TierSel)
    if ($TierSel -eq "Auto") {
        try { $null = Get-NvidiaDriverVersion; return "HIGH" } catch { return "MID" }
    }
    return $TierSel
}

function Refresh-VideoGrid {
    $tier = Get-ResolvedVideoTier (El "VideoTierPicker").SelectedItem
    $recommended = $Script:VideoPresets[$tier]

    $current = @{}
    if ($Script:VideoTxtPath -and (Test-Path $Script:VideoTxtPath)) {
        Get-Content $Script:VideoTxtPath | ForEach-Object {
            if ($_ -match '^\s*"([^"]+)"\s+"([^"]*)"') { $current[$Matches[1]] = $Matches[2] }
        }
    }

    $rows = foreach ($kv in $recommended.GetEnumerator() | Sort-Object Key) {
        $cur  = $current[$kv.Key]
        $rec  = $kv.Value.V
        $note = $kv.Value.N
        $st   = if ($null -eq $cur) { "—  Missing" } elseif ($cur -eq $rec) { "✓  OK" } else { "⚠  Differs" }
        $sc   = if ($st -match "OK") { "#22c55e" } elseif ($st -match "Missing") { "#6b7280" } else { "#fbbf24" }
        [PSCustomObject]@{
            Setting     = $kv.Key -replace "^setting\.",""
            YourValue   = if ($null -eq $cur) { "(not set)" } else { $cur }
            Recommended = $rec
            StatusLabel = $st
            StatusColor = $sc
            Notes       = $note
        }
    }

    (El "VideoGrid").ItemsSource = $rows
    $diffs = @($rows | Where-Object { $_.StatusLabel -notmatch "OK" }).Count
    (El "VideoSummary").Text = "$diffs setting(s) differ from $tier-tier recommendation"
}

(El "VideoTierPicker").Add_SelectionChanged({ if ((El "VideoTierPicker").SelectedItem) { Refresh-VideoGrid } })

$writeVideo = {
    if (-not $Script:VideoTxtPath) { [System.Windows.MessageBox]::Show("video.txt not found.","Write"); return }

    $tier = Get-ResolvedVideoTier (El "VideoTierPicker").SelectedItem

    # Derive values-only hashtable from shared presets
    $managed = @{}
    foreach ($kv in $Script:VideoPresets[$tier].GetEnumerator()) { $managed[$kv.Key] = $kv.Value.V }

    # Read existing file — preserve unmanaged keys (resolution, Hz, etc.)
    $existing = [System.Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    if (Test-Path $Script:VideoTxtPath) {
        Get-Content $Script:VideoTxtPath | ForEach-Object {
            if ($_ -match '^\s*"([^"]+)"\s+"([^"]*)"') { $existing[$Matches[1]] = $Matches[2] }
        }
    }

    # Merge: apply managed overrides onto existing keys
    foreach ($kv in $managed.GetEnumerator()) { $existing[$kv.Key] = $kv.Value }

    $summary = ($managed.Keys | ForEach-Object { "$($_ -replace '^setting\.',''): $($managed[$_])" }) -join "`n"
    $r = [System.Windows.MessageBox]::Show(
        "Write optimized video.txt ($tier tier)?`n`nOriginal → video.txt.bak`n`nSettings:`n$summary",
        "Confirm Write","YesNo","Question")
    if ($r -ne "Yes") { return }

    try {
        $bakPath = "$Script:VideoTxtPath.bak"
        if (Test-Path $Script:VideoTxtPath) { Copy-Item $Script:VideoTxtPath $bakPath -Force }

        $dir = Split-Path $Script:VideoTxtPath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        $lines = @(
            '"VideoConfig"'
            '{'
            "    // CS2-Optimize Suite — $(Get-Date -Format 'yyyy-MM-dd HH:mm')  Tier: $tier"
            "    // Original backed up as video.txt.bak"
            ""
        )
        foreach ($kv in $existing.GetEnumerator() | Sort-Object Key) {
            $lines += "    `"$($kv.Key)`"`t`"$($kv.Value)`""
        }
        $lines += "}"
        $lines | Set-Content $Script:VideoTxtPath -Encoding UTF8

        [System.Windows.MessageBox]::Show("video.txt written ($tier tier).`nOriginal saved as video.txt.bak`n`n$Script:VideoTxtPath","Done")
        Load-Video
    } catch { [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)","Write Failed") }
}
(El "BtnVideoWrite"      ).Add_Click($writeVideo)
(El "BtnVideoWriteFooter").Add_Click($writeVideo)

# ══════════════════════════════════════════════════════════════════════════════
# SETTINGS
# ══════════════════════════════════════════════════════════════════════════════
function Load-Settings {
    $state = $null
    try { if (Test-Path $CFG_StateFile) { $state = Get-Content $CFG_StateFile | ConvertFrom-Json } } catch {}

    $prof = if ($state) { $state.profile } else { "RECOMMENDED" }
    switch ($prof) {
        "SAFE"        { (El "RadioSafe"       ).IsChecked = $true }
        "COMPETITIVE" { (El "RadioCompetitive").IsChecked = $true }
        "CUSTOM"      { (El "RadioCustom"     ).IsChecked = $true }
        default       { (El "RadioRecommended").IsChecked = $true }
    }

    $dry = if ($state) { $state.dryRun } else { $false }
    (El "ChkDryRun").IsChecked = $dry
    (El "RegNA").IsChecked = $true
}

foreach ($rb in @("RadioSafe","RadioRecommended","RadioCompetitive","RadioCustom")) {
    (El $rb).Add_Checked({
        $prof = if ((El "RadioSafe").IsChecked)        { "SAFE"
                } elseif ((El "RadioCompetitive").IsChecked) { "COMPETITIVE"
                } elseif ((El "RadioCustom").IsChecked)      { "CUSTOM"
                } else                                        { "RECOMMENDED" }
        (El "SbProfile").Text = "Profile: $prof"
    }.GetNewClosure())
}

(El "ChkDryRun").Add_Checked({   (El "SbDryRun").Text = "DRY-RUN ON" })
(El "ChkDryRun").Add_Unchecked({ (El "SbDryRun").Text = "" })

(El "BtnSettingsPhase1").Add_Click({ Launch-Terminal "Run-Optimize.ps1" })

# ══════════════════════════════════════════════════════════════════════════════
# SHARED HELPERS
# ══════════════════════════════════════════════════════════════════════════════
function Launch-Terminal {
    param([string]$Script, [string]$ScriptArgs = "")
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$Script:Root\$Script`" $ScriptArgs" -Verb RunAs
}

# ══════════════════════════════════════════════════════════════════════════════
# STARTUP
# ══════════════════════════════════════════════════════════════════════════════
$Window.Add_Loaded({
    Update-SidebarStatus
    Load-Dashboard
})

$Window.Add_Closed({
    try { $Script:Pool.Close(); $Script:Pool.Dispose() } catch {}
})

$Window.ShowDialog() | Out-Null
