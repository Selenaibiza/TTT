Add-Type -AssemblyName System.Drawing

function New-TicTacToeIcon {
    param(
        [int]$Size,
        [string]$OutFile,
        [double]$Safe = 1.0,
        [switch]$Rounded
    )

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    $c1 = [System.Drawing.ColorTranslator]::FromHtml('#0f172a')
    $c2 = [System.Drawing.ColorTranslator]::FromHtml('#1e3a5f')

    if ($Rounded) {
        $r = [float]($Size * 0.22)
        $d = [float]($r * 2)
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddArc(0, 0, $d, $d, 180, 90)
        $path.AddArc(($Size - $d), 0, $d, $d, 270, 90)
        $path.AddArc(($Size - $d), ($Size - $d), $d, $d, 0, 90)
        $path.AddArc(0, ($Size - $d), $d, $d, 90, 90)
        $path.CloseFigure()

        $rect0 = New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)
        $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect0, $c1, $c2, 60)
        $g.FillPath($bg, $path)
        $g.SetClip($path)
        $bg.Dispose()
        $path.Dispose()
    } else {
        $rect0 = New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)
        $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect0, $c1, $c2, 60)
        $g.FillRectangle($bg, $rect0)
        $bg.Dispose()
    }

    $content = [double]$Size * $Safe
    $off = ([double]$Size - $content) / 2.0

    # شبکه
    $lineW = [float]($content * 0.035)
    $gridColor = [System.Drawing.ColorTranslator]::FromHtml('#3b4a66')
    $gridPen = New-Object System.Drawing.Pen($gridColor, $lineW)
    $gridPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $gridPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

    for ($i = 1; $i -le 2; $i++) {
        $p = [float]($off + $content * $i / 3.0)
        $a = [float]($off + $content * 0.06)
        $b = [float]($off + $content * 0.94)
        $g.DrawLine($gridPen, $a, $p, $b, $p)
        $g.DrawLine($gridPen, $p, $a, $p, $b)
    }
    $gridPen.Dispose()

    $cell = $content / 3.0
    $inset = $cell * 0.24

    # ضربدر (خانه بالا-راست)
    $xColor = [System.Drawing.ColorTranslator]::FromHtml('#38bdf8')
    $xPen = New-Object System.Drawing.Pen($xColor, [float]($cell * 0.16))
    $xPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $xPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($xPen, [float]($off + $inset), [float]($off + $inset), [float]($off + $cell - $inset), [float]($off + $cell - $inset))
    $g.DrawLine($xPen, [float]($off + $cell - $inset), [float]($off + $inset), [float]($off + $inset), [float]($off + $cell - $inset))
    $xPen.Dispose()

    # دایره (خانه وسط)
    $oColor = [System.Drawing.ColorTranslator]::FromHtml('#fb7185')
    $oPen = New-Object System.Drawing.Pen($oColor, [float]($cell * 0.16))
    $oPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $oPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawEllipse($oPen, [float]($off + $cell + $inset), [float]($off + $cell + $inset), [float]($cell - 2 * $inset), [float]($cell - 2 * $inset))
    $oPen.Dispose()

    # ضربدر (خانه پایین-چپ)
    $xPen2 = New-Object System.Drawing.Pen($xColor, [float]($cell * 0.16))
    $xPen2.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $xPen2.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $cx = $off + 2 * $cell
    $cy = $off + 2 * $cell
    $g.DrawLine($xPen2, [float]($cx + $inset), [float]($cy + $inset), [float]($cx + $cell - $inset), [float]($cy + $cell - $inset))
    $g.DrawLine($xPen2, [float]($cx + $cell - $inset), [float]($cy + $inset), [float]($cx + $inset), [float]($cy + $cell - $inset))
    $xPen2.Dispose()

    $g.Dispose()
    $bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

New-TicTacToeIcon -Size 192 -OutFile "icon-192.png" -Rounded
New-TicTacToeIcon -Size 512 -OutFile "icon-512.png" -Rounded
New-TicTacToeIcon -Size 512 -OutFile "icon-maskable-512.png" -Safe 0.56
New-TicTacToeIcon -Size 180 -OutFile "apple-touch-icon.png" -Rounded
Write-Host "icons generated"
