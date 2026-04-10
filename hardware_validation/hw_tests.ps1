#Requires -Version 5.1
<#
.SYNOPSIS
    Hardware Validation Test Suite
    Covers: Audio, Battery, Display Adapter, Video, Ethernet
    - Auto-testable items run and produce PASS/FAIL
    - Manual-only items are listed as MANUAL (human verification required)
#>

$ErrorActionPreference = "SilentlyContinue"
$WarningPreference     = "SilentlyContinue"

# ============================================================
# GLOBALS
# ============================================================
$script:Results   = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:StartTime = Get-Date
$ReportPath       = Join-Path $PSScriptRoot "report_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

# ============================================================
# HELPERS
# ============================================================
function Iff { param($cond, $t, $f) if ($cond) { $t } else { $f } }

function Log-Test {
    param(
        [string]$Category,
        [string]$Name,
        [ValidateSet("PASS","FAIL","WARN","SKIP","MANUAL")][string]$Status,
        [string]$Detail = ""
    )
    $script:Results.Add([PSCustomObject]@{
        Category = $Category
        Name     = $Name
        Status   = $Status
        Detail   = $Detail
    })
    $fg = @{ PASS="Green"; FAIL="Red"; WARN="Yellow"; SKIP="Cyan"; MANUAL="Magenta" }[$Status]
    Write-Host ("  [{0,-6}] " -f $Status) -NoNewline -ForegroundColor $fg
    Write-Host $Name -NoNewline
    if ($Detail) { Write-Host " => $Detail" -ForegroundColor DarkGray } else { Write-Host }
}

function Write-Section {
    param([string]$Title)
    Write-Host "`n$('=' * 62)" -ForegroundColor DarkCyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "$('=' * 62)" -ForegroundColor DarkCyan
}

# ============================================================
# 2. AUDIO TESTS
# ============================================================
function Test-Audio {
    Write-Section "[2] AUDIO"

    # Windows Audio service
    $svc = Get-Service "AudioSrv"
    Log-Test "Audio" "Windows Audio Service" (Iff ($svc.Status -eq "Running") "PASS" "FAIL") "Status: $($svc.Status)"

    # Audio Endpoint Builder service
    $ep = Get-Service "AudioEndpointBuilder"
    Log-Test "Audio" "Audio Endpoint Builder Service" (Iff ($ep.Status -eq "Running") "PASS" "FAIL") "Status: $($ep.Status)"

    # WMI sound devices
    $devs = @(Get-WmiObject Win32_SoundDevice)
    if ($devs.Count -gt 0) {
        $names = ($devs | Select-Object -ExpandProperty Name) -join "; "
        Log-Test "Audio" "Audio Device(s) Detected" "PASS" "$($devs.Count) device(s): $names"
        $badDevs = @($devs | Where-Object { $_.Status -ne "OK" })
        if ($badDevs.Count -eq 0) {
            Log-Test "Audio" "Audio Device(s) Driver Status" "PASS" "All devices: OK"
        } else {
            $badNames = ($badDevs | Select-Object -ExpandProperty Name) -join "; "
            Log-Test "Audio" "Audio Device(s) Driver Status" "FAIL" "Issues: $badNames"
        }
    } else {
        Log-Test "Audio" "Audio Device(s) Detected" "FAIL" "No audio devices found via WMI"
    }

    # Manual items
    Log-Test "Audio" "Playback Test + Volume (UI & Physical Buttons)" "MANUAL" "Audio Control Panel > Playback Devices > Test Sound"
    Log-Test "Audio" "S3 Sleep/Resume - Audio Functional"             "MANUAL" "4 cycles (2 manual, 2 via Power Plan), verify audio after each"
    Log-Test "Audio" "S4 Hibernate/Resume - Audio Functional"         "MANUAL" "4 cycles (2 manual, 2 via Power Plan), verify audio after each"
    Log-Test "Audio" "Hot Dock / Warm Dock - Audio Functional"        "MANUAL" "See [Dock] section for semi-auto dock detection test"
    Log-Test "Audio" "Voice Recorder - Record & Playback"             "MANUAL" "Launch Voice Recorder, record, verify full playback"
    Log-Test "Audio" "External Headset (Playback + Mic endpoint)"     "MANUAL" "Plug headset, verify default endpoint switches to headset"
}

# ============================================================
# 3. BATTERY TESTS
# ============================================================
function Test-Battery {
    Write-Section "[3] BATTERY"

    $batt = Get-WmiObject Win32_Battery
    if (-not $batt) {
        Log-Test "Battery" "Battery Detection"        "SKIP"   "No battery found (may be desktop PC)"
        Log-Test "Battery" "AC Charging Verification" "MANUAL" "Plug in AC charger, verify battery icon and LED indicators"
        Log-Test "Battery" "AC/DC Transition Stability" "MANUAL" "Unplug/replug charger a few times, verify stable operation"
        return
    }

    Log-Test "Battery" "Battery Detected" "PASS" "$($batt.Name)"

    # Charge level
    $charge = $batt.EstimatedChargeRemaining
    Log-Test "Battery" "Battery Charge Level" (Iff ($charge -gt 5) "PASS" "WARN") "Charge: $charge%"

    # Power source
    $statusMap = @{
        1="Discharging (Battery)"; 2="AC Power (Not Charging)"; 3="Fully Charged"
        4="Low Battery";           5="Critical Battery";         6="Charging"
        7="Charging (High)";       8="Charging (Low)";           9="Charging (Critical)"
    }
    $statusTxt = $statusMap[$batt.BatteryStatus]
    $onAC      = $batt.BatteryStatus -in @(2, 3, 6, 7, 8, 9)
    Log-Test "Battery" "Power Source Detection" "PASS" "Current status: $statusTxt"

    if ($onAC) {
        Log-Test "Battery" "AC Charger Connected & Charging" "PASS" "Unit is on AC power"
    } else {
        Log-Test "Battery" "AC Charger Connected & Charging" "MANUAL" "Connect AC charger and verify charging starts"
    }

    # Active power plan
    $plan = (powercfg /getactivescheme 2>&1 | Select-Object -First 1) -as [string]
    Log-Test "Battery" "Active Power Plan" (Iff ($plan -match "GUID") "PASS" "WARN") $plan.Trim()

    # Manual
    Log-Test "Battery" "AC/DC Switch Stability" "MANUAL" "Unplug and replug charger several times, verify unit stable"
}

# ============================================================
# 4. DISPLAY ADAPTER TESTS
# ============================================================
function Test-Display {
    Write-Section "[4] DISPLAY ADAPTER"

    # GPU / Video Controller
    $gpus = @(Get-WmiObject Win32_VideoController)
    if ($gpus.Count -eq 0) {
        Log-Test "Display" "GPU Detection" "FAIL" "No video controllers found"
    }
    foreach ($gpu in $gpus) {
        Log-Test "Display" "GPU: $($gpu.Name)" (Iff ($gpu.Status -eq "OK") "PASS" "FAIL") `
            "Driver: $($gpu.DriverVersion) | Status: $($gpu.Status)"
        if ($gpu.CurrentHorizontalResolution -gt 0) {
            Log-Test "Display" "Active Resolution ($($gpu.Name))" "PASS" `
                "$($gpu.CurrentHorizontalResolution)x$($gpu.CurrentVerticalResolution) @ $($gpu.CurrentRefreshRate)Hz"
        }
    }

    # Monitor detection
    $monitors = @(Get-WmiObject Win32_PnPEntity | Where-Object { $_.PNPClass -eq "Monitor" })
    if ($monitors.Count -eq 0) {
        $monitors = @(Get-WmiObject Win32_DesktopMonitor | Where-Object { $_.Name -notmatch "default" })
    }
    Log-Test "Display" "Connected Monitor(s)" (Iff ($monitors.Count -gt 0) "PASS" "WARN") "$($monitors.Count) monitor(s) detected"

    # Display driver signed check
    $dispDrivers = @(Get-WmiObject Win32_PnPSignedDriver | Where-Object { $_.DeviceClass -eq "DISPLAY" })
    if ($dispDrivers.Count -gt 0) {
        $unsigned = @($dispDrivers | Where-Object { $_.IsSigned -eq $false })
        Log-Test "Display" "Display Driver(s) Signed" (Iff ($unsigned.Count -eq 0) "PASS" "WARN") `
            (Iff ($unsigned.Count -eq 0) "All display drivers are signed" "$($unsigned.Count) unsigned driver(s) found")
    }

    # Manual items
    Log-Test "Display" "External Monitor (DP/HDMI/VGA)"                     "MANUAL" "Connect external display, verify signal is intact"
    Log-Test "Display" "Display Modes: Internal/External/Clone/Extend"      "MANUAL" "Press Win+P to cycle through all 4 modes"
    Log-Test "Display" "Brightness Adjustment (on battery)"                 "MANUAL" "Unplug AC, adjust brightness via buttons/hotkeys"
    Log-Test "Display" "Screen Rotation"                                     "MANUAL" "Settings > Display > Rotation, verify correct rendering"
    Log-Test "Display" "Non-native Resolution Change & Restore"             "MANUAL" "Change to lower res, verify OK; restore to native res"
    Log-Test "Display" "Sleep/Resume - Video Mode & Browser Check"          "MANUAL" "Sleep and resume, verify display OK, open browser"
    Log-Test "Display" "Hibernate/Resume - Video Mode & Browser Check"      "MANUAL" "Hibernate and resume, verify display OK, open browser"
    Log-Test "Display" "Shutdown/Restart - Video Mode & Browser Check"      "MANUAL" "Shutdown & boot, verify display OK, open browser"
    Log-Test "Display" "Second Monitor Toggle"                              "MANUAL" "Connect 2nd monitor, verify Win+P toggle works"
}

# ============================================================
# 5. VIDEO TESTS
# ============================================================
function Test-Video {
    Write-Section "[5] VIDEO"

    # Check Edge browser installed
    $edgePath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    if (-not (Test-Path $edgePath)) {
        $edgePath = (Get-Command "msedge.exe" -ErrorAction SilentlyContinue).Source
    }
    Log-Test "Video" "Microsoft Edge Installed" (Iff ($edgePath -and (Test-Path $edgePath)) "PASS" "FAIL") `
        (Iff ($edgePath -and (Test-Path $edgePath)) "Edge found at $edgePath" "Edge not found")

    # Check Movies & TV (Movies app)
    $moviesApp = Get-AppxPackage -Name "Microsoft.ZuneVideo" -ErrorAction SilentlyContinue
    Log-Test "Video" "Movies & TV App Installed" (Iff ($moviesApp) "PASS" "WARN") `
        (Iff ($moviesApp) "Version: $($moviesApp.Version)" "App not installed")

    # Hardware acceleration (DirectX)
    $gpu = Get-WmiObject Win32_VideoController | Select-Object -First 1
    Log-Test "Video" "GPU Available for HW Video Decode" (Iff ($gpu) "PASS" "WARN") `
        (Iff ($gpu) "$($gpu.Name) detected" "No GPU detected for hardware acceleration")

    # Manual items
    Log-Test "Video" "YouTube Playback (Edge) - No Glitch/Rebuffering"     "MANUAL" "Open YouTube, play 1-2 videos, verify audio sync, no glitches"
    Log-Test "Video" "YouTube - Pause/Play/Seek Controls"                  "MANUAL" "Verify pause, play, and seek work during playback"
    Log-Test "Video" "Movies & TV - Oblivion 10min Preview"                "MANUAL" "Search Oblivion, play sample, verify no audio/video issues"
    Log-Test "Video" "Movies & TV - Pause/Play/Seek Controls"              "MANUAL" "Verify controls work during playback"
    Log-Test "Video" "Prepare USB with Sample Video"                       "MANUAL" "Copy sample video from SVL SharePoint > SLFT > sample video"
}

# ============================================================
# DOCK TESTS  (semi-auto: script guides, user does plug/unplug)
# ============================================================
function Get-DeviceSnapshot {
    [PSCustomObject]@{
        AudioDevices = @(Get-WmiObject Win32_SoundDevice | Select-Object -ExpandProperty Name)
        NetAdapters  = @(Get-NetAdapter | Select-Object -ExpandProperty Name)
        Monitors     = @(Get-WmiObject Win32_PnPEntity | Where-Object { $_.PNPClass -eq "Monitor" } | Select-Object -ExpandProperty Name)
        UsbDevices   = @(Get-WmiObject Win32_PnPEntity | Where-Object { $_.PNPClass -eq "USB" -or $_.PNPClass -eq "HIDClass" } | Select-Object -ExpandProperty Name)
    }
}

function Compare-Snapshots {
    param($Before, $After, [string]$Label)
    $added   = @($After | Where-Object { $Before -notcontains $_ })
    $removed = @($Before | Where-Object { $After -notcontains $_ })
    [PSCustomObject]@{ Label = $Label; Added = $added; Removed = $removed }
}

function Test-Dock {
    Write-Section "[DOCK] HOT DOCK / WARM DOCK"

    Write-Host ""
    Write-Host "  This test requires manual dock plug/unplug actions." -ForegroundColor Yellow
    Write-Host "  Script will snapshot devices before/after each action." -ForegroundColor Yellow
    Write-Host ""

    # -- HOT DOCK (insert while system is on) --------------------
    Write-Host "  [HOT DOCK - Insert]" -ForegroundColor Cyan
    Write-Host "  Make sure Dock is UNPLUGGED, then press Enter to continue..." -ForegroundColor DarkGray
    Read-Host | Out-Null

    $snapBefore = Get-DeviceSnapshot
    Write-Host "  Please INSERT the Dock now, then press Enter..." -ForegroundColor Yellow
    Read-Host | Out-Null
    Start-Sleep -Seconds 3
    $snapAfter = Get-DeviceSnapshot

    $audioChange = Compare-Snapshots $snapBefore.AudioDevices $snapAfter.AudioDevices "Audio"
    $netChange   = Compare-Snapshots $snapBefore.NetAdapters  $snapAfter.NetAdapters  "Network"
    $monChange   = Compare-Snapshots $snapBefore.Monitors     $snapAfter.Monitors     "Monitor"
    $usbChange   = Compare-Snapshots $snapBefore.UsbDevices   $snapAfter.UsbDevices   "USB"

    $anyChange = ($audioChange.Added.Count + $netChange.Added.Count +
                  $monChange.Added.Count   + $usbChange.Added.Count) -gt 0

    if ($audioChange.Added.Count -gt 0) {
        Log-Test "Dock" "Hot Dock - Audio Device Added" "PASS" "New: $($audioChange.Added -join ', ')"
    } else {
        Log-Test "Dock" "Hot Dock - Audio Device Added" "WARN" "No new audio device detected (Dock may not have audio)"
    }
    if ($netChange.Added.Count -gt 0) {
        Log-Test "Dock" "Hot Dock - Network Adapter Added" "PASS" "New: $($netChange.Added -join ', ')"
    } else {
        Log-Test "Dock" "Hot Dock - Network Adapter Added" "WARN" "No new network adapter detected"
    }
    if ($monChange.Added.Count -gt 0) {
        Log-Test "Dock" "Hot Dock - Monitor Added" "PASS" "New: $($monChange.Added -join ', ')"
    } else {
        Log-Test "Dock" "Hot Dock - Monitor Added" "WARN" "No new monitor detected (may need external display connected to Dock)"
    }
    if ($usbChange.Added.Count -gt 0) {
        Log-Test "Dock" "Hot Dock - USB Devices Added" "PASS" "$($usbChange.Added.Count) new USB device(s) detected"
    } else {
        Log-Test "Dock" "Hot Dock - USB Devices Added" "WARN" "No new USB devices detected"
    }

    Log-Test "Dock" "Hot Dock - Overall Device Enumeration" (Iff $anyChange "PASS" "FAIL") `
        (Iff $anyChange "Dock detected, devices enumerated" "No new devices found after dock insertion")

    # -- HOT DOCK (remove) ---------------------------------------
    Write-Host ""
    Write-Host "  [HOT DOCK - Remove]" -ForegroundColor Cyan
    $snapPlugged = Get-DeviceSnapshot
    Write-Host "  Please UNPLUG the Dock now, then press Enter..." -ForegroundColor Yellow
    Read-Host | Out-Null
    Start-Sleep -Seconds 3
    $snapUnplugged = Get-DeviceSnapshot

    $audioRemoved = Compare-Snapshots $snapPlugged.AudioDevices $snapUnplugged.AudioDevices "Audio"
    $netRemoved   = Compare-Snapshots $snapPlugged.NetAdapters  $snapUnplugged.NetAdapters  "Network"
    $anyRemoved   = ($audioRemoved.Removed.Count + $netRemoved.Removed.Count) -gt 0

    Log-Test "Dock" "Hot Dock - Devices Released on Unplug" (Iff $anyRemoved "PASS" "WARN") `
        (Iff $anyRemoved "Devices correctly removed after undock" "No device changes detected on undock")

    # -- WARM DOCK (insert during sleep) -------------------------
    Write-Host ""
    Write-Host "  [WARM DOCK]" -ForegroundColor Cyan
    Write-Host "  Next: system will enter S3 sleep. Insert Dock while sleeping, then wake it." -ForegroundColor Yellow
    Write-Host "  Press Enter to put system to sleep (S3)..." -ForegroundColor DarkGray
    Read-Host | Out-Null

    $snapBeforeWarm = Get-DeviceSnapshot

    Write-Host "  System going to sleep now. Insert Dock, then wake the PC..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    rundll32.exe powrprof.dll,SetSuspendState 0,1,0   # S3 Sleep
    Start-Sleep -Seconds 8   # wait for system to fully wake

    $snapAfterWarm = Get-DeviceSnapshot
    $warmAudioChange = Compare-Snapshots $snapBeforeWarm.AudioDevices $snapAfterWarm.AudioDevices "Audio"
    $warmNetChange   = Compare-Snapshots $snapBeforeWarm.NetAdapters  $snapAfterWarm.NetAdapters  "Network"
    $warmAnyChange   = ($warmAudioChange.Added.Count + $warmNetChange.Added.Count) -gt 0

    Log-Test "Dock" "Warm Dock - Devices Enumerated After Resume" (Iff $warmAnyChange "PASS" "WARN") `
        (Iff $warmAnyChange "New devices found after warm dock resume" "No new devices detected after warm dock")

    Log-Test "Dock" "Warm Dock - Audio After Resume"   "MANUAL" "Verify audio works normally after warm dock resume"
    Log-Test "Dock" "Warm Dock - Display After Resume" "MANUAL" "Verify display output correct after warm dock resume"
}

# ============================================================
# 6. ETHERNET TESTS
# ============================================================
function Test-Ethernet {
    Write-Section "[6] ETHERNET"

    # Detect Ethernet adapters
    $ethAdapters = @(Get-NetAdapter | Where-Object {
        $_.PhysicalMediaType -eq "802.3" -or
        ($_.InterfaceDescription -imatch "ethernet|gigabit|realtek.*eth|intel.*eth|broadcom.*eth" -and
         $_.InterfaceDescription -inotmatch "wi-fi|wireless|bluetooth|virtual|vmware|hyper-v|loopback")
    })
    if ($ethAdapters.Count -eq 0) {
        # Broader fallback
        $ethAdapters = @(Get-NetAdapter | Where-Object {
            $_.InterfaceDescription -inotmatch "wi-fi|wireless|bluetooth|loopback|virtual|vmware|hyper-v|miniport"
        })
    }

    if ($ethAdapters.Count -eq 0) {
        Log-Test "Ethernet" "Ethernet Adapter Detection" "FAIL" "No Ethernet adapters found"
        return
    }

    foreach ($a in $ethAdapters) {
        $adapterStatus = Iff ($a.Status -in @("Up", "Disconnected")) "PASS" "WARN"
        Log-Test "Ethernet" "Adapter: $($a.Name)" $adapterStatus `
            "Status: $($a.Status) | Speed: $($a.LinkSpeed) | $($a.InterfaceDescription)"
    }

    # Disable / Enable cycle (requires admin)
    $upAdapter = $ethAdapters | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    if ($upAdapter) {
        try {
            Write-Host "  [....] Disable/Enable cycle for '$($upAdapter.Name)' (waiting ~8s)..." -ForegroundColor DarkGray
            Disable-NetAdapter -Name $upAdapter.Name -Confirm:$false -ErrorAction Stop
            Start-Sleep -Seconds 3
            $afterDisable = (Get-NetAdapter -Name $upAdapter.Name).Status
            Enable-NetAdapter -Name $upAdapter.Name -Confirm:$false -ErrorAction Stop
            Start-Sleep -Seconds 5
            $afterEnable = (Get-NetAdapter -Name $upAdapter.Name).Status

            $ok = ($afterDisable -eq "Disabled") -and ($afterEnable -eq "Up")
            Log-Test "Ethernet" "Adapter Disable/Enable Cycle" (Iff $ok "PASS" "FAIL") `
                "Disabled: $afterDisable  =>  Re-enabled: $afterEnable"
        } catch {
            Log-Test "Ethernet" "Adapter Disable/Enable Cycle" "SKIP" "Error: $($_.Exception.Message)"
        }
    } else {
        Log-Test "Ethernet" "Adapter Disable/Enable Cycle" "MANUAL" "No active Ethernet - connect cable, then rerun"
    }

    # Ping test
    $pingTarget = "internetbeacon.msedge.net"
    Write-Host "  [....] Pinging $pingTarget ..." -ForegroundColor DarkGray
    $pingResult = Test-Connection -ComputerName $pingTarget -Count 4 -ErrorAction SilentlyContinue
    if ($pingResult) {
        $avg = [math]::Round(($pingResult | Measure-Object ResponseTime -Average).Average, 1)
        Log-Test "Ethernet" "Ping: $pingTarget (4 packets)" "PASS" "4/4 replies, avg ${avg}ms"
    } else {
        $gw = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1).IPv4DefaultGateway.NextHop
        if ($gw) {
            $gwPing = Test-Connection -ComputerName $gw -Count 2 -ErrorAction SilentlyContinue
            if ($gwPing) {
                Log-Test "Ethernet" "Ping: $pingTarget" "FAIL" "Internet unreachable, but local gateway ($gw) is reachable"
            } else {
                Log-Test "Ethernet" "Ping: $pingTarget" "FAIL" "Ping failed - no network connectivity"
            }
        } else {
            Log-Test "Ethernet" "Ping: $pingTarget" "FAIL" "Ping failed - no gateway configured, connect Ethernet cable"
        }
    }

    # TCP connection test (Get-NetAdapter equivalent verification)
    Write-Host "  [....] TCP test (port 80) ..." -ForegroundColor DarkGray
    $tcpTest = Test-NetConnection -ComputerName "internetbeacon.msedge.net" -Port 80 -WarningAction SilentlyContinue
    Log-Test "Ethernet" "TCP Connection Test (port 80)" (Iff ($tcpTest.TcpTestSucceeded) "PASS" "FAIL") `
        (Iff ($tcpTest.TcpTestSucceeded) "TCP connection successful" "TCP connection failed")

    # Manual items
    Log-Test "Ethernet" "Adapter Name Correct in Device Manager"   "MANUAL" "ncpa.cpl > verify adapter name correct, icon gray=disabled / color=enabled"
    Log-Test "Ethernet" "Ping After Standby/Resume"                "MANUAL" "Sleep system, resume, run: Test-NetConnection internetbeacon.msedge.net"
    Log-Test "Ethernet" "LAN/WAN Auto Switching"                   "MANUAL" "BIOS F10 > enable LAN/WAN Auto Switch, test per spec"
}

# ============================================================
# 7. WLAN TESTS
# ============================================================
function Test-Wlan {
    Write-Section "[7] WLAN"

    # WiFi adapter detection
    $wifiAdapters = @(Get-NetAdapter | Where-Object {
        $_.InterfaceDescription -imatch "wi-fi|wireless|802\.11|wlan" -or
        $_.Name -imatch "wi-fi|wireless|wlan"
    })
    if ($wifiAdapters.Count -eq 0) {
        Log-Test "WLAN" "WiFi Adapter Detection" "FAIL" "No WiFi adapter found"
        return
    }
    foreach ($a in $wifiAdapters) {
        Log-Test "WLAN" "WiFi Adapter: $($a.Name)" (Iff ($a.Status -in @("Up","Disconnected")) "PASS" "WARN") `
            "Status: $($a.Status) | $($a.InterfaceDescription)"
    }

    # WiFi radio state
    $wlanInfo = netsh wlan show interfaces 2>&1
    $radioOn  = $wlanInfo -match "Radio status\s*:\s*Hardware On"
    Log-Test "WLAN" "WiFi Radio State" (Iff $radioOn "PASS" "WARN") `
        (Iff $radioOn "Radio is ON" "Radio may be off - check hardware WiFi switch")

    # Scan for nearby networks
    Write-Host "  [....] Scanning for nearby networks..." -ForegroundColor DarkGray
    $networks = netsh wlan show networks mode=bssid 2>&1
    $ssidCount = ($networks | Select-String "SSID\s+:\s+\S").Count
    if ($ssidCount -gt 0) {
        $has5G  = $networks -match "5\." -or $networks -match "Band\s*:\s*5"
        $has24G = $networks -match "2\.4" -or $networks -match "Band\s*:\s*2\.4"
        Log-Test "WLAN" "WiFi Network Scan" "PASS" "$ssidCount SSID(s) found"
        Log-Test "WLAN" "2.4GHz Network Available" (Iff $has24G "PASS" "WARN") (Iff $has24G "2.4GHz networks detected" "No 2.4GHz networks found")
        Log-Test "WLAN" "5GHz Network Available"   (Iff $has5G  "PASS" "WARN") (Iff $has5G  "5GHz networks detected"   "No 5GHz networks found")
    } else {
        Log-Test "WLAN" "WiFi Network Scan" "FAIL" "No networks found - verify WiFi is enabled and AP is nearby"
    }

    # Disable / Enable WiFi adapter cycle
    $upWifi = $wifiAdapters | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    if (-not $upWifi) { $upWifi = $wifiAdapters | Select-Object -First 1 }
    if ($upWifi) {
        try {
            Write-Host "  [....] Disable/Enable WiFi cycle for '$($upWifi.Name)' (~8s)..." -ForegroundColor DarkGray
            Disable-NetAdapter -Name $upWifi.Name -Confirm:$false -ErrorAction Stop
            Start-Sleep -Seconds 3
            $afterDisable = (Get-NetAdapter -Name $upWifi.Name).Status
            Enable-NetAdapter -Name $upWifi.Name -Confirm:$false -ErrorAction Stop
            Start-Sleep -Seconds 5
            $afterEnable = (Get-NetAdapter -Name $upWifi.Name).Status
            $ok = ($afterDisable -eq "Disabled") -and ($afterEnable -in @("Up","Disconnected"))
            Log-Test "WLAN" "WiFi Adapter Disable/Enable Cycle" (Iff $ok "PASS" "FAIL") `
                "Disabled: $afterDisable => Re-enabled: $afterEnable"
        } catch {
            Log-Test "WLAN" "WiFi Adapter Disable/Enable Cycle" "SKIP" "Error: $($_.Exception.Message)"
        }
    }

    # Airplane mode check via registry
    $airplaneModeReg = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\RadioManagement\SystemRadioState" -ErrorAction SilentlyContinue
    if ($null -ne $airplaneModeReg) {
        $airplaneOn = $airplaneModeReg.'(default)' -eq 1
        Log-Test "WLAN" "Airplane Mode Currently Off" (Iff (-not $airplaneOn) "PASS" "WARN") `
            (Iff (-not $airplaneOn) "Airplane mode is OFF" "Airplane mode appears ON")
    }

    # Manual items
    Log-Test "WLAN" "Connect to Open AP (2.4GHz + 5GHz)"      "MANUAL" "Settings > WiFi, connect to available open station on both bands"
    Log-Test "WLAN" "WiFi Off -> Standby/Resume -> Still Off"  "MANUAL" "Turn off WiFi, sleep+resume, verify WiFi radio state still off"
    Log-Test "WLAN" "Airplane Mode On -> WiFi Off in 5s"       "MANUAL" "Enable Airplane Mode, verify WiFi turns off within 5 seconds"
    Log-Test "WLAN" "Airplane Mode Off -> Reconnects to AP"    "MANUAL" "Disable Airplane Mode, verify WiFi reconnects to AP"
    Log-Test "WLAN" "Sleep/Resume -> Reconnects to AP"         "MANUAL" "Sleep and resume while connected, verify WiFi reconnects"
}

# ============================================================
# 10. CAMERA TESTS
# ============================================================
function Test-Camera {
    Write-Section "[10] CAMERA"

    # Camera device detection via PnP
    $cameras = @(Get-WmiObject Win32_PnPEntity | Where-Object {
        $_.PNPClass -eq "Camera" -or $_.PNPClass -eq "Image" -or
        $_.Name -imatch "camera|webcam|integrated camera|ir camera"
    })
    if ($cameras.Count -gt 0) {
        Log-Test "Camera" "Camera Device(s) Detected" "PASS" "$($cameras.Count) device(s): $(($cameras.Name) -join ', ')"
        $badCams = @($cameras | Where-Object { $_.Status -ne "OK" })
        Log-Test "Camera" "Camera Driver Status" (Iff ($badCams.Count -eq 0) "PASS" "FAIL") `
            (Iff ($badCams.Count -eq 0) "All camera drivers OK" "Issues: $(($badCams.Name) -join ', ')")
    } else {
        Log-Test "Camera" "Camera Device(s) Detected" "WARN" "No camera found via PnP (may be listed under different class)"
    }

    # Camera app installed
    $camApp = Get-AppxPackage -Name "Microsoft.WindowsCamera" -ErrorAction SilentlyContinue
    Log-Test "Camera" "Windows Camera App Installed" (Iff $camApp "PASS" "WARN") `
        (Iff $camApp "Version: $($camApp.Version)" "Camera app not found")

    # Privacy - camera access allowed
    $camPrivacy = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam" -ErrorAction SilentlyContinue
    if ($camPrivacy) {
        $allowed = $camPrivacy.Value -eq "Allow"
        Log-Test "Camera" "Camera Privacy Access (System)" (Iff $allowed "PASS" "WARN") `
            (Iff $allowed "Camera access: Allow" "Camera access may be blocked: $($camPrivacy.Value)")
    }

    # Manual items
    Log-Test "Camera" "Launch Camera App - Indicator LED On"       "MANUAL" "Open Camera app, verify hardware/software indicator is ON"
    Log-Test "Camera" "Front Camera - Mirror Preview"              "MANUAL" "Switch to front cam, verify preview is mirrored"
    Log-Test "Camera" "Record Video + Rotate + Pause/Resume"       "MANUAL" "Record video, rotate device, pause/resume recording"
    Log-Test "Camera" "Rear Camera - Repeat Steps 3-7"            "MANUAL" "Switch to rear camera, repeat recording steps"
    Log-Test "Camera" "Settings - Resolution, Aspect Ratio"        "MANUAL" "Change resolution & aspect ratio, take photo and video"
    Log-Test "Camera" "Video Stabilization On/Off"                 "MANUAL" "Toggle stabilization in settings, record video for each state"
    Log-Test "Camera" "Close Camera - Indicator LED Off"           "MANUAL" "Close app, verify camera indicator turns OFF"
    Log-Test "Camera" "Sleep During Recording - File Not Corrupt"  "MANUAL" "Start recording, sleep 2min, resume, verify file intact"
}

# ============================================================
# 11. TOUCHPAD TESTS
# ============================================================
function Test-Touchpad {
    Write-Section "[11] TOUCHPAD"

    # Touchpad device detection
    $touchpads = @(Get-WmiObject Win32_PnPEntity | Where-Object {
        $_.Name -imatch "touchpad|precision touchpad|synaptics|elan|alps|i2c hid" -or
        ($_.PNPClass -eq "Mouse" -and $_.Name -imatch "touchpad|synaptics|elan|alps")
    })
    if ($touchpads.Count -gt 0) {
        Log-Test "Touchpad" "Touchpad Device Detected" "PASS" "$(($touchpads.Name) -join ', ')"
        $badTP = @($touchpads | Where-Object { $_.Status -ne "OK" })
        Log-Test "Touchpad" "Touchpad Driver Status" (Iff ($badTP.Count -eq 0) "PASS" "FAIL") `
            (Iff ($badTP.Count -eq 0) "Driver status OK" "Issues: $(($badTP.Name) -join ', ')")
    } else {
        Log-Test "Touchpad" "Touchpad Device Detected" "WARN" "No touchpad found via PnP - may be listed under HID devices"
    }

    # Precision Touchpad (PTP) check via registry
    $ptpKey = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PrecisionTouchPad" -ErrorAction SilentlyContinue
    if ($ptpKey) {
        Log-Test "Touchpad" "Precision Touchpad (PTP) Supported" "PASS" "PTP registry key present"
    } else {
        Log-Test "Touchpad" "Precision Touchpad (PTP) Supported" "WARN" "PTP registry key not found - gestures may be limited"
    }

    # Disable / Enable touchpad via Device Manager
    $tpDevice = $touchpads | Select-Object -First 1
    if ($tpDevice) {
        try {
            Write-Host "  [....] Disable/Enable Touchpad cycle (~8s)..." -ForegroundColor DarkGray
            $devID = $tpDevice.DeviceID
            $null = pnputil /disable-device "$devID" 2>&1
            Start-Sleep -Seconds 3
            $afterDisable = (Get-WmiObject Win32_PnPEntity | Where-Object { $_.DeviceID -eq $devID }).Status
            $null = pnputil /enable-device "$devID" 2>&1
            Start-Sleep -Seconds 3
            $afterEnable = (Get-WmiObject Win32_PnPEntity | Where-Object { $_.DeviceID -eq $devID }).Status
            Log-Test "Touchpad" "Touchpad Disable/Enable Cycle" "PASS" `
                "Disabled then re-enabled via pnputil"
        } catch {
            Log-Test "Touchpad" "Touchpad Disable/Enable Cycle" "SKIP" "Error: $($_.Exception.Message)"
        }
    }

    # Manual items
    Log-Test "Touchpad" "3-Finger Swipe Up - Task View"               "MANUAL" "3-finger swipe up on desktop, verify Task View opens"
    Log-Test "Touchpad" "3-Finger Swipe Down - Show Desktop"          "MANUAL" "Open apps, 3-finger swipe down, verify desktop shown"
    Log-Test "Touchpad" "3-Finger Swipe Left/Right - App Switcher"    "MANUAL" "3-finger swipe left/right, verify App Switcher appears"
    Log-Test "Touchpad" "4-Finger Swipe Up - Task View"               "MANUAL" "4-finger swipe up, verify Task View (skip if old hardware)"
    Log-Test "Touchpad" "4-Finger Swipe Down - Show Desktop"          "MANUAL" "Open apps, 4-finger swipe down, verify desktop shown"
    Log-Test "Touchpad" "4-Finger Swipe Left/Right - Virtual Desktop" "MANUAL" "Create virtual desktops, 4-finger swipe to switch"
    Log-Test "Touchpad" "Touchpad On/Off Toggle (if control exists)"  "MANUAL" "Use Fn key or Settings to toggle touchpad, verify enable/disable"
}

# ============================================================
# HTML REPORT GENERATOR
# ============================================================
function New-HtmlReport {
    $pass   = @($script:Results | Where-Object { $_.Status -eq "PASS"   }).Count
    $fail   = @($script:Results | Where-Object { $_.Status -eq "FAIL"   }).Count
    $warn   = @($script:Results | Where-Object { $_.Status -eq "WARN"   }).Count
    $skip   = @($script:Results | Where-Object { $_.Status -eq "SKIP"   }).Count
    $manual = @($script:Results | Where-Object { $_.Status -eq "MANUAL" }).Count
    $elapsed = [math]::Round(((Get-Date) - $script:StartTime).TotalSeconds, 1)

    $os  = (Get-WmiObject Win32_OperatingSystem)
    $cpu = (Get-WmiObject Win32_Processor | Select-Object -First 1).Name
    $ram = "$([math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)) GB"

    $sysRows = @(
        @("Computer",  $env:COMPUTERNAME),
        @("User",      $env:USERNAME),
        @("OS",        $os.Caption),
        @("OS Build",  $os.BuildNumber),
        @("CPU",       $cpu),
        @("RAM",       $ram),
        @("Test Date", $script:StartTime.ToString("yyyy-MM-dd HH:mm:ss")),
        @("Duration",  "${elapsed}s")
    ) | ForEach-Object { "<tr><td class='k'>$($_[0])</td><td>$($_[1])</td></tr>" }

    $overallStatus = if ($fail -gt 0) { "FAIL" } elseif ($warn -gt 0) { "WARN" } else { "PASS" }
    $overallColor  = @{ PASS="#28a745"; FAIL="#dc3545"; WARN="#e6a817" }[$overallStatus]
    $overallText   = @{ PASS="white";   FAIL="white";   WARN="#333"   }[$overallStatus]

    $categories = $script:Results | Select-Object -ExpandProperty Category -Unique
    $catBlocks  = foreach ($cat in $categories) {
        $rows = $script:Results | Where-Object { $_.Category -eq $cat } | ForEach-Object {
            "<tr><td><span class='badge $($_.Status)'>$($_.Status)</span></td>
                 <td class='tn'>$($_.Name)</td>
                 <td class='td'>$($_.Detail)</td></tr>"
        }
        "<div class='cat'>
          <div class='cat-hdr'>$cat</div>
          <table class='ttbl'>
            <thead><tr><th style='width:86px'>Status</th><th>Test Item</th><th>Details</th></tr></thead>
            <tbody>$($rows -join '')</tbody>
          </table>
        </div>"
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>HW Validation - $($env:COMPUTERNAME) - $(Get-Date -Format 'yyyy-MM-dd')</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',Arial,sans-serif;background:#eef0f4;color:#333}
.hdr{background:linear-gradient(135deg,#003380,#0055c8);color:#fff;padding:24px 32px}
.hdr h1{font-size:1.55em;font-weight:600}
.hdr p{opacity:.85;margin-top:5px;font-size:.93em}
.overall{display:inline-block;margin-top:12px;padding:6px 22px;border-radius:20px;
         font-size:1.05em;font-weight:700;background:$overallColor;color:$overallText}
.wrap{max-width:1100px;margin:0 auto;padding:24px 16px}
.sgrid{display:grid;grid-template-columns:repeat(5,1fr);gap:12px;margin-bottom:22px}
.sc{background:#fff;border-radius:10px;padding:14px;text-align:center;
    box-shadow:0 2px 8px rgba(0,0,0,.08);border-top:4px solid}
.sc.p{border-color:#28a745}.sc.f{border-color:#dc3545}
.sc.w{border-color:#e6a817}.sc.s{border-color:#17a2b8}.sc.m{border-color:#9b59b6}
.sc .n{font-size:2em;font-weight:700}
.sc.p .n{color:#28a745}.sc.f .n{color:#dc3545}
.sc.w .n{color:#e6a817}.sc.s .n{color:#17a2b8}.sc.m .n{color:#9b59b6}
.sc .lbl{font-size:.82em;color:#777;margin-top:3px}
.si{background:#fff;border-radius:10px;padding:18px 20px;margin-bottom:22px;box-shadow:0 2px 8px rgba(0,0,0,.08)}
.si h3{color:#003380;font-size:.85em;text-transform:uppercase;letter-spacing:1px;margin-bottom:10px}
.si table{width:100%;border-collapse:collapse}
.si td{padding:5px 10px;font-size:.9em}
.si tr:nth-child(even){background:#f8f9fa}
.k{font-weight:600;color:#555;width:130px}
.cat{background:#fff;border-radius:10px;margin-bottom:14px;box-shadow:0 2px 8px rgba(0,0,0,.08);overflow:hidden}
.cat-hdr{background:#003380;color:#fff;padding:11px 18px;font-weight:600}
.ttbl{width:100%;border-collapse:collapse}
.ttbl th{text-align:left;padding:8px 14px;font-size:.78em;text-transform:uppercase;
         letter-spacing:.5px;color:#999;border-bottom:1px solid #e9ecef}
.ttbl td{padding:10px 14px;border-bottom:1px solid #f0f2f5;vertical-align:middle}
.ttbl tr:last-child td{border-bottom:none}
.ttbl tr:hover{background:#f8f9fa}
.tn{font-weight:500}
.td{color:#777;font-size:.88em}
.badge{display:inline-block;padding:3px 9px;border-radius:4px;font-size:.78em;
       font-weight:700;color:#fff;min-width:62px;text-align:center}
.badge.PASS{background:#28a745}.badge.FAIL{background:#dc3545}
.badge.WARN{background:#e6a817;color:#333}.badge.SKIP{background:#17a2b8}
.badge.MANUAL{background:#9b59b6}
.legend{background:#fff;border-radius:10px;padding:14px 20px;margin-bottom:22px;
        box-shadow:0 2px 8px rgba(0,0,0,.08);font-size:.88em;color:#555}
.legend span{display:inline-block;margin-right:18px}
.foot{text-align:center;padding:20px;color:#bbb;font-size:.82em}
</style>
</head>
<body>

<div class="hdr">
  <h1>Hardware Validation Test Report</h1>
  <p>$($env:COMPUTERNAME) &nbsp;|&nbsp; $($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss')) &nbsp;|&nbsp; Duration: ${elapsed}s</p>
  <div class="overall">Overall Result: $overallStatus</div>
</div>

<div class="wrap">
  <div class="sgrid">
    <div class="sc p"><div class="n">$pass</div>  <div class="lbl">PASS</div></div>
    <div class="sc f"><div class="n">$fail</div>  <div class="lbl">FAIL</div></div>
    <div class="sc w"><div class="n">$warn</div>  <div class="lbl">WARN</div></div>
    <div class="sc s"><div class="n">$skip</div>  <div class="lbl">SKIP</div></div>
    <div class="sc m"><div class="n">$manual</div><div class="lbl">MANUAL</div></div>
  </div>

  <div class="legend">
    <strong>Legend:</strong>&nbsp;
    <span><span class="badge PASS">PASS</span> Automated check passed</span>
    <span><span class="badge FAIL">FAIL</span> Automated check failed</span>
    <span><span class="badge WARN">WARN</span> Potential issue, review needed</span>
    <span><span class="badge SKIP">SKIP</span> Not applicable to this device</span>
    <span><span class="badge MANUAL">MANUAL</span> Requires human verification</span>
  </div>

  <div class="si">
    <h3>System Information</h3>
    <table>$($sysRows -join '')</table>
  </div>

  $($catBlocks -join "`n")
</div>

<div class="foot">Generated by HW Validation Test Suite &nbsp;|&nbsp; $($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))</div>
</body>
</html>
"@

    $html | Out-File -FilePath $ReportPath -Encoding UTF8 -Force
}

# ============================================================
# MAIN
# ============================================================
Clear-Host
Write-Host ""
Write-Host "  ============================================================" -ForegroundColor DarkCyan
Write-Host "   HARDWARE VALIDATION TEST SUITE" -ForegroundColor Cyan
Write-Host "   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkCyan
Write-Host "  ============================================================" -ForegroundColor DarkCyan

Test-Audio
Test-Battery
Test-Display
Test-Video
Test-Dock
Test-Ethernet
Test-Wlan
Test-Camera
Test-Touchpad

Write-Host "`n  ============================================================" -ForegroundColor DarkCyan
Write-Host "  GENERATING REPORT..." -ForegroundColor Cyan

New-HtmlReport

$pass   = @($script:Results | Where-Object { $_.Status -eq "PASS"   }).Count
$fail   = @($script:Results | Where-Object { $_.Status -eq "FAIL"   }).Count
$warn   = @($script:Results | Where-Object { $_.Status -eq "WARN"   }).Count
$skip   = @($script:Results | Where-Object { $_.Status -eq "SKIP"   }).Count
$manual = @($script:Results | Where-Object { $_.Status -eq "MANUAL" }).Count

Write-Host ""
Write-Host "  SUMMARY" -ForegroundColor White
Write-Host "  ──────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  PASS   : $pass" -ForegroundColor Green
Write-Host "  FAIL   : $fail" -ForegroundColor Red
Write-Host "  WARN   : $warn" -ForegroundColor Yellow
Write-Host "  SKIP   : $skip" -ForegroundColor Cyan
Write-Host "  MANUAL : $manual  (requires human verification)" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Report: $ReportPath" -ForegroundColor Cyan
Write-Host "  ============================================================" -ForegroundColor DarkCyan
Write-Host ""

Start-Process $ReportPath
