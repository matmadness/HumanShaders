extends Node

signal new_log(message: String)

var _previous_message: String = ""
var _repeat_count: int = 1

func log_message(message: String) -> void:
	if message == _previous_message:
		_repeat_count += 1
	else:
		_repeat_count = 1
		_previous_message = message
	
	var display_message = message
	
	if _repeat_count > 1:
		display_message += " [color=yellow](x" + str(_repeat_count) + ")[/color]"
		
	new_log.emit(display_message)
	print(display_message)  # Optional: Also print to the standard output

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
		
func _process(_delta: float) -> void:
	RenderingServer.global_shader_parameter_set("frame_index", Engine.get_frames_drawn() * 2.0)
