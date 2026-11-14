extends RefCounted

const BASE := "user://trials.csv"
const SAVE := "user://tuning.cfg"

static func append_trial(row: Array) -> Error:
	var new_file := not FileAccess.file_exists(BASE)
	var file := FileAccess.open(BASE, FileAccess.WRITE if new_file else FileAccess.READ_WRITE)
	if file == null:
		return FileAccess.get_open_error()
	if new_file:
		file.store_string("\ufeff")
		file.store_csv_line(PackedStringArray([
			"时间", "实验", "动作方案", "武器", "结果", "试验秒数", "玩家位移px",
			"跳跃", "翻滚", "缓冲触发", "攻击", "命中", "受击", "滚动避伤", "脱离攻击范围",
			"敌人出招", "前摇出手", "后摇出手", "反击命中", "打断", "平均命中距离px",
			"音效", "命中停顿", "屏幕震动", "手感/满足感备注", "动作参数JSON", "敌人参数JSON", "武器参数JSON"
		]))
	file.seek_end()
	var columns := PackedStringArray()
	for value in row:
		columns.append(str(value))
	file.store_csv_line(columns)
	file.flush()
	return file.get_error()
