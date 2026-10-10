$ErrorActionPreference = 'Continue'
$base = 'https://github.com/debugly/MRFFToolChainBuildShell/releases/download'
$dest = 'D:\dev\fsplayer\FFToolChain\build\product\android\universal'
$dl   = 'D:\dev\fsplayer\FFToolChain\build\_zips'
New-Item -ItemType Directory -Force -Path $dest, $dl | Out-Null

$libs = @(
    @{ t = 'ffmpeg8-8.1.2-261007120544';    z = 'ffmpeg-android-universal-8.1.2.zip' },
    @{ t = 'openssl3-3.6.4-260826085332';   z = 'openssl-android-universal-3.6.4.zip' },
    @{ t = 'opus-1.6.1-260824190450';       z = 'opus-android-universal-1.6.1.zip' },
    @{ t = 'bluray-1.5.0-260827104804';     z = 'bluray-android-universal-1.5.0.zip' },
    @{ t = 'dav1d-1.5.4-260824210640';      z = 'dav1d-android-universal-1.5.4.zip' },
    @{ t = 'uavs3d-1.2.1-260824211246';     z = 'uavs3d-android-universal-1.2.1.zip' },
    @{ t = 'smb2-6.2-260228143900';         z = 'smb2-android-universal-6.2.zip' },
    @{ t = 'soundtouch-2.4.1-260824190319'; z = 'soundtouch-android-universal-2.4.1.zip' },
    @{ t = 'xml2-2.15.3-260827104329';      z = 'xml2-android-universal-2.15.3.zip' },
    @{ t = 'freetype-2.14.3-260824184117';  z = 'freetype-android-universal-2.14.3.zip' },
    @{ t = 'fribidi-1.0.16-260824184014';   z = 'fribidi-android-universal-1.0.16.zip' },
    @{ t = 'harfbuzz-14.3.1-260824184504';  z = 'harfbuzz-android-universal-14.3.1.zip' },
    @{ t = 'unibreak-7.0-260824183653';     z = 'unibreak-android-universal-7.0.zip' },
    @{ t = 'fontconfig-2.18.3-260827104627'; z = 'fontconfig-android-universal-2.18.3.zip' },
    @{ t = 'ass-0.17.5-260827105429';       z = 'ass-android-universal-0.17.5.zip' }
)

foreach ($l in $libs) {
    $zip = Join-Path $dl $l.z
    if ((Test-Path $zip) -and (Get-Item $zip).Length -gt 1024) {
        Write-Output "[skip] $($l.z)"
    }
    else {
        Write-Output "[get ] $($l.z)"
        curl.exe -L --ssl-no-revoke --retry 3 --retry-delay 3 -s -o $zip "$base/$($l.t)/$($l.z)"
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $zip)) {
            Write-Output "[FAIL] $($l.z) exit=$LASTEXITCODE"
            continue
        }
    }
    $mb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
    Write-Output "[ok  ] $($l.z) ${mb}MB extracting"
    tar.exe -xf $zip -C $dest
    if ($LASTEXITCODE -ne 0) { Write-Output "[XFAIL] extract $($l.z)" }
}

Write-Output '=== extracted top-level dirs ==='
Get-ChildItem $dest | ForEach-Object { $_.Name }
Write-Output '=== ffmpeg products ==='
Get-ChildItem (Join-Path $dest 'ffmpeg') -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }
Write-Output '=== DONE ==='
