class Gitbar < Formula
  desc "Native macOS menu bar app for tracking GitHub PRs and issues"
  homepage "https://github.com/brunokiafuka/gitbar"
  url "https://github.com/brunokiafuka/gitbar/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "34f3d4e0cbaffe325978fe0bf8903b10679e273b1403a439f310df31c4aae41f"
  head "https://github.com/brunokiafuka/gitbar.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on :macos

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"

    app = prefix/"Gitbar.app"
    (app/"Contents/MacOS").mkpath
    (app/"Contents/Resources").mkpath

    cp ".build/release/gitbar", app/"Contents/MacOS/Gitbar"

    iconset = buildpath/"AppIcon.iconset"
    iconset.mkpath
    {
      "icon_16x16.png"      => 16,
      "icon_16x16@2x.png"   => 32,
      "icon_32x32.png"      => 32,
      "icon_32x32@2x.png"   => 64,
      "icon_128x128.png"    => 128,
      "icon_128x128@2x.png" => 256,
      "icon_256x256.png"    => 256,
      "icon_256x256@2x.png" => 512,
      "icon_512x512.png"    => 512,
      "icon_512x512@2x.png" => 1024,
    }.each do |name, size|
      system "sips", "-z", size.to_s, size.to_s,
             "Resources/AppIcon.png", "--out", iconset/name
    end
    system "iconutil", "-c", "icns", iconset,
           "-o", app/"Contents/Resources/AppIcon.icns"

    (app/"Contents/Info.plist").write <<~PLIST
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
          <key>CFBundleName</key><string>Gitbar</string>
          <key>CFBundleDisplayName</key><string>Gitbar</string>
          <key>CFBundleIdentifier</key><string>com.brunokiafuka.gitbar</string>
          <key>CFBundleVersion</key><string>#{version}</string>
          <key>CFBundleShortVersionString</key><string>#{version}</string>
          <key>CFBundleExecutable</key><string>Gitbar</string>
          <key>CFBundlePackageType</key><string>APPL</string>
          <key>LSMinimumSystemVersion</key><string>14.0</string>
          <key>LSUIElement</key><true/>
          <key>NSHighResolutionCapable</key><true/>
          <key>CFBundleIconFile</key><string>AppIcon</string>
      </dict>
      </plist>
    PLIST

    (bin/"gitbar").write <<~SH
      #!/usr/bin/env bash
      exec open "#{opt_prefix}/Gitbar.app" "$@"
    SH
    chmod 0755, bin/"gitbar"
  end

  def caveats
    <<~EOS
      Gitbar.app is installed at:
        #{opt_prefix}/Gitbar.app

      Launch it with:
        gitbar
      or symlink into /Applications:
        ln -sf "#{opt_prefix}/Gitbar.app" /Applications/Gitbar.app

      On first launch, open Settings from the menu bar icon and paste a GitHub
      Personal Access Token (classic ghp_… or fine-grained github_pat_…).
    EOS
  end

  test do
    assert_path_exists prefix/"Gitbar.app/Contents/MacOS/Gitbar"
    assert_path_exists prefix/"Gitbar.app/Contents/Info.plist"
  end
end
