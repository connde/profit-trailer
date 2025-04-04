param(
    [Parameter(Mandatory=$true, HelpMessage="Version number for the release (e.g. 2.5.68)")]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,
    
    [Parameter(Mandatory=$true, HelpMessage="GitHub token with repository access")]
    [ValidateNotNullOrEmpty()]
    [string]$GithubToken
)

$ErrorActionPreference = 'Stop'

function Update-ChartYaml {
    param(
        [string]$AppVersion,
        [string]$ChartVersion
    )
    
    $chartFile = "charts/profit-trailer/Chart.yaml"
    $chartContent = Get-Content $chartFile
    
    # Update version and appVersion
    $updatedContent = $chartContent | ForEach-Object {
        if ($_ -match '^version:') {
            "version: $ChartVersion"
        }
        elseif ($_ -match '^appVersion:') {
            "appVersion: $AppVersion"
        }
        else {
            $_
        }
    }
    
    Set-Content -Path $chartFile -Value $updatedContent
}

try {
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

    # Get current chart version and increment minor version
    $chartFile = "charts/profit-trailer/Chart.yaml"
    $chartContent = Get-Content $chartFile
    $currentChartVersion = ($chartContent | Select-String -Pattern '^version: (.+)$').Matches.Groups[1].Value
    $versionParts = $currentChartVersion.Split('.')
    $versionParts[1] = [int]$versionParts[1] + 1
    $versionParts[2] = 0  # Reset patch version when incrementing minor version
    $newChartVersion = $versionParts -join '.'

    # Update Chart.yaml with new versions
    Update-ChartYaml -AppVersion $Version -ChartVersion $newChartVersion

    # Package and publish Helm chart first
    Write-Host "Packaging Helm chart..." -ForegroundColor Cyan
    
    # Clean up deploy directory
    if (Test-Path .\.deploy) {
        Remove-Item .\.deploy\* -Force
    } else {
        New-Item -ItemType Directory -Path .\.deploy
    }

    # Package the Helm chart
    helm package .\charts\profit-trailer\ --destination .deploy
    if ($LASTEXITCODE -ne 0) { throw "Failed to package Helm chart" }

    # Upload chart to GitHub with skip-existing flag
    Write-Host "Uploading chart to GitHub..." -ForegroundColor Cyan
    cr upload -o connde -r profit-trailer -p .\.deploy\ --token $GithubToken --skip-existing
    if ($LASTEXITCODE -ne 0) { throw "Failed to upload chart" }

    # Switch to gh-pages branch and update index
    Write-Host "Updating chart repository index..." -ForegroundColor Cyan
    git checkout gh-pages
    if ($LASTEXITCODE -ne 0) { throw "Failed to checkout gh-pages branch" }

    cr index -i .\index.yaml -p .deploy -o connde -r profit-trailer -c https://github.com/connde/profit-trailer/charts
    if ($LASTEXITCODE -ne 0) { throw "Failed to update chart index" }

    # Commit and push changes to gh-pages
    Write-Host "Publishing changes..." -ForegroundColor Cyan
    git add .\index.yaml
    git commit -m "release $Version"
    git push origin gh-pages
    if ($LASTEXITCODE -ne 0) { throw "Failed to push changes to gh-pages" }

    # Return to feature branch
    git checkout $featureBranch

    # Now commit and push version changes
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

    # Create GitHub release
    Write-Host "Creating GitHub release..." -ForegroundColor Cyan
    gh release create $Version --title "Release $Version" --target main --notes "Release $Version" --latest

    Write-Host "Version $Version has been successfully deployed!" -ForegroundColor Green
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}
finally {
    # Return to develop branch
    git checkout develop
    
    # Clean up .deploy folder
    if (Test-Path .\.deploy) {
        Write-Host "Cleaning up .deploy folder..." -ForegroundColor Cyan
        Remove-Item .\.deploy -Recurse -Force
    }
}
