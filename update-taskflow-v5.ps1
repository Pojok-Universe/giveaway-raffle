$ErrorActionPreference = "Stop"

# v5: kolom paste-link + tombol Verify Post pada task reply
# baru muncul SETELAH user klik "Open" ke postingan target.
# (Mirip pola "I've done this" di task follow/like.)

$Path = "app/c/[id]/page.js"
$content = [System.IO.File]::ReadAllText($Path)

$pattern = '(?s)(<p className="small" style=\{\{ marginBottom: 6 \}\}>.*?</button>\s*</div>)'
$replacement = '{(openedMap[r.id] || !r.url || done) ? (<>$1</>) : (<p className="small" style={{ marginTop: 8 }}>Click "Open" above and reply to that post first - the link field appears after that.</p>)}'

$new = $content -replace $pattern, $replacement
if ($new -eq $content) {
  Write-Host "SKIP: pola tidak ketemu (mungkin sudah di-patch)"
  exit 1
}
[System.IO.File]::WriteAllText($Path, $new, [System.Text.Encoding]::UTF8)
Write-Host "OK: app/c/[id]/page.js - paste-link reply digate di balik klik Open"
Write-Host ""
Write-Host 'Lanjut: git add -A; git commit -m "v5 reply gate"; git push'
