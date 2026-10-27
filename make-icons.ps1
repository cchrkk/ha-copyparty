# Generates copyparty/icon.png (256x256) and copyparty/logo.png (250x100)
# from copyparty's own logo (docs/logo.svg in 9001/copyparty, AFL-3.0).
#
# The SVG is rasterised with headless Edge, because there is no SVG renderer
# available to System.Drawing. Run:  pwsh -File make-icons.ps1
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$outDir = Join-Path $here 'copyparty'
$tmp = Join-Path $env:TEMP 'cp-logos'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

$svgUrl = 'https://raw.githubusercontent.com/9001/copyparty/hovudstraum/docs/logo.svg'
$svg = Join-Path $tmp 'logo.svg'
Invoke-WebRequest -Uri $svgUrl -OutFile $svg -UseBasicParsing

$wrap = Join-Path $tmp 'wrap.html'
@"
<!doctype html>
<html><head><meta charset="utf-8">
<style>
  html,body{margin:0;padding:0;background:transparent;overflow:hidden}
  img{display:block;width:100vw;height:100vh;object-fit:contain}
</style></head>
<body><img src="file:///$($svg -replace '\\','/')"></body></html>
"@ | Set-Content -Path $wrap -Encoding UTF8

$edgeCandidates = @(
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
)
$browser = $edgeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $browser) { throw 'No Edge/Chrome found to rasterise the SVG' }

$render = Join-Path $tmp 'logo-render.png'
if (Test-Path $render) { Remove-Item $render }
& $browser --headless=new --no-first-run --disable-gpu --hide-scrollbars `
    --user-data-dir="$(Join-Path $tmp 'profile')" --force-device-scale-factor=2 `
    --default-background-color=00000000 --window-size=450,311 `
    --screenshot="$render" "file:///$($wrap -replace '\\','/')" | Out-Null
for ($i = 0; $i -lt 30 -and -not (Test-Path $render); $i++) { Start-Sleep -Milliseconds 200 }
if (-not (Test-Path $render)) { throw 'Edge did not write the screenshot' }

$src = [System.Drawing.Image]::FromFile($render)

function New-RoundedPath {
    param([System.Drawing.RectangleF]$Rect, [float]$Radius)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $Radius * 2
    $path.AddArc($Rect.X, $Rect.Y, $d, $d, 180, 90)
    $path.AddArc($Rect.Right - $d, $Rect.Y, $d, $d, 270, 90)
    $path.AddArc($Rect.Right - $d, $Rect.Bottom - $d, $d, $d, 0, 90)
    $path.AddArc($Rect.X, $Rect.Bottom - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

function Save-Scaled {
    param([System.Drawing.Image]$Image, [int]$W, [int]$H, [string]$File, [switch]$Rounded)

    $bmp = New-Object System.Drawing.Bitmap($W, $H)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode = 'HighQuality'
    $g.Clear([System.Drawing.Color]::Transparent)

    $ratio = [Math]::Min($W / $Image.Width, $H / $Image.Height)
    $dw = [int]($Image.Width * $ratio)
    $dh = [int]($Image.Height * $ratio)
    $dx = [int](($W - $dw) / 2)
    $dy = [int](($H - $dh) / 2)

    if ($Rounded) {
        $rect = New-Object System.Drawing.RectangleF(0, 0, $W, $H)
        $round = New-RoundedPath -Rect $rect -Radius ($W * 0.13)
        # the logo's own card colour, so the corners blend with the artwork
        $card = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 40, 40, 40))
        $g.FillPath($card, $round)
        $card.Dispose()
    }

    $g.DrawImage($Image, (New-Object System.Drawing.Rectangle($dx, $dy, $dw, $dh)))
    $bmp.Save((Join-Path $outDir $File), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
}

Save-Scaled -Image $src -W 256 -H 256 -File 'icon.png' -Rounded
Save-Scaled -Image $src -W 250 -H 100 -File 'logo.png'

$src.Dispose()
Write-Host "icons written to $outDir"
