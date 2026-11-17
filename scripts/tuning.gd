extends RefCounted

const MOVEMENT_A := {
	"speed": 302.0, "accel": 2550.0, "brake": 3060.0, "air_control": 0.73,
	"turn_brake": 3700.0, "air_drag": 520.0,
	"jump_height": 164.0, "buffer": 0.115, "roll_time": 0.31, "roll_speed": 550.0,
	"air_jump_height": 96.0,
	"iframe_start": 0.045, "iframe_end": 0.245,
}
const MOVEMENT_B := {
	"speed": 302.0, "accel": 1450.0, "brake": 1020.0, "air_control": 0.39,
	"turn_brake": 1150.0, "air_drag": 100.0,
	"jump_height": 148.0, "buffer": 0.05, "roll_time": 0.38, "roll_speed": 500.0,
	"air_jump_height": 96.0,
	"iframe_start": 0.045, "iframe_end": 0.245,
}
const ENEMY := {"speed": 118.0, "reach": 118.0, "windup": 0.57, "active": 0.12, "recovery": 0.57, "stagger": 0.28}
const THROW_BALL := {"fuse": 2.4}
const FEEDBACK := {
	"stop_time": 0.05,
	"flash_time": 0.10, "flash_strength": 0.85,
	"knockback_speed": 240.0, "knockback_brake": 660.0,
	"shake_strength": 4.0, "shake_time": 0.16, "shake_frequency": 30.0,
	"particle_count": 8, "particle_speed": 160.0, "particle_spread": 50.0, "particle_time": 0.22,
	"spark_size": 18.0, "spark_time": 0.07, "spark_strength": 1.0, "spark_color": Color("#fff0ad"),
	"slash_length": 1.0, "slash_width": 7.0, "slash_opacity": 0.85, "slash_time": 0.10,
	"number_size": 18, "number_rise": 24.0, "number_time": 0.45,
}
const FEEDBACK_SWITCHES := {
	"freeze": true, "flash": true, "knockback": true, "shake": true,
	"particles": true, "spark": true, "slash": true, "damage_number": true,
}
const FAST := {"reach": 67.0, "windup": 0.10, "active": 0.085, "recovery": 0.19, "move_factor": 0.73, "damage": 1.0, "interrupts": false}
const HEAVY := {"reach": 140.0, "windup": 0.33, "active": 0.13, "recovery": 0.40, "move_factor": 0.0, "damage": 2.0, "interrupts": true}
const M_FIELDS := [
	["accel", "地面加速度", 500, 6000, 50, "px/s²"],
	["brake", "地面松键减速", 100, 6500, 10, "px/s²"],
	["turn_brake", "反向制动", 200, 6500, 50, "px/s²"],
	["air_drag", "空中松键减速", 0, 3000, 10, "px/s²"],
	["speed", "移动速度", 150, 475, 5, "px/s"],
	["air_control", "空中控制", 0.10, 1.40, 0.01, "×"],
	["jump_height", "一段目标跳高", 65, 250, 1, "px"],
	["air_jump_height", "二段目标跳高", 40, 250, 1, "px"],
	["buffer", "输入缓冲", 0, 0.25, 0.005, "ms"],
	["roll_time", "翻滚时长", 0.14, 0.65, 0.01, "ms"],
	["roll_speed", "翻滚速度", 280, 850, 5, "px/s"],
	["iframe_start", "无敌开始", 0, 0.40, 0.005, "ms"],
	["iframe_end", "无敌结束", 0, 0.65, 0.005, "ms"],
]
const E_FIELDS := [
	["windup", "敌人前摇", 0.20, 1.20, 0.01, "ms"],
	["active", "敌人有效段", 0.05, 0.40, 0.01, "ms"],
	["recovery", "敌人后摇", 0.16, 1.10, 0.01, "ms"],
	["reach", "敌人攻击距离", 64, 175, 1, "px"],
	["speed", "追击速度", 45, 220, 1, "px/s"],
]
const W_FIELDS := [
	["windup", "武器前摇", 0.05, 0.70, 0.005, "ms"],
	["active", "武器有效段", 0.05, 0.40, 0.005, "ms"],
	["recovery", "武器后摇", 0.05, 0.75, 0.005, "ms"],
	["reach", "武器攻击距离", 36, 190, 1, "px"],
	["move_factor", "攻击时移动", 0, 1, 0.01, "×"],
	["damage", "单击伤害", 1, 6, 1, "HP"],
]
const THROW_FIELDS := [
	["fuse", "爆炸延时", 0.30, 6.0, 0.05, "ms"],
]
const FEEDBACK_FIELDS := [
	["freeze", "命中停顿", [
		["stop_time", "停顿时长", 0, 0.20, 0.005, "ms"],
	]],
	["flash", "受击闪白", [
		["flash_time", "闪白时长", 0.02, 0.35, 0.005, "ms"],
		["flash_strength", "峰值强度", 0, 1, 0.05, "%"],
	]],
	["knockback", "受击击退", [
		["knockback_speed", "横向冲量", 0, 620, 10, "px/s"],
		["knockback_brake", "衰减速度", 100, 3200, 20, "px/s²"],
	]],
	["shake", "屏幕震动", [
		["shake_strength", "峰值幅度", 0, 16, 0.5, "px"],
		["shake_time", "震动时长", 0.02, 0.40, 0.01, "ms"],
		["shake_frequency", "震动频率", 5, 60, 1, "Hz"],
	]],
	["particles", "受击粒子", [
		["particle_count", "粒子数量", 1, 30, 1, "个"],
		["particle_speed", "喷射速度", 20, 500, 5, "px/s"],
		["particle_spread", "散布角度", 5, 160, 5, "°"],
		["particle_time", "粒子寿命", 0.04, 0.60, 0.01, "ms"],
	]],
	["spark", "命中火花", [
		["spark_size", "火花尺寸", 4, 50, 1, "px"],
		["spark_time", "火花时长", 0.02, 0.30, 0.005, "ms"],
		["spark_strength", "火花亮度", 0, 1, 0.05, "%"],
		["spark_color", "火花颜色", 0, 0, 0, "color"],
	]],
	["slash", "挥砍残影", [
		["slash_length", "弧线长度", 0.25, 1.50, 0.05, "×"],
		["slash_width", "弧线宽度", 1, 20, 1, "px"],
		["slash_opacity", "弧线透明度", 0, 1, 0.05, "%"],
		["slash_time", "淡出时间", 0.02, 0.40, 0.005, "ms"],
	]],
	["damage_number", "伤害数字", [
		["number_size", "数字字号", 10, 32, 1, "px"],
		["number_rise", "上浮距离", 0, 80, 1, "px"],
		["number_time", "数字时长", 0.10, 0.90, 0.025, "ms"],
	]],
]
