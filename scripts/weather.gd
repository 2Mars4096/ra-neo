extends RefCounted

# Authored passing front. Gameplay values are approximations, not meteorology.
static func sample(seconds:float,enabled:bool=true) -> Dictionary:
	var rain:=0.0
	var wet:=0.0
	if enabled:
		rain=clampf((seconds-25.0)/15.0,0,1)*clampf((130.0-seconds)/25.0,0,1)
		wet=clampf((seconds-25.0)/25.0,0,1)*clampf((230.0-seconds)/100.0,0,1)
	# Four stable visibility bands avoid rebuilding fog every simulation tick.
	var sight:=1.0-float(roundi(rain*4.0))*0.05
	return {"rain":rain,"wetness":wet,"sight_scale":sight,"wind":Vector2(1.3,0.45)*rain,"label":"RAIN" if rain>0.1 else ("DRYING" if wet>0.1 else "CLEAR")}
