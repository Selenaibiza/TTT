$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$B   = "C:\Users\ComCell\AppData\Local\Temp\opencode\ttt-apk"
$SRC = "$B\src"
$OUT = "$B\out"

$ANDROID_JAR = "$B\dl\android-all.jar"          # framework (classes + resources.arsc)
$AAPT2       = "$B\tools\aapt2\aapt2.exe"
$R8          = "$B\tools\r8.jar"                # contains D8
$APKSIG      = "$B\tools\apksig.jar"            # contains ApkSigner
$KEYSTORE    = "$B\debug.keystore"

function Step($t) { Write-Host ""; Write-Host "==> $t" -ForegroundColor Cyan }

# ---------------------------------------------------------------- JDK
Step "Locating JDK"
$jdkRoot = Get-ChildItem "$B\jdk" -Directory -ErrorAction SilentlyContinue |
           Where-Object { Test-Path (Join-Path $_.FullName 'bin\javac.exe') } |
           Select-Object -First 1

if (-not $jdkRoot) {
    Write-Host "    extracting jdk17.zip ..."
    if (Test-Path "$B\jdk") { Remove-Item "$B\jdk" -Recurse -Force }
    New-Item -ItemType Directory -Force -Path "$B\jdk" | Out-Null
    [IO.Compression.ZipFile]::ExtractToDirectory("$B\dl\jdk17.zip", "$B\jdk")
    $jdkRoot = Get-ChildItem "$B\jdk" -Directory |
               Where-Object { Test-Path (Join-Path $_.FullName 'bin\javac.exe') } |
               Select-Object -First 1
}
if (-not $jdkRoot) { throw "JDK not found" }

$JDK    = $jdkRoot.FullName
$JAVA   = Join-Path $JDK 'bin\java.exe'
$JAVAC  = Join-Path $JDK 'bin\javac.exe'
$KEYTOOL= Join-Path $JDK 'bin\keytool.exe'
Write-Host "    JDK = $JDK"

# ---------------------------------------------------------------- clean
Step "Preparing output folders"
if (Test-Path $OUT) { Remove-Item $OUT -Recurse -Force }
foreach ($d in @("classes","dex","gen","signer")) {
    New-Item -ItemType Directory -Force -Path "$OUT\$d" | Out-Null
}

# ---------------------------------------------------------------- 1) javac
Step "Compiling Java sources"
$javaFiles = Get-ChildItem "$SRC\java" -Recurse -Filter *.java | ForEach-Object { $_.FullName }
& $JAVAC -encoding UTF-8 -source 8 -target 8 -nowarn -cp $ANDROID_JAR -d "$OUT\classes" $javaFiles
if ($LASTEXITCODE -ne 0) { throw "javac failed" }
Write-Host "    ok"

# ---------------------------------------------------------------- 2) d8
Step "Dexing with D8"
$classFiles = Get-ChildItem "$OUT\classes" -Recurse -Filter *.class | ForEach-Object { $_.FullName }
& $JAVA -cp $R8 com.android.tools.r8.D8 --min-api 21 --lib $ANDROID_JAR --output "$OUT\dex" $classFiles
if ($LASTEXITCODE -ne 0) { throw "d8 failed" }
Get-ChildItem "$OUT\dex" | ForEach-Object { Write-Host "    $($_.Name)  $($_.Length) bytes" }

# ---------------------------------------------------------------- 3) aapt2
Step "Compiling resources (aapt2 compile)"
& $AAPT2 compile --dir "$SRC\res" -o "$OUT\res.zip"
if ($LASTEXITCODE -ne 0) { throw "aapt2 compile failed" }

Step "Linking resources + assets (aapt2 link)"
& $AAPT2 link -o "$OUT\base.apk" `
    -I $ANDROID_JAR `
    --manifest "$SRC\AndroidManifest.xml" `
    "$OUT\res.zip" `
    -A "$SRC\assets" `
    --java "$OUT\gen" `
    --min-sdk-version 21 `
    --target-sdk-version 34 `
    --version-code 1 `
    --version-name 1.0
if ($LASTEXITCODE -ne 0) { throw "aapt2 link failed" }
Write-Host "    base.apk  $([math]::Round((Get-Item "$OUT\base.apk").Length/1KB,1)) KB"

# ---------------------------------------------------------------- 4) package + zipalign
Step "Packing classes.dex + zipalign"
& node "$B\tools\zipalign.js" "$OUT\base.apk" "$OUT\unsigned.apk" "classes.dex=$OUT\dex\classes.dex"
if ($LASTEXITCODE -ne 0) { throw "packaging/zipalign failed" }

# ---------------------------------------------------------------- 5) keystore
Step "Creating debug keystore"
if (-not (Test-Path $KEYSTORE)) {
    & $KEYTOOL -genkeypair -v `
        -keystore $KEYSTORE -storetype PKCS12 `
        -storepass android -keypass android `
        -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 `
        -dname "CN=Android Debug,O=Android,C=US"
    if ($LASTEXITCODE -ne 0) { throw "keytool failed" }
} else {
    Write-Host "    reusing existing keystore"
}

# ---------------------------------------------------------------- 6) sign
Step "Signing APK (apksig)"
& $JAVAC -encoding UTF-8 -nowarn -cp $APKSIG -d "$OUT\signer" "$B\tools\Sign.java"
if ($LASTEXITCODE -ne 0) { throw "Sign.java compile failed" }

& $JAVA -cp "$APKSIG;$OUT\signer" Sign `
    "$OUT\unsigned.apk" "$OUT\tictactoe.apk" $KEYSTORE android androiddebugkey
if ($LASTEXITCODE -ne 0) { throw "signing failed" }

Write-Host ""
Write-Host "BUILD COMPLETE -> $OUT\tictactoe.apk" -ForegroundColor Green
