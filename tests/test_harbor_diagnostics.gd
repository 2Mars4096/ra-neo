extends SceneTree
# Healthy soldiers have infinite bleed timers. The stopped rejection report
# must remain strict JSON and preserve the evidence without mutating the unit.
const Diagnostics=preload("res://tests/fixtures/harbor_order_diagnostics.gd")
var checks:=0
var failures:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func _init()->void:
	var original:={"hp":105.0,"pos":Vector2(318.3088,352.8779),"members":[
		{"hp":52.5,"bleed_at":INF,"missing":Vector2.INF},
		{"hp":52.5,"bleed_at":-INF,"probe":NAN}],"orders":[{"mode":"attack_move","pos":Vector2(340,342)}]}
	var converted:Dictionary=Diagnostics.plain(original)
	var encoded:=JSON.stringify(converted)
	var parser:=JSON.new()
	check(parser.parse(encoded)==OK,"nonfinite diagnostic state is valid strict JSON")
	check(converted.members[0].bleed_at=="inf" and converted.members[1].bleed_at=="-inf","infinite bleed timers remain labelled values")
	check(converted.members[1].probe=="nan" and converted.members[0].missing==["inf","inf"],"nested/vector nonfinite values remain labelled")
	check(converted.hp==105.0 and converted.members[0].hp==52.5 and converted.orders[0].pos==[340.0,342.0],"finite health and order coordinates preserved")
	converted.members[0].hp=0.0
	converted.orders[0].mode="move"
	check(original.members[0].hp==52.5 and original.orders[0].mode=="attack_move" and is_inf(original.members[0].bleed_at),"diagnostics never mutate source state")
	print("HARBOR DIAGNOSTICS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
