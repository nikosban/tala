class_name ErrorCounter
extends Logger
## Counts engine and script errors so the test runner can fail a test that crashed.
## Logger callbacks may arrive from any thread.

var _mutex := Mutex.new()
var _count := 0


func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	_mutex.lock()
	_count += 1
	_mutex.unlock()


func count() -> int:
	_mutex.lock()
	var n := _count
	_mutex.unlock()
	return n
