# Script to package and publish Helm chart to GitHub Pages
param (
    [Parameter(Mandatory=$true, HelpMessage="Version number for the release (e.g. 2.5.68)")]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$releaseVersion,
    
    [Parameter(Mandatory=$true, HelpMessage="GitHub token with repository access")]
    [ValidateNotNullOrEmpty()]
    [string]$token
)

# Exit on any error
$ErrorActionPreference = 'Stop'

try {
    # Store the current branch to return to it at the end
    $currentBranch = git rev-parse --abbrev-ref HEAD

    # Clean up deploy directory
    if (Test-Path .\.deploy) {
        Remove-Item .\.deploy\* -Force
    } else {
        New-Item -ItemType Directory -Path .\.deploy
    }

    # Package the Helm chart
    Write-Host "Packaging Helm chart..." -ForegroundColor Cyan
    helm package .\charts\profit-trailer\ --destination .deploy
    if ($LASTEXITCODE -ne 0) { throw "Failed to package Helm chart" }

    # Upload chart to GitHub
    Write-Host "Uploading chart to GitHub..." -ForegroundColor Cyan
    cr upload -o connde -r profit-trailer -p .\.deploy\ --token $token
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
    git commit -m "release $releaseVersion"
    git push origin gh-pages
    if ($LASTEXITCODE -ne 0) { throw "Failed to push changes to gh-pages" }
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}
finally {
    # Always try to return to the original branch
    if ($currentBranch) {
        Write-Host "Returning to original branch..." -ForegroundColor Cyan
        git checkout $currentBranch
    }
}

Write-Host "Chart successfully published for version $releaseVersion" -ForegroundColor Green