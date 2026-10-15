extends RefCounted

# Weapon-specific impact and kill recipes for BattleEffects (scripts/effects.gd). Stateless static functions
# that spawn into the caller's fixed MultiMesh pools and bounded cue/emitter lists, so no recipe adds nodes.
# Every layer below ESSENTIAL is thinned first when the pools fill.

const CONCRETE:=Color(0.72,0.70,0.65)
const RUBBLE:=Color(0.47,0.45,0.42)
const TIMBER:=Color(0.36,0.27,0.18)
const CANVAS:=Color(0.38,0.40,0.30)
const HOT_WHITE:=Color(1.0,0.95,0.82)
const HEAT_ORANGE:=Color(1.0,0.62,0.26)
const SPILL:=Color(1.0,0.55,0.22,0.3)

# Destroyed field works: [material, scale]. Unlisted kinds that are not units fall back to generic_blast().
const FIELD_WORKS:={
	"bunker":["concrete",1.2],"command_post":["concrete",1.0],"tactical_cover":["concrete",0.6],
	"observation_post":["timber",0.75],"ammo_depot":["depot",1.3],"at_gun":["gun",0.8],
	"tank_obstacles":["steel",0.6],"fighting_trench":["earth",0.8],"vehicle_berm":["earth",0.9],
	"concertina_wire":["light",0.4],"camouflage_net":["light",0.5],
	"repair_point":["tent",0.9],"aid_post":["tent",0.8],"forward_supply_point":["tent",0.9],
}

# ---------------------------------------------------------------- impacts
# ATGM / rocket warhead: a hard white snap, then an orange fireball and dark smoke. On armour the shaped-charge
# jet throws sparks onward along the flight line; on soil it leaves a small scorch rather than a dirt fountain.
static func missile_burst(fx, pos:Vector3, direction:Vector3, scale:float, armor:bool) -> void:
	var rng:RandomNumberGenerator=fx.rng
	var c:=pos if armor else Vector3(pos.x,maxf(pos.y,BattleEffects.FLOOR)+0.2,pos.z)
	var g:=Vector3(pos.x,BattleEffects.FLOOR,pos.z)
	fx.flash(c,1.5*scale+0.3,0.04,HOT_WHITE)
	fx.flash(c,2.2*scale,0.08,HEAT_ORANGE,0.03,BattleEffects.NORMAL)
	fx.bloom(c,3.6*scale,0.22,SPILL)
	for n in 2:
		fx.fireball(c+fx._jitter(0.3*scale,0.15),Vector3(0,rng.randf_range(1.6,2.6),0)+fx._jitter(0.9*scale,0.0),0.5*scale,rng.randf_range(1.6,2.0)*scale,rng.randf_range(0.3,0.42),n*0.025)
	var bias:=direction*0.9+Vector3.UP*0.2 if armor else Vector3.UP*0.6
	fx.sparks(c,int(round(6+6*scale)),11.0*scale+2.0,bias,0.45)
	for n in 3:
		fx.smoke(c+Vector3(0,0.3,0)+fx._jitter(0.3*scale,0.1),Vector3(0,rng.randf_range(1.0,1.8),0)+fx._jitter(0.5,0.0),0.4*scale,rng.randf_range(1.9,2.5)*scale,rng.randf_range(2.2,3.0),Color(BattleEffects.SOOT.lerp(BattleEffects.GREY_SMOKE,0.3),0.72),1.2,0.5,0.08+n*0.06,BattleEffects.NORMAL if n<2 else BattleEffects.OPTIONAL)
	if armor:return
	fx.decal(g,BattleEffects.DUST_RING,0.4,3.2*scale,0.4,Color(BattleEffects.DUST,0.45))
	fx.decal(g,BattleEffects.SCORCH,1.1*scale+0.3,1.3*scale+0.4,35.0,Color(BattleEffects.SCORCH_COLOR,0.6),BattleEffects.OPTIONAL)
	for n in 3:
		fx.debris(g+Vector3(0,0.1,0),fx._jitter(1.5*scale,0.0)+Vector3(0,rng.randf_range(3.0,5.0),0),rng.randf_range(0.07,0.12),rng.randf_range(0.8,1.2),BattleEffects.SOIL,false,false,BattleEffects.OPTIONAL)

# Concrete, brick or sandbag face: pale masonry dust blown back toward the shooter and bouncing chips.
# Rifle-scale hits (scale < 0.35) are a single puff and two chips, since bunkers draw sustained fire.
static func masonry_hit(fx, pos:Vector3, direction:Vector3, scale:float) -> void:
	var rng:RandomNumberGenerator=fx.rng
	var back:Vector3=-fx._flat(direction)
	var p:=Vector3(pos.x,maxf(pos.y,0.3),pos.z)
	if scale<0.35:
		fx.smoke(p,back*rng.randf_range(0.6,1.2)+Vector3(0,0.5,0),0.14,0.6,0.7,Color(CONCRETE,0.6),2.6,0.1,0.0,BattleEffects.OPTIONAL)
		for n in 2:fx.debris(p,back*rng.randf_range(0.8,1.8)+fx._jitter(0.6,0.0)+Vector3(0,rng.randf_range(1.2,2.4),0),0.05,0.6,RUBBLE,true,false,BattleEffects.OPTIONAL)
		return
	for n in int(round(1+3*scale)):
		fx.smoke(p+fx._jitter(0.25*scale),back*rng.randf_range(0.6,1.6)*scale+Vector3(0,rng.randf_range(0.4,1.1),0),0.3*scale+0.1,rng.randf_range(1.5,2.2)*scale+0.3,rng.randf_range(1.6,2.6),Color(CONCRETE,0.7),1.8,0.15,0.0,BattleEffects.NORMAL if n<2 else BattleEffects.OPTIONAL)
	for n in int(round(2+5*scale)):
		fx.debris(p,back*rng.randf_range(1.0,3.0)*scale+fx._jitter(1.4*scale,0.0)+Vector3(0,rng.randf_range(1.5,4.0)*sqrt(scale),0),rng.randf_range(0.06,0.13)*(0.6+scale*0.6),rng.randf_range(0.9,1.5),RUBBLE if n%2 else CONCRETE.darkened(0.2),true,false,BattleEffects.NORMAL if n<2 else BattleEffects.OPTIONAL)
	if scale>=0.6:
		# Dust sliding down the face and spreading along the ground a moment later.
		var g:=Vector3(pos.x,0.25,pos.z)
		for n in 3:
			var out:=back.rotated(Vector3.UP,rng.randf_range(-1.4,1.4))
			fx.smoke(g+out*0.4,out*rng.randf_range(1.2,2.4)*scale,0.5*scale,rng.randf_range(1.8,2.4)*scale,rng.randf_range(1.8,2.6),Color(CONCRETE.darkened(0.08),0.55),2.0,0.05,0.12+n*0.04,BattleEffects.OPTIONAL)
		fx.decal(Vector3(pos.x,BattleEffects.FLOOR,pos.z),BattleEffects.DUST_RING,0.5,3.0*scale,0.5,Color(CONCRETE,0.45),BattleEffects.OPTIONAL)

# HE shell into a wall: flash and fireball at the face, masonry burst, no soil fountain.
static func shell_on_masonry(fx, pos:Vector3, direction:Vector3, scale:float) -> void:
	var rng:RandomNumberGenerator=fx.rng
	fx.flash(pos,1.3*scale+0.3,0.06,Color(1.0,0.82,0.5))
	fx.bloom(pos,2.8*scale,0.16,SPILL)
	fx.fireball(pos-direction*0.3,-direction*1.2+Vector3(0,1.2,0),0.5*scale,1.5*scale,0.25)
	fx.sparks(pos,int(4*scale),8.0,-direction*0.5+Vector3.UP*0.5,0.4,BattleEffects.OPTIONAL)
	masonry_hit(fx,pos,direction,scale)
	fx.smoke(pos,Vector3(0,0.9,0)+fx._jitter(0.3,0.0),0.4*scale,1.8*scale,rng.randf_range(1.8,2.4),Color(BattleEffects.SOOT,0.55),1.4,0.4,0.05)

# Armour-piercing gun round: a small, very bright strike, a dense rebound fan, a few fragments carried on
# through the plate, and a glowing hot spot that fades over half a second.
static func ap_strike(fx, pos:Vector3, direction:Vector3, scale:float) -> void:
	fx.flash(pos,0.8*scale+0.3,0.035,HOT_WHITE)
	fx.sparks(pos,int(round(8+6*scale)),12.0*scale+3.0,-direction*0.8+Vector3.UP*0.4,0.4)
	fx.sparks(pos,int(round(2+3*scale)),14.0,direction*1.2,0.3,BattleEffects.OPTIONAL)
	fx.ember(pos,Vector3.ZERO,0.45*scale+0.15,0.5,Color(1.0,0.42,0.18,0.9))
	fx.smoke(pos,Vector3(0,0.7,0)+fx._jitter(0.3),0.25*scale,1.1*scale,1.1,Color(BattleEffects.SOOT,0.5),1.6,0.3,0.03,BattleEffects.OPTIONAL)

# AP round into soil: a low, fast skip spurt along the flight line instead of an HE crater.
static func ap_ground(fx, pos:Vector3, direction:Vector3) -> void:
	var rng:RandomNumberGenerator=fx.rng
	var g:=Vector3(pos.x,BattleEffects.FLOOR+0.05,pos.z)
	var along:Vector3=fx._flat(direction)
	for n in 2:
		fx.smoke(g+along*n*0.5,along*rng.randf_range(2.0,3.5)+Vector3(0,rng.randf_range(1.0,1.8),0),0.2,rng.randf_range(0.9,1.3),rng.randf_range(0.8,1.1),Color(BattleEffects.DUST,0.62),2.6,0.0,n*0.03)
	for n in 3:
		fx.debris(g,along*rng.randf_range(2.0,4.0)+fx._jitter(0.8,0.0)+Vector3(0,rng.randf_range(1.5,3.0),0),0.08,0.8,BattleEffects.SOIL,false,false,BattleEffects.OPTIONAL)
	fx.decal(g,BattleEffects.DUST_RING,0.3,1.6,0.35,Color(BattleEffects.DUST,0.4),BattleEffects.OPTIONAL)

# FPV / loitering-munition detonation: a tight white burst, a fast spherical fragment spray, one small
# fireball and a grey puff. Shot down above 1.6 m it bursts in the air; on water it throws a short column.
static func drone_strike(fx, pos:Vector3, water:bool, armor:bool) -> void:
	var rng:RandomNumberGenerator=fx.rng
	fx._boom(0.45)
	if pos.y>1.6 and not armor:
		fx.air_burst(pos,0.32,false)
		return
	var c:=Vector3(pos.x,maxf(pos.y,0.35),pos.z)
	var g:=Vector3(pos.x,BattleEffects.FLOOR,pos.z)
	fx.flash(c,1.4,0.04,HOT_WHITE)
	fx.bloom(c,2.8,0.18,SPILL)
	fx.fireball(c,Vector3(0,1.6,0),0.4,1.3,0.28)
	fx.sparks(c,12,13.0,Vector3.UP*0.3,0.35)
	for n in 2:
		fx.smoke(c+fx._jitter(0.25),Vector3(0,rng.randf_range(0.8,1.4),0)+fx._jitter(0.4,0.0),0.3,rng.randf_range(1.4,1.8),rng.randf_range(1.6,2.2),Color(BattleEffects.GREY_SMOKE.darkened(0.25),0.66),1.4,0.3,0.05+n*0.05)
	if water:
		fx.water_strike(g,0.6)
		return
	fx.decal(g,BattleEffects.DUST_RING,0.4,2.6,0.35,Color(BattleEffects.DUST,0.5))
	fx.decal(g,BattleEffects.SCORCH,0.8,1.0,30.0,Color(BattleEffects.SCORCH_COLOR,0.55),BattleEffects.OPTIONAL)
	for n in 3:
		fx.debris(c,fx._jitter(2.5,0.0)+Vector3(0,rng.randf_range(2.0,4.0),0),rng.randf_range(0.05,0.1),rng.randf_range(0.8,1.3),BattleEffects.METAL,true,false,BattleEffects.OPTIONAL)

# ---------------------------------------------------------------- kills
# Fallback for any destroyed kind the effects do not know (new units arrive before their recipe): a small,
# complete explosion with no lingering emitter.
static func generic_blast(fx, pos:Vector3, water:bool) -> void:
	var rng:RandomNumberGenerator=fx.rng
	var c:=Vector3(pos.x,maxf(pos.y,0.4),pos.z)
	var g:=Vector3(pos.x,BattleEffects.FLOOR,pos.z)
	fx._boom(0.6)
	fx.flash(c+Vector3(0,0.3,0),1.9,0.07,Color(1.0,0.86,0.55))
	fx.bloom(c,3.0,0.24,SPILL)
	for n in 2:
		fx.fireball(c+fx._jitter(0.35,0.15),Vector3(0,rng.randf_range(1.2,2.0),0)+fx._jitter(0.6,0.0),0.5,rng.randf_range(1.5,1.9),rng.randf_range(0.35,0.5),n*0.03)
	fx.sparks(c,6,9.0,Vector3.UP*0.7,0.6)
	for n in 4:
		fx.debris(c,fx._jitter(2.6,0.0)+Vector3(0,rng.randf_range(3.0,6.0),0),rng.randf_range(0.08,0.16),rng.randf_range(1.1,1.6),BattleEffects.METAL if n%2==0 else BattleEffects.SOOT,not water)
	for n in 3:
		fx.smoke(c+Vector3(0,0.5,0)+fx._jitter(0.4,0.2),Vector3(0,rng.randf_range(1.2,2.0),0),0.6,rng.randf_range(2.0,2.6),rng.randf_range(2.6,3.6),Color(BattleEffects.SOOT,0.72),0.8,0.8,0.12+n*0.05)
	if water:
		fx.water_strike(g,0.7)
	else:
		fx.decal(g,BattleEffects.DUST_RING,0.6,3.6,0.4,Color(BattleEffects.DUST,0.5))
		fx.decal(g,BattleEffects.SCORCH,1.4,1.7,35.0,Color(BattleEffects.SCORCH_COLOR,0.6),BattleEffects.OPTIONAL)

static func field_work_destroyed(fx, kind:String, pos:Vector3, water:bool) -> void:
	var spec:Array=FIELD_WORKS[kind]
	var k:float=spec[1]
	var g:=Vector3(pos.x,BattleEffects.FLOOR,pos.z)
	match String(spec[0]):
		"concrete":concrete_collapse(fx,pos,k)
		"depot":
			# Ammunition dump: a large kill, then a rolling chain of cook-offs and a long fire.
			fx.vehicle_explosion(Vector3(pos.x,0.7,pos.z),k,water,false)
			for n in 4:
				var offset:Vector3=Vector3.FORWARD.rotated(Vector3.UP,n*TAU/4+fx.rng.randf())*fx.rng.randf_range(0.8,2.2)
				fx.cue(0.5+n*0.6+fx.rng.randf_range(0.0,0.3),Callable(fx,"_cook_off").bind(Vector3(pos.x,0.8,pos.z)+offset))
			fx.add_emitter(g,14.0,1.1,water)
		"gun":fx.vehicle_explosion(Vector3(pos.x,0.6,pos.z),k,water,true)
		"steel":
			fx.armor_hit(Vector3(pos.x,0.6,pos.z),Vector3.DOWN,k)
			fx.he_burst(pos,Vector3.DOWN,0.5)
		"earth":
			fx.he_burst(pos,Vector3.DOWN,k)
			_dust_skirt(fx,g,k,BattleEffects.DUST)
		"timber":
			fx.he_burst(pos,Vector3.DOWN,k)
			_splinters(fx,Vector3(pos.x,1.0,pos.z),k,TIMBER)
			fx.add_emitter(g,6.0,0.55,water)
		"tent":
			generic_blast(fx,pos,water)
			_splinters(fx,Vector3(pos.x,0.6,pos.z),k,CANVAS)
			fx.add_emitter(g,7.0,0.65*k,water)
		_:
			# Wire and nets: torn apart without an explosion of their own.
			_dust_skirt(fx,g,k,BattleEffects.DUST)
			_splinters(fx,Vector3(pos.x,0.4,pos.z),k,BattleEffects.METAL)

# Bunker / pillbox collapse: blast through the embrasures, then a heavy pale cloud of concrete dust that rolls
# outward and hangs, chunks of slab bouncing, and a smouldering interior.
static func concrete_collapse(fx, pos:Vector3, scale:float) -> void:
	var rng:RandomNumberGenerator=fx.rng
	var c:=Vector3(pos.x,0.9,pos.z)
	var g:=Vector3(pos.x,BattleEffects.FLOOR,pos.z)
	fx._boom(scale)
	fx.flash(c,2.6*scale,0.08,Color(1.0,0.86,0.55))
	fx.bloom(c,4.2*scale,0.32,SPILL,BattleEffects.ESSENTIAL)
	for n in 2:
		fx.fireball(c+fx._jitter(0.5*scale,0.2),Vector3(0,rng.randf_range(1.4,2.2),0)+fx._jitter(0.8,0.0),0.7*scale,rng.randf_range(2.0,2.6)*scale,rng.randf_range(0.35,0.5),n*0.04)
	for n in int(round(8*scale)):
		fx.debris(c,fx._jitter(3.5*scale,0.0)+Vector3(0,rng.randf_range(3.0,7.0),0),rng.randf_range(0.14,0.3)*scale,rng.randf_range(1.4,2.2),RUBBLE if n%2 else CONCRETE.darkened(0.15),true,false,BattleEffects.NORMAL if n<4 else BattleEffects.OPTIONAL)
	for n in 6:
		fx.smoke(c+fx._jitter(1.2*scale,0.3),Vector3(0,rng.randf_range(0.8,1.6),0)+fx._jitter(0.6,0.0),1.0*scale,rng.randf_range(3.0,3.8)*scale,rng.randf_range(3.5,5.0),Color(CONCRETE,0.72),1.0,0.35,0.05+n*0.06,BattleEffects.ESSENTIAL if n<3 else BattleEffects.NORMAL)
	_dust_skirt(fx,g,scale,CONCRETE)
	fx.decal(g,BattleEffects.SCORCH,2.4*scale,2.8*scale,45.0,Color(BattleEffects.SCORCH_COLOR,0.55),BattleEffects.ESSENTIAL)
	fx.cue(rng.randf_range(0.4,0.7),Callable(fx,"_cook_off").bind(c+fx._jitter(0.6,0.0)))
	fx.add_emitter(g,9.0,0.7*scale,false)

# Low ring of dust shoved outward along the ground.
static func _dust_skirt(fx, g:Vector3, scale:float, col:Color) -> void:
	var rng:RandomNumberGenerator=fx.rng
	fx.decal(g,BattleEffects.DUST_RING,0.8*scale,6.0*scale,0.5,Color(col,0.55),BattleEffects.NORMAL)
	for n in 8:
		var out:=Vector3.FORWARD.rotated(Vector3.UP,n*TAU/8+rng.randf_range(-0.2,0.2))
		fx.smoke(g+Vector3(0,0.25,0)+out*0.7*scale,out*rng.randf_range(3.0,5.5)*scale,0.5*scale,rng.randf_range(2.0,2.8)*scale,rng.randf_range(1.8,2.8),Color(col,0.55),2.2,0.05,0.06,BattleEffects.NORMAL if n%2==0 else BattleEffects.OPTIONAL)

static func _splinters(fx, pos:Vector3, scale:float, col:Color) -> void:
	var rng:RandomNumberGenerator=fx.rng
	for n in int(round(3+5*scale)):
		fx.debris(pos,fx._jitter(2.5*scale+0.5,0.0)+Vector3(0,rng.randf_range(2.0,4.5),0),rng.randf_range(0.07,0.15),rng.randf_range(1.0,1.6),col,true,false,BattleEffects.OPTIONAL)
