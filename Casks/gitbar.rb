cask "gitbar" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/brunokiafuka/gitbar/releases/download/v#{version}/Gitbar-#{version}.app.zip"
  name "Gitbar"
  desc "Menu bar app for tracking GitHub PRs and issues"
  homepage "https://github.com/brunokiafuka/gitbar"

  depends_on macos: :sonoma

  app "Gitbar.app"

  zap trash: [
    "~/.gitbar",
    "~/Library/Preferences/com.brunokiafuka.gitbar.plist",
  ]
end
