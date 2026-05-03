# Shows how much disk Docker is using and (with confirmation) prunes everything safely.
# Run before any lab session and before bed.

$ErrorActionPreference = "Continue"

Write-Host "==> Free space on system drive:" -ForegroundColor Cyan
Get-PSDrive -PSProvider FileSystem |
  Where-Object { $_.Name -eq 'C' } |
  Select-Object Name,
                @{n='UsedGB';e={[math]::Round(($_.Used/1GB),1)}},
                @{n='FreeGB';e={[math]::Round(($_.Free/1GB),1)}}

Write-Host "`n==> Docker disk usage:" -ForegroundColor Cyan
docker system df

Write-Host "`n==> kind clusters:" -ForegroundColor Cyan
kind get clusters 2>$null

Write-Host "`n==> k3d clusters:" -ForegroundColor Cyan
k3d cluster list 2>$null

Write-Host "`nReclaim options:"
Write-Host "  1) Light prune  - removes stopped containers + dangling images (safe)"
Write-Host "  2) Heavy prune  - also removes unused images + build cache (recovers most space)"
Write-Host "  3) Skip"
$choice = Read-Host "Choose [1/2/3]"

switch ($choice) {
    '1' {
        docker container prune -f
        docker image prune -f
        docker volume prune -f
    }
    '2' {
        docker container prune -f
        docker image prune -a -f
        docker volume prune -f
        docker builder prune -a -f
    }
    default { Write-Host "Skipped." }
}

Write-Host "`n==> After cleanup:" -ForegroundColor Cyan
docker system df
