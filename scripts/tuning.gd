extends RefCounted

const MOVEMENT_A := {
	"speed": 302.0, "accel": 2550.0, "brake": 3060.0, "air_control": 0.73,
	"jump_height": 164.0, "buffer": 0.115, "roll_time": 0.31, "roll_speed": 550.0,
	"iframe_start": 0.045, "iframe_end": 0.245,
}
const MOVEMENT_B := {
	"speed": 302.0, "accel": 1450.0, "brake": 1650.0, "air_control": 0.39,
	"jump_height": 148.0, "buffer": 0.05, "roll_time": 0.38, "roll_speed": 500.0,
	"iframe_start": 0.045, "iframe_end": 0.245,
}
const ENEMY := {"speed": 118.0, "reach": 118.0, "windup": 0.57, "active": 0.12, "recovery": 0.57, "stagger": 0.28}
const FAST := {"reach": 67.0, "windup": 0.10, "active": 0.085, "recovery": 0.19, "move_factor": 0.73, "damage": 1.0, "interrupts": false}
const HEAVY := {"reach": 140.0, "windup": 0.33, "active": 0.13, "recovery": 0.40, "move_factor": 0.0, "damage": 2.0, "interrupts": true}
const M_FIELDS := [
	["accel", "地面加速度", 500, 6000, 50, "px/s²"],
	["brake", "地面制动", 500, 6500, 50, "px/s²"],
	["speed", "移动速度", 150, 475, 5, "px/s"],
	["air_control", "空中控制", 0.10, 1.40, 0.01, "×"],
	["jump_height", "目标跳高", 65, 250, 1, "px"],
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
