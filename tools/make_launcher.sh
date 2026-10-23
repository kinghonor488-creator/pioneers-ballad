#!/bin/bash
# 生成一个可以双击启动游戏的「拓荒者之歌.app」，放在项目文件夹里。
# 它会直接用 Godot 运行游戏（不打开编辑器）。项目文件夹挪到别处也能用，只要 .app 和 project.godot 在同一个文件夹。
# 用法：bash tools/make_launcher.sh
set -e
DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="$DIR/拓荒者之歌.app"
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/launcher.applescript" <<'AS'
on run
	set appPath to POSIX path of (path to me)
	set projDir to do shell script "dirname " & quoted form of appPath
	set godotBin to "/Applications/Godot.app/Contents/MacOS/Godot"
	try
		do shell script "test -x " & quoted form of godotBin
	on error
		display dialog "没有找到 Godot。请先在终端里运行：brew install --cask godot" buttons {"好"} default button 1 with title "拓荒者之歌"
		return
	end try
	do shell script quoted form of godotBin & " --path " & quoted form of projDir & " > /dev/null 2>&1 &"
end run
AS

rm -rf "$APP"
osacompile -o "$APP" "$TMP/launcher.applescript"

# 图标：icon.svg → 各种尺寸的 PNG → .icns
"$GODOT" --headless --path "$DIR" -s res://tools/export_icon.gd -- "$TMP/icon_1024.png" > /dev/null 2>&1
mkdir "$TMP/icon.iconset"
for s in 16 32 128 256 512; do
	sips -z $s $s "$TMP/icon_1024.png" --out "$TMP/icon.iconset/icon_${s}x${s}.png" > /dev/null
	sips -z $((s * 2)) $((s * 2)) "$TMP/icon_1024.png" --out "$TMP/icon.iconset/icon_${s}x${s}@2x.png" > /dev/null
done
iconutil -c icns "$TMP/icon.iconset" -o "$APP/Contents/Resources/applet.icns"
# 新版 macOS 会优先用 Assets.car 里的默认脚本图标，去掉它才会显示我们的图标
rm -f "$APP/Contents/Resources/Assets.car"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$APP/Contents/Info.plist" 2> /dev/null || true
xattr -cr "$APP" 2> /dev/null || true
codesign --force --deep --sign - "$APP" > /dev/null 2>&1 || true
touch "$APP"
echo "已生成：$APP"
