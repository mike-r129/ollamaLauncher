$RepoRoot = Split-Path -Parent $PSScriptRoot
$PathsModule = Join-Path $RepoRoot 'src/OllamaLauncher/Paths.psm1'

Import-Module $PathsModule -Force

Describe 'Paths.psm1' {
    It 'resolves the portable app root from the module location' {
        Get-OllamaLauncherAppRoot | Should Be $RepoRoot
    }

    It 'keeps user config under AppData and generated files under LocalAppData cache' {
        $configPath = Get-OllamaLauncherConfigPath 'repos.json'
        $cachePath = Get-OllamaLauncherCachePath 'models.txt'

        $configPath | Should Match 'ollamaLauncher\\repos\.json$'
        $cachePath | Should Match 'ollamaLauncher\\Cache\\models\.txt$'
    }

    It 'points default repo config at the checked-in config artifact' {
        $defaultConfig = Get-OllamaLauncherDefaultReposPath

        $defaultConfig | Should Be (Join-Path $RepoRoot 'config\repos.default.json')
        (Test-Path -LiteralPath $defaultConfig) | Should Be $true
    }
}
