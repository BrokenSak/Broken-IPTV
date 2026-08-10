# Rigenera il banner rettangolare dei launcher TV (Fire OS & co.) partendo da
# tool/tv_banner.html.
#
#   powershell -ExecutionPolicy Bypass -File tool\make_tv_banner.ps1
#
# Perché non è più disegnato con System.Drawing (com'era fino al 71° giro): il
# banner è tipografia, e comporlo con DrawString voleva dire misure a occhio,
# nessun controllo su interlinea e crenatura, e un risultato che era "icona
# quadrata + due parole di fianco". Ora la composizione sta in una pagina HTML —
# dove allineare il blocco del nome all'altezza del marchio è una riga di CSS —
# e questo script la rasterizza e basta.
#
# ⚠️ Si rasterizza UNA volta sola a 640x360 e si scala giù. Edge headless ha una
# larghezza minima di finestra: sotto i ~400px **ritaglia invece di
# rimpicciolire**, e ti ritrovi con un banner tagliato che sembra a posto finché
# non lo apri (a 320 il render diretto è sbagliato). Il ricampionamento bicubico
# da 640 è comunque migliore del render nativo a quella misura.
#
# ⚠️ Dopo l'installazione il Firestick mostra ancora la tessera vecchia: è in
# cache nel LAUNCHER, non nell'app. Serve disinstalla -> riavvio dello stick ->
# installa, e conviene cambiare anche la versione (alcuni launcher indicizzano
# l'artwork per pacchetto+versione).
#
# La variante si sceglie nella pagina (`var variant = ... || 'lockup'`): via
# file:// non si può contare sulla query string.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$page = Join-Path $PSScriptRoot 'tv_banner.html'
$res = Join-Path $root 'android\app\src\main\res'
$work = Join-Path $env:TEMP ('tv_banner_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$big = Join-Path $work 'tv_banner_640.png'
New-Item -ItemType Directory -Path $work | Out-Null

$edge = @(
  (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
  (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw "msedge.exe non trovato: serve per rasterizzare $page" }

try {
  # NB: si passa da Start-Process e NON da `& $edge ... 2>&1`. In PowerShell 5.1
  # redirigere lo stderr di un eseguibile nativo incapsula ogni riga in un
  # ErrorRecord (NativeCommandError): con $ErrorActionPreference='Stop' lo
  # script muore anche quando Edge ha funzionato benissimo — e Edge scrive
  # proprio su stderr il suo "bytes written to file".
  Start-Process -FilePath $edge -NoNewWindow -Wait -ArgumentList @(
    '--headless=new', '--disable-gpu', '--hide-scrollbars',
    '--window-size=640,360', "--screenshot=$big", "--user-data-dir=$work\profile",
    ('file:///' + $page.Replace('\', '/'))
  ) -RedirectStandardError (Join-Path $work 'edge.log')
  if (-not (Test-Path $big)) { throw "Edge non ha prodotto $big" }

  $src = [System.Drawing.Image]::FromFile($big)
  try {
    foreach ($t in @(@(640, 360, 'xxxhdpi'), @(480, 270, 'xxhdpi'), @(320, 180, 'xhdpi'))) {
      $dir = Join-Path $res ('drawable-' + $t[2])
      if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
      $bmp = New-Object System.Drawing.Bitmap($t[0], $t[1])
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      $g.InterpolationMode = 'HighQualityBicubic'
      $g.PixelOffsetMode = 'HighQuality'
      $g.SmoothingMode = 'HighQuality'
      $g.DrawImage($src, 0, 0, $t[0], $t[1])
      $g.Dispose()
      $bmp.Save((Join-Path $dir 'tv_banner.png'), [System.Drawing.Imaging.ImageFormat]::Png)
      $bmp.Dispose()
      Write-Host ('scritto drawable-{0}/tv_banner.png  {1}x{2}' -f $t[2], $t[0], $t[1])
    }
  }
  finally { $src.Dispose() }
}
finally { Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue }

Write-Host ''
Write-Host "Verifica dentro l'APK compilata:"
Write-Host '  aapt2 dump badging app-release.apk | grep leanback'
Write-Host "deve mostrare  leanback-launchable-activity: ... banner='res/....png'"
