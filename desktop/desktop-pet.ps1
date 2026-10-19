param([switch]$Verify)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$base = $PSScriptRoot
$cfg = Get-Content -LiteralPath (Join-Path $base 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$mutex = New-Object Threading.Mutex($false, 'Local\NailongThreeActionsDesktopPet')
if (-not $mutex.WaitOne(0)) { exit }
try {
    $script:window = New-Object Windows.Window
    $window.Title = '奶龙 · 三动作'
    $window.WindowStyle = 'None'
    $window.ResizeMode = 'NoResize'
    $window.AllowsTransparency = $true
    $window.Background = [Windows.Media.Brushes]::Transparent
    $window.Topmost = $true
    $window.ShowInTaskbar = $false
    $window.Width = [double]$cfg.size
    $window.Height = [double]$cfg.size * 416 / 384
    $script:workArea = [Windows.SystemParameters]::WorkArea
    $script:anchorX = $workArea.Right - $window.Width - 80
    $script:anchorY = $workArea.Bottom - $window.Height - 6
    $window.Left = $anchorX
    $window.Top = $anchorY
    $image = New-Object Windows.Controls.Image
    $image.Stretch = 'Uniform'
    $image.RenderTransformOrigin = New-Object Windows.Point(0.5, 0.5)
    $script:scale = New-Object Windows.Media.ScaleTransform(1, 1)
    $script:offset = New-Object Windows.Media.TranslateTransform(0, 0)
    $group = New-Object Windows.Media.TransformGroup
    $group.Children.Add($scale)
    $group.Children.Add($offset)
    $image.RenderTransform = $group
    $window.Content = $image
    $script:cache = @{}
    function Load-Frame([string]$relative) {
        if (-not $script:cache.ContainsKey($relative)) {
            $bitmap = New-Object Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit()
            $bitmap.CacheOption = 'OnLoad'
            $bitmap.DecodePixelWidth = [int]$cfg.size
            $bitmap.UriSource = New-Object System.Uri((Join-Path $base $relative))
            $bitmap.EndInit()
            $bitmap.Freeze()
            $script:cache[$relative] = $bitmap
        }
        return $script:cache[$relative]
    }
    $script:idleFrame = Load-Frame 'assets\idle-frame.png'
    $script:stanceFrame = Load-Frame 'assets\stance-frame.png'
    $script:player = New-Object Windows.Media.MediaPlayer
    $player.Open((New-Object System.Uri((Join-Path $base 'assets\laugh.wav'))))
    $script:sound = [bool]$cfg.sound_enabled
    $script:mode = 'idle'
    $script:clock = [Diagnostics.Stopwatch]::StartNew()
    $script:nextAction = 'laugh'
    $script:paused = $false
    $script:lastFrame = -1
    function Set-Mode([string]$newMode) {
        $script:player.Stop()
        $script:anchorX = $window.Left
        $script:anchorY = $window.Top
        $script:mode = $newMode
        $script:lastFrame = -1
        $script:clock.Restart()
        if ($newMode -eq 'laugh' -and $script:sound) {
            $script:player.Position = [TimeSpan]::Zero
            $script:player.Play()
        }
    }
    $menu = New-Object Windows.Controls.ContextMenu
    foreach ($entry in @(@('白大褂待机','idle'), @('完整大笑','laugh'), @('马步节奏移动','stance'))) {
        $item = New-Object Windows.Controls.MenuItem
        $item.Header = $entry[0]
        $item.Tag = $entry[1]
        $item.Add_Click({ param($sender,$eventArgs) $script:paused=$false; Set-Mode ([string]$sender.Tag) })
        [void]$menu.Items.Add($item)
    }
    $soundItem = New-Object Windows.Controls.MenuItem
    $soundItem.Header = '播放笑声'
    $soundItem.IsCheckable = $true
    $soundItem.IsChecked = $script:sound
    $soundItem.Add_Click({param($sender,$eventArgs) $script:sound=[bool]$sender.IsChecked; if(-not $script:sound){$script:player.Stop()} })
    [void]$menu.Items.Add($soundItem)
    $pauseItem = New-Object Windows.Controls.MenuItem
    $pauseItem.Header = '暂停动作'
    $pauseItem.IsCheckable = $true
    $pauseItem.Add_Click({param($sender,$eventArgs) $script:paused=[bool]$sender.IsChecked; if($script:paused){$script:clock.Stop();$script:player.Pause()}else{$script:clock.Start();if($script:mode -eq 'laugh' -and $script:sound){$script:player.Play()}} })
    [void]$menu.Items.Add($pauseItem)
    $closeItem = New-Object Windows.Controls.MenuItem
    $closeItem.Header = '退出桌宠'
    $closeItem.Add_Click({$script:window.Close()})
    [void]$menu.Items.Add($closeItem)
    $image.ContextMenu = $menu
    $image.Add_MouseLeftButtonDown({
        param($sender,$eventArgs)
        if($eventArgs.ClickCount -eq 2){$script:paused=$false;Set-Mode 'laugh';return}
        $script:clock.Stop();$script:player.Pause()
        $script:window.DragMove()
        $script:anchorX=$script:window.Left;$script:anchorY=$script:window.Top
        if(-not $script:paused){$script:clock.Start();if($script:mode -eq 'laugh' -and $script:sound){$script:player.Play()}}
    })
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(16)
    $onTick = {
        if($script:paused){return}
        $t=$script:clock.Elapsed.TotalSeconds
        if($Verify -and $null -ne $script:verifyTime){$t=$script:verifyTime}
        $script:scale.ScaleX=1
        $script:offset.Y=0
        $image.Opacity=1
        switch($script:mode){
            'idle' {
                $image.Source=$script:idleFrame
                if(([math]::Floor($t/[double]$cfg.idle_flip_seconds)%2) -eq 1){$script:scale.ScaleX=-1}
                if($t -ge [double]$cfg.idle_seconds){$next=$script:nextAction;if($next -eq 'laugh'){$script:nextAction='stance'}else{$script:nextAction='laugh'};Set-Mode $next}
            }
            'laugh' {
                $index=[math]::Min([int]$cfg.laugh_frames-1,[int][math]::Floor($t*[double]$cfg.laugh_fps))
                if($index -ne $script:lastFrame){$image.Source=Load-Frame ('assets\laugh\{0:D4}.png' -f $index);$script:lastFrame=$index}
                if($t -ge [double]$cfg.laugh_seconds){Set-Mode 'idle'}
            }
            'stance' {
                $image.Source=$script:stanceFrame
                $hold=[double]$cfg.pose_hold_seconds
                $duration=[double]$cfg.move_seconds_each_direction
                $speed=[double]$cfg.move_pixels_per_second
                $available=[math]::Max(0,$script:workArea.Width-$window.Width-16)
                $distance=[math]::Min($speed*$duration,$available)
                $start=[math]::Max($script:workArea.Left+8,[math]::Min($script:anchorX,$script:workArea.Right-$window.Width-8))
                $direction=1
                if($script:workArea.Right-$window.Width-8-$start -lt $distance){$direction=-1;$distance=[math]::Min($distance,$start-$script:workArea.Left-8)}
                $script:scale.ScaleX=$direction
                if($t -lt $hold){$window.Left=$start}
                elseif($t -lt $hold+$duration){
                    $p=($t-$hold)/$duration
                    $e=$p-[math]::Sin($p*[math]::PI*20)/([math]::PI*20)
                    $window.Left=$start+$direction*$distance*$e
                    $script:offset.Y=-5*[math]::Abs([math]::Sin(($t-$hold)*[math]::PI/[double]$cfg.beat_seconds))
                }
                elseif($t -lt $hold+$duration+0.3){$script:scale.ScaleX=-$direction;$window.Left=$start+$direction*$distance}
                elseif($t -lt $hold+2*$duration+0.3){
                    $script:scale.ScaleX=-$direction
                    $p=($t-$hold-$duration-0.3)/$duration
                    $e=$p-[math]::Sin($p*[math]::PI*20)/([math]::PI*20)
                    $window.Left=$start+$direction*$distance*(1-$e)
                    $script:offset.Y=-5*[math]::Abs([math]::Sin(($t-$hold-$duration-0.3)*[math]::PI/[double]$cfg.beat_seconds))
                }
                else{Set-Mode 'idle'}
            }
        }
    }
    $timer.Add_Tick($onTick)
    $window.Add_Closed({$timer.Stop();$script:player.Close()})
    $image.Source=$idleFrame
    if($Verify){
        $qaDir=Join-Path $base 'qa-runtime'
        [void][IO.Directory]::CreateDirectory($qaDir)
        $results=@()
        foreach($test in @(@('idle',0),@('idle',4.1),@('laugh',0),@('laugh',3),@('laugh',8),@('laugh',14),@('laugh',17.9),@('stance',0),@('stance',1.3),@('stance',3.6),@('stance',6.1),@('stance',7),@('stance',10.9))){
            $script:mode=$test[0];$script:verifyTime=[double]$test[1]
            & $onTick
            $image.Measure((New-Object Windows.Size($window.Width,$window.Height)))
            $image.Arrange((New-Object Windows.Rect(0,0,$window.Width,$window.Height)))
            $image.UpdateLayout()
            $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$window.Width,[int]$window.Height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
            $bitmap.Render($image)
            $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
            $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
            $file=Join-Path $qaDir ('{0}-{1}.png' -f $test[0],$test[1])
            $stream=[IO.File]::Create($file);$encoder.Save($stream);$stream.Close()
            $results+=@{mode=$test[0];time=$test[1];x=$window.Left;flip=$script:scale.ScaleX;frame=$script:lastFrame}
        }
        $results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $qaDir 'playback-check.json') -Encoding UTF8
        $player.Close()
        'Runtime verification OK'
    }else{
        $timer.Start()
        [void]$window.ShowDialog()
    }
} catch {
    $_ | Out-String | Set-Content -LiteralPath (Join-Path $base '运行错误.txt') -Encoding UTF8
    throw
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
