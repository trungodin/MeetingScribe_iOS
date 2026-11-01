<#
    Cai / cap nhat app MeetingScribe len iPhone that (Windows).
    Cong thuc lai theo Huong-dan-cai-dat-xtool-Windows (PHAN 2):
      - xtool trong WSL lo build + ky  -> file .ipa
      - pymobiledevice3 tren Windows lo cai qua driver Apple (KHONG dung usbipd
        cho khau cai, vi usbipd lam hong viec truyen file lon tren may nay).

    Cach dung:
      powershell -ExecutionPolicy Bypass -File d:\MeetingScribe_iOS\tools\cai-iphone.ps1
      powershell -ExecutionPolicy Bypass -File d:\MeetingScribe_iOS\tools\cai-iphone.ps1 -Build
      powershell -ExecutionPolicy Bypass -File d:\MeetingScribe_iOS\tools\cai-iphone.ps1 -Ipa "C:\duong\dan\app.ipa"
#>
[CmdletBinding()]
param(
    # Build + ky lai IPA tu source hien tai truoc khi cai
    [switch]$Build,
    # Duong dan file .ipa (mac dinh: lay file moi nhat trong xtool\ hoac Downloads)
    [string]$Ipa
)

$ErrorActionPreference = 'Stop'
$env:PYTHONWARNINGS = 'ignore'      # an canh bao urllib3/chardet cua pymobiledevice3

# xtool tu them tien to "XTL-<TEAMID>." khi ky bang tai khoan mien phi, nen tren may
# bundle ID thuc te la: XTL-NTZRS3A969.com.example.meetingscribe
$bundleSuffix = 'com.example.meetingscribe'
$repoIpa   = 'd:\MeetingScribe_iOS\xtool\MeetingScribe.ipa'
$windowsIpa = Join-Path $env:USERPROFILE 'Downloads\MeetingScribe-signed.ipa'

function Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[!]  $m" -ForegroundColor Yellow }

# ---------------------------------------------------------------- 1. build + ky
if ($Build) {
    Step 'Build + ky IPA bang xtool trong WSL (khong can cam iPhone)...'
    wsl -d Ubuntu -e bash -lc 'cd /mnt/d/MeetingScribe_iOS && xtool dev build --sign --ipa'
    if ($LASTEXITCODE -ne 0) { Warn "Build/ky that bai (exit $LASTEXITCODE)."; exit $LASTEXITCODE }
    if (-not (Test-Path -LiteralPath $repoIpa)) { Warn "Khong thay $repoIpa"; exit 1 }
    Copy-Item -LiteralPath $repoIpa -Destination $windowsIpa -Force
    Ok "Da ky va chep ra: $windowsIpa"
}

# ---------------------------------------------------------------- 2. chon .ipa
if (-not $Ipa) {
    $cands = @($repoIpa, $windowsIpa) | Where-Object { Test-Path -LiteralPath $_ }
    if (-not $cands) {
        Warn 'Khong tim thay file .ipa. Chay lai voi -Build, hoac:'
        Write-Host '    wsl -d Ubuntu -e bash -lc "cd /mnt/d/MeetingScribe_iOS && xtool dev build --sign --ipa"'
        exit 1
    }
    $Ipa = $cands | Sort-Object { (Get-Item -LiteralPath $_).LastWriteTime } -Descending | Select-Object -First 1
}
if (-not (Test-Path -LiteralPath $Ipa)) { Warn "Khong thay file: $Ipa"; exit 1 }

$ipaItem = Get-Item -LiteralPath $Ipa
Step ("IPA: {0}  ({1:N0} KB, {2:dd/MM/yyyy HH:mm})" -f $ipaItem.FullName, ($ipaItem.Length / 1KB), $ipaItem.LastWriteTime)

# ---------------------------------------------------------------- 3. kiem tra cong cu
if (-not (Get-Command pymobiledevice3 -ErrorAction SilentlyContinue)) {
    Warn 'Chua co pymobiledevice3. Cai bang:  python -m pip install pymobiledevice3'
    exit 1
}

# ---------------------------------------------------------------- 4. tim iPhone
Step 'Tim iPhone qua usbmux...'
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'   # pymobiledevice3 ghi log ra stderr -> khong duoc de no nem loi
$list = & pymobiledevice3 usbmux list 2>&1 | Out-String
$ErrorActionPreference = $prevEap
$listText = $list.Trim()
if (-not $listText -or $listText -eq '[]') {
    Warn 'Chua thay iPhone nao.'
    Write-Host @'
Lam theo thu tu nay roi chay lai:
 1. Cam cap USB truc tiep vao may (tranh hub), mo khoa iPhone.
 2. Neu iPhone hien "Tin cay may tinh nay?" -> bam "Tin cay" + nhap mat khau.
 3. Neu truoc do da attach qua usbipd (driver WinUSB), phai tra driver Apple lai:
      mo PowerShell (Admin) -> usbipd list  -> lay BUSID cua dong Apple
      usbipd detach --busid <BUSID>
      usbipd unbind --busid <BUSID>
 4. Chay lai script nay.
'@
    exit 1
}
Ok 'Da thay iPhone.'

# ---------------------------------------------------------------- 5. cai
Step 'Dang cai app len iPhone (giu nguyen du lieu cu trong app)...'
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$log = & pymobiledevice3 apps install $Ipa 2>&1 | Out-String
$code = $LASTEXITCODE
$ErrorActionPreference = $prevEap

if ($log -notmatch 'Installation succeed|InstallComplete') {
    $log.Trim() -split "`n" | Select-Object -Last 12
    Warn "Cai that bai (exit $code). Xem thong bao phia tren."
    exit 1
}
Ok 'Thiet bi bao: Installation succeed.'

# ---------------------------------------------------------------- 6. xac minh
Step 'Xac minh app da co tren may...'
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$apps = & pymobiledevice3 apps list 2>&1 | Out-String
$ErrorActionPreference = $prevEap

$idLine = ($apps -split "`n") | Select-String -Pattern $bundleSuffix -SimpleMatch | Select-Object -First 1
if ($idLine) {
    Ok ('Bundle da cai: ' + $idLine.Line.Trim().TrimEnd(':', '{'))
} else {
    Warn 'Cai xong nhung khong thay trong danh sach app - thu mo app tren iPhone.'
}
Write-Host 'Mo app "MeetingScribe VN" tren man hinh chinh de kiem tra.'
