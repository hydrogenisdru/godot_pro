extends RefCounted

static func create() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Hiragino Sans GB", "PingFang SC", "Noto Sans CJK SC", "Microsoft YaHei", "Heiti SC"])
	font.fallbacks = [ThemeDB.fallback_font]
	if OS.get_name() == "macOS":
		var path := "/System/Library/Fonts/Hiragino Sans GB.ttc"
		var data := FontFile.new()
		if data.load_dynamic_font(path) == OK:
			return data
	return font
