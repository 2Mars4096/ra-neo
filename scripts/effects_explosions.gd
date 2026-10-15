extends RefCounted

# Weapon-specific impact and kill recipes for BattleEffects (scripts/effects.gd). Stateless static functions
# that spawn into the caller's fixed MultiMesh pools and bounded cue/emitter lists, so no recipe adds nodes.
# Every layer below ESSENTIAL is thinned first when the pools fill.

const Remains:=preload("res://scripts/effects_remains.gd")
const CONCRETE:=Color(0.72,0.70,0.65)
const RUBBLE:=Color(0.47,0.45,0.42)
const TIMBER:=Color(0.36,0.27,0.18)
const CANVAS:=Color(0.38,0.40,0.30)
const HOT_WHITE:=Color(1.0,0.95,0.82)
const HEAT_ORANGE:=Color(1.0,0.62,0.26)
const SPILL:=Color(1.0,0.55,0.22,0.3)
const CORE:=Color(1.0,0.9,0.72,0.95)
const GROUND_GLOW:=Color(1.0,0.5,0.2,0.34)
const SHOCK:=Color(0.9,0.86,0.76)
const BLACK_SMOKE:=Color(0.09,0.085,0.08)
# Hand-off smoke: tan dust for ground hits, dark grey for hull/air hits, near-black for vehicle kills.
const TAN_DUST:=Color(0.50,0.43,0.33)
const DARK_GREY:=Color(0.22,0.21,0.2)
# Fireball tints multiply the shader's white -> orange -> soot ramp.
const LOBE_HOT:=Color(1.0,0.8,0.62)
const LOBE_EDGE:=Color(0.8,0.46,0.32)
const SMOKY_LOBE:=Color(0.3,0.24,0.2)
# Hot yellow-white core (additive glow pool, always drawn over the fireball cards).
const CORE_GLOW:=Color(1.0,0.86,0.52,0.75)
const HEAT:=Color(1.0,0.32,0.1,0.32)
# Largest ground ring card (m); a structure-sized blast would otherwise lay a 40 m ring.
const RING_MAX:=28.0

# Destroyed field works: [material, scale]. Unlisted kinds that are not units fall back to generic_blast().
const FIELD_WORKS:={
	"bunker":["concrete",1.2],"command_post":["concrete",1.0],"tactical_cover":["concrete",0.6],
	"observation_post":["timber",0.75],"ammo_depot":["depot",1.3],"at_gun":["gun",0.8],
	"tank_obstacles":["steel",0.6],"fighting_trench":["earth",0.8],"vehicle_berm":["earth",0.9],
	"concertina_wire":["light",0.4],"camouflage_net":["light",0.5],
	"repair_point":["tent",0.9],"aid_post":["tent",0.8],"forward_supply_point":["tent",0.9],
}

# ---------------------------------------------------------------- shared layers
# Every blast is authored around R, its peak visible fireball radius in metres (tank kill 5, tank HE 2.5, ATGM on
# soil 1.5). Layers in time order: core flash (1-2 frames) -> fireball rolling up and cooling into smoke ->
# ground shock ring and dust skirt -> debris arcs -> rising column -> sparks -> scorch. Card sizes are diameters
# and the shaders erode roughly a quarter of each card, hence the factors below.

# Warm-white star and soft core for one or two frames, plus an additive firelight card on the ground that
# fades over ~0.45 s in place of a dynamic light.
static func core_flash(fx, c:Vector3, g:Vector3, r:float, col:Color=HOT_WHITE) -> void:
	fx.flash(c,3.0*r,0.03,col)
	fx.bloom(c,2.2*r,0.1,CORE,BattleEffects.ESSENTIAL)
	fx.bloom(g+Vector3(0,0.3,0),3.2*r,0.4,GROUND_GLOW,BattleEffects.NORMAL)

# A central ball and outward lobes that rise under lift; the volume shader cools them white -> orange -> soot.
# Each card's hue is set by the shader per age, so the radial ramp is built from layers: an additive yellow-white
# core that shrinks inside the ball, a central ball pulled slightly toward orange, outer lobes tinted toward red-
# brown with per-card brightness, and `dark` near-black smoky lobes mixed into the fire layer from the start.
static func fireball_layer(fx, c:Vector3, r:float, lobes:int, life:float, dark:int=1) -> void:
	var rng:RandomNumberGenerator=fx.rng
	fx.fireball(c,Vector3(0,0.7*r,0),1.0*r,2.8*r,life,0.0,BattleEffects.ESSENTIAL,1.8,0.9*r,ball_tint(rng))
	fx.ember(c,Vector3(0,0.6*r,0),1.5*r,life*0.45,CORE_GLOW,BattleEffects.ESSENTIAL)
	for n in lobes:
		var out:=Vector3.FORWARD.rotated(Vector3.UP,n*TAU/lobes+rng.randf_range(-0.5,0.5))
		var tint:Color=LOBE_HOT.lerp(LOBE_EDGE,rng.randf())*rng.randf_range(0.85,1.0)
		tint.a=1.0
		fx.fireball(c+out*0.35*r+Vector3(0,0.15*r,0),out*rng.randf_range(0.9,1.4)*r+Vector3(0,rng.randf_range(0.5,1.0)*r,0),0.5*r,rng.randf_range(1.5,1.9)*r,life*rng.randf_range(0.75,0.95),n*0.02,BattleEffects.ESSENTIAL if n<2 else BattleEffects.NORMAL,2.4,0.8*r,tint)
	for n in dark:
		var out:=Vector3.FORWARD.rotated(Vector3.UP,rng.randf()*TAU)
		var smoky:Color=SMOKY_LOBE*rng.randf_range(0.8,1.15)
		smoky.a=0.95
		fx.fireball(c+out*0.5*r+Vector3(0,0.3*r,0),out*rng.randf_range(0.5,0.9)*r+Vector3(0,rng.randf_range(0.7,1.1)*r,0),0.6*r,rng.randf_range(1.4,1.7)*r,life*rng.randf_range(0.85,1.0),rng.randf_range(0.04,0.1),BattleEffects.NORMAL,2.0,0.9*r,smoky)

# Central ball tint: near white with a little orange, varied per blast.
static func ball_tint(rng:RandomNumberGenerator) -> Color:
	return Color(1.0,rng.randf_range(0.86,0.95),rng.randf_range(0.72,0.88))

# Per-card brightness so a cloud of same-coloured puffs does not read as one flat shade.
static func shade(rng:RandomNumberGenerator, col:Color) -> Color:
	var k:=rng.randf_range(0.82,1.1)
	return Color(col.r*k,col.g*k,col.b*k,col.a)

# Smoke born inside the cooling fireball, so the ball visibly darkens into a rolling cloud that keeps rising.
static func smoke_handoff(fx, c:Vector3, r:float, count:int, col:Color, fire_life:float, life:float) -> void:
	var rng:RandomNumberGenerator=fx.rng
	for n in count:
		fx.smoke(c+Vector3(0,0.35*r,0)+fx._jitter(0.45*r,0.25*r),Vector3(0,rng.randf_range(0.35,0.6)*r,0)+fx._jitter(0.25*r,0.0),1.2*r,rng.randf_range(1.9,2.3)*r,rng.randf_range(life*0.8,life),shade(rng,col),1.1,0.22*r,fire_life*0.35+n*0.04,BattleEffects.ESSENTIAL if n<2 else BattleEffects.NORMAL)

# Fast pale overpressure ring, a slower dust ring and low puffs shoved outward that stop about 1.5 R out.
static func shockwave(fx, g:Vector3, r:float, col:Color, skirt:int, priority:int=BattleEffects.NORMAL, shock:bool=true) -> void:
	var rng:RandomNumberGenerator=fx.rng
	if shock:fx.decal(g,BattleEffects.DUST_RING,0.8*r,minf(4.8*r,RING_MAX),0.32,Color(SHOCK,0.85),priority)
	fx.decal(g,BattleEffects.DUST_RING,0.6*r,minf(3.4*r,RING_MAX),1.1,Color(col,0.6),BattleEffects.OPTIONAL)
	for n in skirt:
		var out:=Vector3.FORWARD.rotated(Vector3.UP,n*TAU/skirt+rng.randf_range(-0.25,0.25))
		fx.smoke(g+Vector3(0,0.2+0.08*r,0)+out*0.45*r,out*rng.randf_range(2.4,3.6)*r,0.6*r,rng.randf_range(1.2,1.6)*r,rng.randf_range(1.6,2.4),Color(col,0.6),2.6,0.1,0.02,priority if n%2==0 else BattleEffects.OPTIONAL)

# Chunks thrown in ballistic arcs. Height and reach grow with sqrt(R) so a tank kill does not launch into orbit.
static func debris_arcs(fx, origin:Vector3, r:float, count:int, cols:Array, trails:int, bounce:bool) -> void:
	var rng:RandomNumberGenerator=fx.rng
	var k:=sqrt(r)
	for n in count:
		var out:=Vector3.FORWARD.rotated(Vector3.UP,rng.randf()*TAU)
		var up:=rng.randf_range(3.4,5.4)*k
		fx.debris(origin,out*rng.randf_range(1.0,2.4)*k+Vector3(0,up,0),rng.randf_range(0.07,0.13)*r+0.06,2.0*up/9.8+rng.randf_range(0.3,0.8),cols[n%cols.size()],bounce,n<trails,BattleEffects.NORMAL if n<count/2 else BattleEffects.OPTIONAL)

# Billowing column that rises and lingers after the fireball.
static func column(fx, base:Vector3, r:float, count:int, col:Color, life:float, priority:int=BattleEffects.NORMAL) -> void:
	var rng:RandomNumberGenerator=fx.rng
	for n in count:
		fx.smoke(base+Vector3(0,0.3*r+n*0.2*r,0)+fx._jitter(0.25*r,0.0),Vector3(0,rng.randf_range(0.45,0.8)*r,0)+fx._jitter(0.15*r,0.0),0.8*r,rng.randf_range(1.6,2.0)*r,rng.randf_range(life*0.8,life),shade(rng,col),0.9,0.3*r,0.12+n*0.1,priority if n<count/2 else BattleEffects.OPTIONAL)

# Fresh scorch: a short-lived dark decal over the new permanent mark, fading within `life` seconds to reveal it.
static func scorch(fx, g:Vector3, r:float, life:float, alpha:float=0.7, priority:int=BattleEffects.NORMAL) -> void:
	fx.decal(g,BattleEffects.SCORCH,1.6*r,1.9*r,life,Color(BattleEffects.SCORCH_COLOR,alpha),priority)

# Smouldering ground for a few seconds after a kill: a dull red additive card low over the burn mark.
static func heat(fx, g:Vector3, r:float, life:float) -> void:
	fx.bloom(g+Vector3(0,0.2,0),1.6*r,life,HEAT,BattleEffects.OPTIONAL)

# ---------------------------------------------------------------- impacts
# ATGM / rocket warhead: a hard white snap, then an orange fireball and dark smoke. On armour the shaped-charge
# jet throws sparks onward along the flight line; on soil it leaves a scorch and a small dirt skirt rather than
# an HE fountain. scale 0.9 on soil gives R = 1.5 m.
static func missile_burst(fx, pos:Vector3, direction:Vector3, scale:float, armor:bool) -> void:
	var rng:RandomNumberGenerator=fx.rng
	var r:=1.65*scale
	var c:=pos if armor else Vector3(pos.x,maxf(pos.y,BattleEffects.FLOOR)+0.35*r,pos.z)
	var g:=Vector3(pos.x,BattleEffects.FLOOR,pos.z)
	fx.flash(c,3.0*r,0.035,HOT_WHITE)
	fx.flash(c,2.2*r,0.07,HEAT_ORANGE,0.03,BattleEffects.NORMAL)
	fx.bloom(g+Vector3(0,0.3,0),3.2*r,0.3,GROUND_GLOW)
	fireball_layer(fx,c,r,2,0.5)
	var bias:=direction*0.9+Vector3.UP*0.2 if armor else Vector3.UP*0.6
	fx.sparks(c,int(round(6+6*scale)),11.0*scale+3.0,bias,0.55,BattleEffects.NORMAL,1.6)
	smoke_handoff(fx,c,r,3,Color(DARK_GREY if armor else TAN_DUST.darkened(0.2),0.8),0.5,2.8)
	fx.shake(c,0.22*scale)
	if armor:return
	fx.decal(g,BattleEffects.DUST_RING,0.6*r,4.8*r,0.3,Color(SHOCK,0.75))
	scorch(fx,g,r,4.0,0.6,BattleEffects.OPTIONAL)
	fx.mark(g,1.0*r,Remains.SCORCH)
	fx.mark(g,0.3*r,Remains.CRATER)
	for n in 3:
		var out:=Vector3.FORWARD.rotated(Vector3.UP,n*TAU/3+rng.randf_range(-0.3,0.3))
		fx.smoke(g+Vector3(0,0.3,0)+out*0.4*r,out*rng.randf_range(2.2,3.2)*r,0.6*r,1.3*r,rng.randf_range(1.4,2.0),Color(BattleEffects.DUST,0.55),2.6,0.1,0.02,BattleEffects.OPTIONAL)
	debris_arcs(fx,g+Vector3(0,0.1,0),r,3,[BattleEffects.SOIL],0,false)

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
		fx.smoke(p+fx._jitter(0.4*scale),back*rng.randf_range(1.0,2.6)*scale+Vector3(0,rng.randf_range(0.6,1.6),0),0.5*scale+0.15,rng.randf_range(2.6,3.4)*scale+0.4,rng.randf_range(2.0,3.0),Color(CONCRETE,0.78),1.8,0.2,0.0,BattleEffects.NORMAL if n<2 else BattleEffects.OPTIONAL)
	for n in int(round(2+5*scale)):
		fx.debris(p,back*rng.randf_range(1.5,4.0)*scale+fx._jitter(2.0*scale,0.0)+Vector3(0,rng.randf_range(2.5,5.5)*sqrt(scale),0),rng.randf_range(0.1,0.22)*(0.6+scale*0.6),rng.randf_range(1.2,1.8),RUBBLE if n%2 else CONCRETE.darkened(0.2),true,n==0 and scale>=0.6,BattleEffects.NORMAL if n<2 else BattleEffects.OPTIONAL)
	if scale>=0.6:
		# Dust sliding down the face and spreading along the ground a moment later.
		var g:=Vector3(pos.x,0.25,pos.z)
		for n in 3:
			var out:=back.rotated(Vector3.UP,rng.randf_range(-1.4,1.4))
			fx.smoke(g+out*0.6,out*rng.randf_range(2.0,3.6)*scale,0.8*scale,rng.randf_range(2.8,3.6)*scale,rng.randf_range(2.2,3.0),Color(CONCRETE.darkened(0.08),0.6),2.0,0.05,0.12+n*0.04,BattleEffects.OPTIONAL)
		fx.decal(Vector3(pos.x,BattleEffects.FLOOR,pos.z),BattleEffects.DUST_RING,0.8,5.0*scale,0.6,Color(CONCRETE,0.55),BattleEffects.OPTIONAL)

# HE shell into a wall: flash and fireball at the face, masonry burst, no soil fountain. R = 2.2 m at scale 1.
static func shell_on_masonry(fx, pos:Vector3, direction:Vector3, scale:float) -> void:
	var rng:RandomNumberGenerator=fx.rng
	var r:=2.2*scale
	var c:=pos-direction*0.3
	fx.flash(c,3.0*r,0.035,Color(1.0,0.86,0.6))
	fx.bloom(c,2.0*r,0.1,CORE,BattleEffects.ESSENTIAL)
	fx.bloom(Vector3(pos.x,0.3,pos.z),3.2*r,0.3,GROUND_GLOW)
	fx.fireball(c,-direction*1.0*r+Vector3(0,0.6*r,0),0.8*r,2.4*r,0.45,0.0,BattleEffects.ESSENTIAL,1.8,0.8*r)
	fx.sparks(c,int(6*scale),10.0,-direction*0.5+Vector3.UP*0.5,0.5,BattleEffects.OPTIONAL,1.6)
	masonry_hit(fx,pos,direction,scale)
	fx.smoke(c,Vector3(0,0.5*r,0)+fx._jitter(0.3,0.0),0.9*r,2.4*r,rng.randf_range(2.4,3.0),Color(BattleEffects.SOOT,0.65),1.2,0.3*r,0.12)
	fx.shake(c,0.3*scale)

# Armour-piercing gun round: a small, very bright strike, a dense rebound fan, a few fragments carried on
# through the plate, and a glowing hot spot that fades over half a second. Kinetic, so no fireball or shake.
static func ap_strike(fx, pos:Vector3, direction:Vector3, scale:float) -> void:
	fx.flash(pos,1.2*scale+0.4,0.035,HOT_WHITE)
	fx.sparks(pos,int(round(8+6*scale)),13.0*scale+3.0,-direction*0.8+Vector3.UP*0.4,0.45,BattleEffects.NORMAL,1.5)
	fx.sparks(pos,int(round(2+3*scale)),15.0,direction*1.2,0.35,BattleEffects.OPTIONAL,1.5)
	fx.ember(pos,Vector3.ZERO,0.7*scale+0.2,0.55,Color(1.0,0.42,0.18,0.9))
	fx.smoke(pos,Vector3(0,0.8,0)+fx._jitter(0.3),0.4*scale,1.8*scale,1.4,Color(BattleEffects.SOOT,0.55),1.6,0.3,0.03,BattleEffects.OPTIONAL)

# AP round into soil: a low, fast skip spurt along the flight line instead of an HE crater.
static func ap_ground(fx, pos:Vector3, direction:Vector3) -> void:
	var rng:RandomNumberGenerator=fx.rng
	var g:=Vector3(pos.x,BattleEffects.FLOOR+0.05,pos.z)
	var along:Vector3=fx._flat(direction)
	for n in 2:
		fx.smoke(g+along*n*0.6,along*rng.randf_range(2.5,4.2)+Vector3(0,rng.randf_range(1.2,2.0),0),0.3,rng.randf_range(1.3,1.8),rng.randf_range(0.9,1.3),Color(BattleEffects.DUST,0.65),2.6,0.0,n*0.03)
	for n in 3:
		fx.debris(g,along*rng.randf_range(2.0,4.5)+fx._jitter(0.8,0.0)+Vector3(0,rng.randf_range(1.8,3.4),0),0.13,0.9,BattleEffects.SOIL,false,false,BattleEffects.OPTIONAL)
	fx.decal(g,BattleEffects.DUST_RING,0.4,2.4,0.4,Color(BattleEffects.DUST,0.45),BattleEffects.OPTIONAL)
	fx.mark(g+along*0.5,0.45,Remains.CRATER)

# FPV / loitering-munition detonation: a tight white burst, a fast spherical fragment spray, one fireball and a
# grey puff (R = 1.3 m). Shot down above 1.6 m it bursts in the air; on water it throws a short column.
static func drone_strike(fx, pos:Vector3, water:bool, armor:bool) -> void:
	var rng:RandomNumberGenerator=fx.rng
	fx._boom(0.45)
	if pos.y>1.6 and not armor:
		fx.air_burst(pos,0.32,false)
		return
	var r:=1.3
	var c:=Vector3(pos.x,maxf(pos.y,0.5),pos.z)
	var g:=Vector3(pos.x,BattleEffects.FLOOR,pos.z)
	fx.flash(c,3.0*r,0.035,HOT_WHITE)
	fx.bloom(c,2.0*r,0.08,CORE,BattleEffects.ESSENTIAL)
	fx.bloom(g+Vector3(0,0.3,0),3.2*r,0.3,GROUND_GLOW)
	fx.fireball(c,Vector3(0,0.8*r,0),1.0*r,2.6*r,0.4,0.0,BattleEffects.ESSENTIAL,1.8,0.9*r,ball_tint(rng))
	fx.sparks(c,14,15.0,Vector3.UP*0.3,0.45,BattleEffects.NORMAL,1.6)
	fx.ember(c,Vector3(0,0.5*r,0),1.4*r,0.18,CORE_GLOW,BattleEffects.NORMAL)
	for n in 2:
		fx.smoke(c+fx._jitter(0.3),Vector3(0,rng.randf_range(0.6,1.0)*r,0)+fx._jitter(0.4,0.0),0.9*r,rng.randf_range(2.0,2.5)*r,rng.randf_range(2.0,2.6),Color(DARK_GREY if water else TAN_DUST.darkened(0.25),0.74),1.3,0.3*r,0.12+n*0.05)
	fx.shake(c,0.25)
	if water:
		fx.water_strike(g,0.6)
		return
	fx.decal(g,BattleEffects.DUST_RING,0.6*r,4.8*r,0.3,Color(SHOCK,0.8))
	scorch(fx,g,r,3.5,0.6,BattleEffects.OPTIONAL)
	fx.mark(g,1.0*r,Remains.SCORCH)
	for n in 3:
		fx.debris(c,fx._jitter(2.8,0.0)+Vector3(0,rng.randf_range(2.5,4.5),0),rng.randf_range(0.1,0.16),rng.randf_range(0.9,1.4),BattleEffects.METAL,true,false,BattleEffects.OPTIONAL)

# ---------------------------------------------------------------- kills
# Fallback for any destroyed kind the effects do not know (new units arrive before their recipe): a smaller,
# complete explosion with no lingering emitter. R = 2.2 m.
static func generic_blast(fx, pos:Vector3, water:bool) -> void:
	var r:=2.2
	var c:=Vector3(pos.x,maxf(pos.y,0.4)+0.3*r,pos.z)
	var g:=Vector3(pos.x,BattleEffects.FLOOR,pos.z)
	fx._boom(0.6)
	core_flash(fx,c,g,r,Color(1.0,0.86,0.6))
	fireball_layer(fx,c,r,1,0.55)
	fx.sparks(c,8,11.0,Vector3.UP*0.7,0.7,BattleEffects.NORMAL,1.8)
	debris_arcs(fx,c,r,5,[BattleEffects.METAL,BattleEffects.SOOT],1,not water)
	smoke_handoff(fx,c,r,3,Color(DARK_GREY.darkened(0.3),0.84),0.55,3.2)
	fx.shake(c,0.45)
	if water:
		fx.water_strike(g,0.7)
	else:
		shockwave(fx,g,r,BattleEffects.DUST,4)
		scorch(fx,g,r,5.0,0.6,BattleEffects.OPTIONAL)
		fx.mark(g,1.0*r,Remains.SCORCH)

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
# outward and hangs, chunks of slab bouncing, and a smouldering interior. R = 2.6 m per unit scale.
static func concrete_collapse(fx, pos:Vector3, scale:float) -> void:
	var rng:RandomNumberGenerator=fx.rng
	var r:=2.6*scale
	var c:=Vector3(pos.x,0.9+0.2*r,pos.z)
	var g:=Vector3(pos.x,BattleEffects.FLOOR,pos.z)
	fx._boom(scale)
	core_flash(fx,c,g,r,Color(1.0,0.86,0.6))
	fireball_layer(fx,c,r,1,0.6)
	debris_arcs(fx,c,r,int(round(8*scale)),[RUBBLE,CONCRETE.darkened(0.15)],2,true)
	for n in 6:
		fx.smoke(c+fx._jitter(0.5*r,0.15*r),Vector3(0,rng.randf_range(0.3,0.6)*r,0)+fx._jitter(0.25*r,0.0),1.1*r,rng.randf_range(2.2,2.7)*r,rng.randf_range(4.0,5.5),Color(CONCRETE,0.8),1.0,0.15*r,0.05+n*0.06,BattleEffects.ESSENTIAL if n<3 else BattleEffects.NORMAL)
	shockwave(fx,g,r,CONCRETE,8)
	scorch(fx,g,r,7.0,0.55,BattleEffects.ESSENTIAL)
	fx.mark(g,0.8*r,Remains.SCORCH)
	heat(fx,g,r,2.5)
	fx.sparks(c,8,10.0,Vector3.UP*0.7,0.6,BattleEffects.OPTIONAL,1.8)
	fx.shake(c,0.8*scale)
	fx.cue(rng.randf_range(0.4,0.7),Callable(fx,"_cook_off").bind(c+fx._jitter(0.6,0.0)))
	fx.add_emitter(g,9.0,0.7*scale,false)

# Low ring of dust shoved outward along the ground, without an overpressure ring (wire, nets, berms).
static func _dust_skirt(fx, g:Vector3, scale:float, col:Color) -> void:
	shockwave(fx,g,2.2*scale,col,8,BattleEffects.NORMAL,false)

static func _splinters(fx, pos:Vector3, scale:float, col:Color) -> void:
	var rng:RandomNumberGenerator=fx.rng
	for n in int(round(3+5*scale)):
		fx.debris(pos,fx._jitter(2.5*scale+0.5,0.0)+Vector3(0,rng.randf_range(2.5,5.5),0),rng.randf_range(0.1,0.22),rng.randf_range(1.2,1.8),col,true,false,BattleEffects.OPTIONAL)
