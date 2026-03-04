@{
  Label = "googlechrome"
  Title = "Google Chrome"

  # Enables Chrome-specific fallback behavior in the runner
  AppId = "chrome"

  # Match the registry display name
  DisplayNameRegex = "Google Chrome"

  ProcessesToStop = @(
    "chrome",
    "googleupdate",
    "googleupdatem"
  )

  ServicesToStop = @(
    "gupdate",
    "gupdatem"
  )

  # System leftovers (keep conservative)
  RemovePaths = @(
    "C:\\Program Files\\Google\\Chrome\\",
    "C:\\Program Files (x86)\\Google\\Chrome\\",
    "C:\\ProgramData\\Google\\Chrome\\"
  )

  # User data (only removed when runner is called with -RemoveUserData)
  PerUserPaths = @(
    "AppData\\Local\\Google\\Chrome\\",
    "AppData\\Roaming\\Google\\Chrome\\"
  )

  # Optional EXE silent args (leave empty by default)
  # ExeSilentArgs = "/S"
}
