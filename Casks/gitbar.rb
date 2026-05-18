cask "gitbar" do
  version "0.2.4"
  sha256 "e25ef1fd30640df73fceccf7b9dfbbb65c73e6030d1ddb632acec388f2b9ac22"

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
