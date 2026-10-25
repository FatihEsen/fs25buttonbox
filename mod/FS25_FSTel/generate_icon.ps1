Add-Type -AssemblyName System.Drawing

$outputPath = "d:\Documents\Agv\fs25buttonbox\mod\FS25_FSTel\icon.png"
$bmp = New-Object System.Drawing.Bitmap 512, 512
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

# Background dark gradient
$p1 = New-Object System.Drawing.Point 0, 0
$p2 = New-Object System.Drawing.Point 512, 512
$c1 = [System.Drawing.Color]::FromArgb(18, 24, 20)
$c2 = [System.Drawing.Color]::FromArgb(26, 38, 30)
$brushBg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $p1, $p2, $c1, $c2
$g.FillRectangle($brushBg, 0, 0, 512, 512)

# Border
$penBorder = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(46, 125, 50)), 12
$g.DrawRectangle($penBorder, 24, 24, 464, 464)

$penAmber = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 179, 0)), 6
$g.DrawArc($penAmber, 70, 70, 372, 372, 135, 270)

# Main Title FSTel
$fontBig = [System.Drawing.Font]::new("Arial", [float]56, [System.Drawing.FontStyle]::Bold)
$brushGreen = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(76, 175, 80))
$brushWhite = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(240, 240, 240))
$brushAmber = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 179, 0))
$brushGray = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(160, 160, 160))

$format = New-Object System.Drawing.StringFormat
$format.Alignment = [System.Drawing.StringAlignment]::Center
$format.LineAlignment = [System.Drawing.StringAlignment]::Center

$g.DrawString("FSTel", $fontBig, $brushGreen, 256, 190, $format)

$fontSub = [System.Drawing.Font]::new("Arial", [float]20, [System.Drawing.FontStyle]::Bold)
$g.DrawString("FS25 TELEMETRY", $fontSub, $brushWhite, 256, 270, $format)

$fontSmall = [System.Drawing.Font]::new("Arial", [float]14, [System.Drawing.FontStyle]::Regular)
$g.DrawString("& VIRTUAL BUTTON BOX", $fontSmall, $brushAmber, 256, 310, $format)

$fontVer = [System.Drawing.Font]::new("Arial", [float]12, [System.Drawing.FontStyle]::Regular)
$g.DrawString("ISOBUS TERMINAL ECOSYSTEM", $fontVer, $brushGray, 256, 430, $format)

$g.Dispose()
$bmp.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host "Mod icon generated at $outputPath"
