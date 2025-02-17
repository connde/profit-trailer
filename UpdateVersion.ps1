param(
    [Parameter(Mandatory=$true)]
    [string]$Version,
    [Parameter(Mandatory=$true)]
    [string]$GithubToken
)

# Start from develop branch and ensure it's up to date
git checkout develop
git pull origin develop

# Create and checkout new feature branch
$featureBranch = "feature/$Version"
git checkout -b $featureBranch

# Update version in files
$files = @(
    "charts/profit-trailer/values.yaml",
    "charts/questions.yaml",
    "Dockerfile"
)

foreach ($file in $files) {
    (Get-Content $file) | ForEach-Object {
        $_ -replace '(?<=version: )\d+\.\d+\.\d+', $Version
    } | Set-Content $file
}

# Increment chart version
$chartFile = "charts/profit-trailer/Chart.yaml"
$chartContent = Get-Content $chartFile -Raw
$chartVersion = [regex]::Match($chartContent, 'version: (\d+\.\d+\.\d+)').Groups[1].Value
$versionParts = $chartVersion.Split('.')
$versionParts[2] = [int]$versionParts[2] + 1
$newChartVersion = $versionParts -join '.'

(Get-Content $chartFile) | ForEach-Object {
    $_ -replace '(?<=version: )\d+\.\d+\.\d+', $newChartVersion
    $_ -replace '(?<=appVersion: )\d+\.\d+\.\d+', $Version
} | Set-Content $chartFile

# Commit and push changes
git add .
git commit -m "feat: Update to version $Version"
git push origin $featureBranch

# Create and merge PR to develop
gh pr create --base develop --head $featureBranch --title "feat: Update to version $Version" --body "Update to version $Version"
$prNumber = (gh pr list --head $featureBranch --json number --jq '.[0].number')
gh pr merge $prNumber --merge

# Switch to develop and update
git checkout develop
git pull origin develop

# Create and merge PR to main
gh pr create --base main --head develop --title "feat: Update to version $Version" --body "Update to version $Version"
$prNumber = (gh pr list --head develop --base main --json number --jq '.[0].number')
gh pr merge $prNumber --merge

# Switch to main and update
git checkout main
git pull origin main

# Update chart
.\UpdateChart.ps1 $Version $GithubToken

# Create release
gh release create $Version --title "Release $Version" --target main --notes "Release $Version" --latest

Write-Host "Version $Version has been successfully deployed!"
