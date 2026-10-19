class_name UnitAnimation
extends RefCounted

static func state(u:Dictionary,sim,moving:bool=false) -> String:
	if u.hp<=0:return "DESTROYED"
	if u.kind=="fpv_drone":return FPV_STATES.get(u.state,"HOMING") # Autonomous munition: no orders.
	# Building states (garrison.gd, structure_damage.gd) outrank the transient
	# combat cues, which would otherwise hide them behind CYCLING/HOLDING.
	var transit:String=u.get("garrison_transit","")
	if transit!="":return "ENTERING" if transit=="IN" else "EXITING"
	if u.recovering:return "RECOVERING"
	if not u.orders.is_empty() and u.orders[0].mode=="retreat":return "WITHDRAWING"
	if u.suppression>0.6:return "PINNED"
	if int(u.get("garrison",-1))>=0:return "GARRISON FIRING" if sim.time-float(u.get("last_shot",-100))<1.5 else "GARRISONED"
	if u.has("bombard") and u.orders.is_empty():return "BOMBARDING"
	if sim.time-float(u.get("last_hit",-100))<0.5:return "BRACING"
	if sim.time-float(u.get("last_shot",-100))<0.24:return "FIRING"
	if u.state=="AIMING":return "ACQUIRING"
	if u.target>=0 and u.cooldown>0:return "CYCLING"
	if u.blocked_time>0:return "YIELDING"
	if moving:return "ADVANCING" if not u.orders.is_empty() and u.orders[0].mode=="attack_move" else "MARCHING"
	if u.kind=="drone":return "OBSERVING"
	return "HOLDING"

const TURRET:=0
const SOLDIER:=1
const ROTOR:=2
const PROP:=3
const WHEEL:=4
const OTHER:=5
const SIDES:Array[int]=[-1,1]
const FPV_STATES:={"DIVING":"DIVING","ACQUIRING":"LINING UP"}

# Writing an unchanged transform still re-notifies the whole joint subtree (and
# re-sends every mesh instance transform), so settled joints skip the write.
static func set_position(node:Node3D,value:Vector3) -> void:
	if node.position!=value:node.position=value

static func set_position_axis(node:Node3D,axis:int,value:float) -> void:
	var position:=node.position
	if position[axis]==value:return
	position[axis]=value
	node.position=position

static func set_rotation_axis(node:Node3D,axis:int,value:float) -> void:
	var rotation:=node.rotation
	if rotation[axis]==value:return
	rotation[axis]=value
	node.rotation=rotation

static func set_basis(node:Node3D,value:Basis) -> void:
	if node.basis!=value:node.basis=value

# Animated joints, classified once per model (children at first pose, as before):
# [kind, node, extra] where extra is the gun (turret) or soldier index, plus a
# lazily resolved soldier rig. Avoids per-frame name strings and node lookups.
static func parts(model:Node3D) -> Array:
	if model.has_meta("animated_parts"):return model.get_meta("animated_parts")
	var entries:Array=[]
	var children:Array=model.get_children()
	# The FPV strike drone nests the scout airframe in a scaled child.
	var airframe:=model.get_node_or_null("Airframe")
	if airframe!=null:children.append_array(airframe.get_children())
	for part in children:
		var part_name:=str(part.name)
		if part_name=="Turret":entries.append([TURRET,part,part.get_node_or_null("Gun"),null])
		elif part_name.begins_with("Soldier"):entries.append([SOLDIER,part,int(part_name.trim_prefix("Soldier")),null])
		elif part_name=="Rotor":entries.append([ROTOR,part,null,null])
		elif part_name.begins_with("Prop"):entries.append([PROP,part,null,null])
		elif part_name.begins_with("Wheel"):entries.append([WHEEL,part,null,null])
	model.set_meta("animated_parts",entries)
	return entries

# Pose is driven by simulation time and actual displacement, never wall time.
static func pose(model:Node3D,u:Dictionary,sim,dt:float) -> void:
	if dt<=0:return
	var previous:Vector2=model.get_meta("previous",u.pos)
	var displacement:float=previous.distance_to(u.pos)
	var travel:float=lerpf(float(model.get_meta("travel",0.0)),minf(1,displacement/maxf(dt*2,0.001)),minf(1,dt*9))
	model.set_meta("travel",travel)
	var moving:bool=travel>0.05
	u["visual_state"]=state(u,sim,moving)
	model.set_meta("previous",u.pos)
	var phase:float=model.get_meta("phase",0.0)+displacement*3.0
	model.set_meta("phase",phase)
	var recoil:=maxf(0,1.0-(sim.time-float(u.get("last_shot",-100)))/0.24)
	var positions:Array=model.get_meta("display_members",[])
	var center:Vector2=model.get_meta("display_pos",u.pos)
	var inverse_heading:=Basis(Vector3.UP,model.rotation.y).inverse()
	var autonomy:bool=sim.scenario.get("autonomy",false)
	for entry in parts(model):
		var kind:int=entry[0]
		var part:Node3D=entry[1]
		if kind==TURRET:
			var target:Dictionary=sim.get_unit(u.target)
			var aiming:bool=sim.alive(target) and sim.contact_known(u,target)
			var angle:=0.0
			if aiming:
				var direction:Vector2=target.pos-u.pos
				angle=atan2(-direction.x,-direction.y)-model.rotation.y
			set_rotation_axis(part,1,lerp_angle(part.rotation.y,angle,minf(1,dt*5)))
			set_position_axis(part,1,-recoil*0.035)
			if entry[2]!=null:set_position_axis(entry[2],2,recoil*0.16)
		elif kind==SOLDIER:
			var index:int=entry[2]
			if index>=u.members.size():
				part.visible=false
				continue
			var member:Dictionary=u.members[index]
			var member_pos:Vector2=positions[index] if index<positions.size() else member.pos
			var wound:String=member.get("wound","HEALTHY")
			var down:bool=wound=="SEVERE" or wound=="KIA"
			# Garrisoned soldiers are inside the building: hidden, marked by the HUD.
			# The fallen stay on the ground (SEVERE wounded and KIA bodies).
			part.visible=(member.hp>0 or down) and u.get("garrison",-1)<0 and not member.get("indoors",false)
			if part.has_meta("corpse")!=(wound=="KIA") and part.visible:mark_corpse(part,wound=="KIA")
			if not part.visible:continue
			var member_moving:bool=member.travel>0.001
			var reload:bool=member.get("reload_until",0.0)>sim.time
			var local:Vector3=inverse_heading*Vector3(member_pos.x-center.x,0,member_pos.y-center.y)
			# Soldiers inside a dug trench stand in it: drop the figure below ground level.
			local.y=-0.55 if member.get("in_trench",false) else 0.0
			set_position(part,local)
			set_rotation_axis(part,1,lerp_angle(part.rotation.y,atan2(-member.facing.x,-member.facing.y)-model.rotation.y,minf(1,dt*9)))
			var member_recoil:=maxf(0,1-(sim.time-member.last_shot)/0.24)
			var reaction:=maxf(0,1-(sim.time-member.last_hit)/0.5)
			var member_aiming:bool=member.target>=0
			if entry[3]==null:
				var legs:Array=[]
				for leg_name in ["LegL","LegR"]:
					var leg:Node3D=part.get_node(leg_name)
					var knee:Node3D=leg.get_node_or_null("Knee")
					legs.append([leg,knee,knee.get_node_or_null("Foot") if knee!=null else null])
				entry[3]=[part.get_node("Upper"),part.get_node("Upper/Weapon"),legs[0],legs[1]]
			var rig:Array=entry[3]
			var body:Node3D=rig[0]
			if down:
				pose_fallen(rig,member,wound=="KIA",sim.time,dt)
				continue
			var prone:bool=member.get("posture","")=="PRONE"
			# A lightly wounded soldier hunches over the wound and walks low.
			var hurt:bool=wound=="LIGHT"
			var crouched:bool=member.get("posture","")=="CROUCHED" or (hurt and member_moving)
			set_rotation_axis(body,2,sin(index*1.7)*0.07*reaction+(0.12 if hurt and not prone else 0.0))
			set_position_axis(body,1,lerpf(body.position.y,0.24 if prone else (-0.18 if crouched or maxf(member.suppression,u.suppression)>0.6 else (-0.07 if hurt else 0.0)),minf(1,dt*10)))
			set_position_axis(body,2,lerpf(body.position.z,0.75 if prone else 0.0,minf(1,dt*10)))
			set_rotation_axis(body,0,lerpf(body.rotation.x,-PI/2 if prone else ((-0.12 if member_moving else 0.0)-(0.22 if hurt else 0.0)-member_recoil*0.09),minf(1,dt*10)))
			var weapon:Node3D=rig[1]
			set_rotation_axis(weapon,0,lerpf(weapon.rotation.x,PI/2 if prone else (-0.65 if reload else (0.0 if member_aiming else (-0.24 if member_moving else -0.12))),minf(1,dt*6)))
			set_position_axis(weapon,2,member_recoil*0.035)
			for side in SIDES:
				var joints:Array=rig[2 if side<0 else 3]
				var leg:Node3D=joints[0]
				if autonomy:
					if prone:
						if leg.scale!=Vector3.ONE:leg.scale=Vector3.ONE
						if leg.rotation!=Vector3(-PI/2,0,0):leg.rotation=Vector3(-PI/2,0,0)
						set_basis(joints[1],Basis.IDENTITY)
						set_basis(joints[2],Basis.IDENTITY)
						set_position(leg,Vector3(side*0.095,0.3,0.1))
					else:
						if leg.scale!=Vector3.ONE:leg.scale=Vector3.ONE
						plant_foot(leg,member,side,model.rotation.y+part.rotation.y,member_moving,crouched,member_pos,joints[1],joints[2])
				else:
					# Restore the standing hip after a lying pose (treated casualty).
					if leg.has_meta("rest"):
						set_position(leg,leg.get_meta("rest"))
						set_rotation_axis(leg,1,0.0)
						set_rotation_axis(leg,2,0.0)
					# A limp: the wounded side barely swings.
					var stride:float=0.42*(0.45 if hurt and side>0 else 1.0)
					set_rotation_axis(leg,0,sin(member.phase)*stride*side if member_moving else (0.22*side if member_aiming else 0.0))

		elif kind==ROTOR:set_rotation_axis(part,1,sim.time*45)
		elif kind==PROP:set_rotation_axis(part,1,sim.time*(110.0 if u.kind=="fpv_drone" else 75.0))
		elif kind==WHEEL:set_rotation_axis(part,0,phase)
	if u.kind=="fpv_drone":pose_fpv(model,u,sim,dt,displacement,moving)
	elif u.kind=="helo" or u.kind=="drone":
		set_rotation_axis(model,0,lerpf(model.rotation.x,-0.07 if moving else 0.0,minf(1,dt*4)))
		set_position_axis(model,1,sin(sim.time*2+u.id)*0.08)
	elif u.kind=="boat":
		set_rotation_axis(model,2,sin(sim.time*1.4+u.id)*0.012)
	else:
		set_position_axis(model,1,0.0) # Flat ground: no synthetic chassis vibration.

# FPV strike drone: a twitchy racing-quad buzz (fast small roll/pitch/bob),
# nose-forward while homing, level while lining up, and nose-down along the
# flight path while diving (pitch follows the measured descent of u.altitude).
static func pose_fpv(model:Node3D,u:Dictionary,sim,dt:float,displacement:float,moving:bool) -> void:
	var altitude:float=float(u.get("altitude",sim.definitions[u.kind].altitude))
	var descent:float=maxf(0.0,float(model.get_meta("fpv_altitude",altitude))-altitude)
	model.set_meta("fpv_altitude",altitude)
	var diving:bool=u.state=="DIVING"
	var pitch:float=model.get_meta("fpv_target",0.0)
	# The sim moves at 30 Hz: hold the dive angle on render frames between ticks.
	if diving:
		if displacement>0.0 or descent>0.0:pitch=-clampf(0.35+atan2(descent,maxf(displacement,0.001)),0.35,1.25)
	else:pitch=-0.28 if moving and u.state!="ACQUIRING" else 0.0
	model.set_meta("fpv_target",pitch)
	var t:float=sim.time+u.id*0.37
	var jitter:=0.4 if diving else 1.0 # Committed to the dive: steadier.
	var attitude:=lerpf(float(model.get_meta("fpv_pitch",0.0)),pitch,minf(1,dt*8))
	model.set_meta("fpv_pitch",attitude)
	set_rotation_axis(model,0,attitude+(sin(t*17.0)*0.03+sin(t*41.0)*0.012)*jitter)
	set_rotation_axis(model,2,(sin(t*11.0)*0.06+sin(t*29.0)*0.025)*jitter)
	set_position_axis(model,1,(sin(t*7.0)*0.05+sin(t*23.0)*0.015)*jitter)

# SEVERE: lying, breathing, weapon dropped, legs working when crawling or
# dragged. KIA: lying still, rolled further, no breathing (darkened separately).
static func pose_fallen(rig:Array,member:Dictionary,dead:bool,now:float,dt:float) -> void:
	var body:Node3D=rig[0]
	var weapon:Node3D=rig[1]
	var blend:=minf(1,dt*6)
	var breath:float=0.0 if dead else sin(now*2.6+member.index)*0.012
	set_position_axis(body,1,lerpf(body.position.y,0.2,blend)+breath*blend)
	set_position_axis(body,2,lerpf(body.position.z,0.75,blend))
	set_rotation_axis(body,0,lerpf(body.rotation.x,-PI/2,blend))
	set_rotation_axis(body,2,lerpf(body.rotation.z,0.55 if dead else 0.22,blend))
	set_rotation_axis(weapon,0,lerpf(weapon.rotation.x,PI/2,blend))
	set_position_axis(weapon,2,0.0)
	var crawl:bool=not dead and member.get("travel",0.0)>0.0005
	for side in SIDES:
		var joints:Array=rig[2 if side<0 else 3]
		var leg:Node3D=joints[0]
		if not leg.has_meta("rest"):leg.set_meta("rest",leg.position)
		if leg.scale!=Vector3.ONE:leg.scale=Vector3.ONE
		var kick:float=sin(now*5.0+(PI if side>0 else 0.0))*0.3 if crawl else (0.08*side if dead else 0.0)
		var lying:=Vector3(-PI/2+kick,0.0,0.18*side if dead else 0.0)
		if leg.rotation!=lying:leg.rotation=lying
		if joints[1]!=null:set_basis(joints[1],Basis.IDENTITY)
		if joints[2]!=null:set_basis(joints[2],Basis.IDENTITY)
		set_position(leg,Vector3(side*0.095,0.3,0.1))

# Bodies are slightly darker: one shared vertex-colour material replaces the
# miniature paint on a corpse's meshes (no extra draw pass), restored if needed.
static var corpse_material:StandardMaterial3D
static func mark_corpse(part:Node3D,dead:bool) -> void:
	if dead and corpse_material==null:
		corpse_material=StandardMaterial3D.new()
		corpse_material.vertex_color_use_as_albedo=true
		corpse_material.albedo_color=Color(0.58,0.56,0.54)
		corpse_material.roughness=1.0
		corpse_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	for mesh in part.find_children("*","MeshInstance3D",true,false):
		if dead:
			mesh.set_meta("live_material",mesh.material_override)
			mesh.material_override=corpse_material
		elif mesh.has_meta("live_material"):
			mesh.material_override=mesh.get_meta("live_material")
			mesh.remove_meta("live_material")
	if dead:part.set_meta("corpse",true)
	else:part.remove_meta("corpse")

static func plant_foot(leg:Node3D,member:Dictionary,side:int,yaw:float,moving:bool,crouched:bool=false,display_pos:Vector2=Vector2(INF,INF),knee:Node3D=null,foot_node:Node3D=null) -> void:
	var member_pos:Vector2=member.pos if not display_pos.is_finite() else display_pos
	var phase:float=fposmod(member.phase+(PI if side>0 else 0.0),TAU)
	var swing:bool=moving and phase>=PI
	var forward:Vector2=member.facing
	var rest:Vector2=member_pos-forward.orthogonal()*side*0.13
	var target:Vector2=rest+forward*0.24
	if not leg.has_meta("foot_world"):leg.set_meta("foot_world",rest)
	var foot:Vector2=leg.get_meta("foot_world")
	var lift:=0.0
	if swing:
		var t:float=(phase-PI)/PI
		if not leg.get_meta("swing",false):leg.set_meta("swing_start",foot)
		foot=(leg.get_meta("swing_start",foot) as Vector2).lerp(target,smoothstep(0.0,1.0,t))
		lift=sin(t*PI)*0.12
	elif foot.distance_to(member_pos)>0.55:
		# Reset after teleports/abrupt turns rather than stretching the leg.
		foot=rest
	leg.set_meta("foot_world",foot)
	leg.set_meta("swing",swing)
	var local:Vector3=Basis(Vector3.UP,yaw).inverse()*Vector3(foot.x-member_pos.x,lift,foot.y-member_pos.y)
	if knee==null:knee=leg.get_node_or_null("Knee")
	if knee!=null:
		if foot_node==null:foot_node=knee.get_node("Foot")
		var hip:=Vector3(side*0.095,0.47 if crouched else 0.65,0)
		var ankle:=local+Vector3(0,0.10,0.05)
		var horizontal:=Vector2(ankle.x-hip.x,ankle.z-hip.z).length()
		hip.y=minf(hip.y,ankle.y+sqrt(maxf(0.01,0.549*0.549-horizontal*horizontal)))
		var delta:=ankle-hip
		var distance:=clampf(delta.length(),0.08,0.549)
		var direction:=delta.normalized()
		var along:float=(0.27*0.27+distance*distance-0.28*0.28)/(2.0*distance)
		var bend:Vector3=Vector3.FORWARD-direction*Vector3.FORWARD.dot(direction)
		if bend.length_squared()<0.001:bend=Vector3.RIGHT
		var joint:=hip+direction*along+bend.normalized()*sqrt(maxf(0,0.27*0.27-along*along))
		set_position(leg,hip)
		set_basis(leg,Basis(Quaternion(Vector3.DOWN,(joint-hip).normalized())))
		var lower:=Basis(Quaternion(Vector3.DOWN,(ankle-joint).normalized()))
		set_basis(knee,leg.basis.inverse()*lower)
		set_basis(foot_node,lower.inverse())
		return
	var anchor:=Vector3(side*0.035,-0.65,-0.13 if side<0 else 0.09)
	var angle:float=clampf(atan2(-local.z,0.65)-atan2(-anchor.z,0.65),-0.55,0.55)
	set_rotation_axis(leg,0,angle)
	var placed:=local-leg.basis*anchor
	placed.y+=absf(sin(angle))*0.125 # Keep the pitched boot sole above the ground.
	set_position(leg,placed)
