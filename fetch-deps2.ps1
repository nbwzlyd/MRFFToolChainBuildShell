$ErrorActionPreference = 'Continue'
$base = 'https://github.com/debugly/MRFFToolChainBuildShell/releases/download'
$dl   = 'D:\dev\fsplayer\FFToolChain\build\_zips'
$dest = 'D:\dev\fsplayer\FFToolChain\build\product\android\universal'
New-Item -ItemType Directory -Force -Path $dl, $dest | Out-Null

$items = @(
    @{ t = 'ffmpeg8-8.1.2-261007120544';  z = 'ffmpeg8-android-universal-8.1.2.zip';   exp = 70664200 },
    @{ t = 'openssl3-3.6.4-260826085332'; z = 'openssl3-android-universal-3.6.4.zip'; exp = 15792035 }
)

foreach ($i in $items) {
    $out = Join-Path $dl $i.z
    for ($try = 1; $try -le 10; $try++) {
        $cur = if (Test-Path $out) { (Get-Item $out).Length } else { 0 }
        if ($cur -ge $i.exp) { break }
        Write-Output "[get $try] $($i.z) have=$cur / $($i.exp)"
        curl.exe -L --ssl-no-revoke -C - --retry 2 --retry-delay 2 --max-time 900 -s -o $out "$base/$($i.t)/$($i.z)"
        $after = if (Test-Path $out) { (Get-Item $out).Length } else { 0 }
        if ($after -le $cur) { Write-Output "[stall] $($i.z) no progress ($after)"; Start-Sleep -Seconds 3 }
    }
    $final = if (Test-Path $out) { (Get-Item $out).Length } else { 0 }
    Write-Output "[done] $($i.z) size=$final expected=$($i.exp)"
    if ($final -eq $i.exp) {
        tar.exe -xf $out -C $dest
        Write-Output "[extract] $($i.z) exit=$LASTEXITCODE"
    }
    else {
        Write-Output "[BADSIZE] $($i.z)"
    }
}

Write-Output '=== top-level dirs ==='
Get-ChildItem $dest | ForEach-Object { $_.Name }
Write-Output '=== ffmpeg / openssl structure ==='
Get-ChildItem $dest -Directory | Where-Object { $_.Name -match 'ffmpeg|openssl' } | ForEach-Object {
    $sub = (Get-ChildItem $_.FullName | ForEach-Object { $_.Name }) -join ', '
    Write-Output "$($_.Name): $sub"
}
Write-Output '=== DONE ==='
