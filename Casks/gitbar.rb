cask "gitbar" do
  version "0.2.5"
  sha256 "bb6d12dd7151b9270af4506e2f40281afd0b6b61e4eb34aec6a20db32c7db580"

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
