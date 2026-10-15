class_name UnitAnimation
extends RefCounted

static func state(u:Dictionary,sim,moving:bool=false) -> String:
	if u.hp<=0:return "DESTROYED"
	if u.recovering:return "RECOVERING"
	if not u.orders.is_empty() and u.orders[0].mode=="retreat":return "WITHDRAWING"
	if u.suppression>0.6:return "PINNED"
	if sim.time-float(u.get("last_hit",-100))<0.5:return "BRACING"
	if sim.time-float(u.get("last_shot",-100))<0.24:return "FIRING"
	if u.state=="AIMING":return "ACQUIRING"
	if u.target>=0 and u.cooldown>0:return "CYCLING"
	if u.blocked_time>0:return "YIELDING"
	if moving:return "ADVANCING" if not u.orders.is_empty() and u.orders[0].mode=="attack_move" else "MARCHING"
	if u.kind=="drone":return "OBSERVING"
	return "HOLDING"

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
	if not model.has_meta("animated_parts"):
		model.set_meta("animated_parts",model.get_children())
	var positions:Array=model.get_meta("display_members",[])
	var center:Vector2=model.get_meta("display_pos",u.pos)
	var inverse_heading:=Basis(Vector3.UP,model.rotation.y).inverse()
	for part in model.get_meta("animated_parts"):
		if part.name=="Turret":
			var target:Dictionary=sim.get_unit(u.target)
			var aiming:bool=sim.alive(target) and sim.contact_known(u,target)
			var angle:=0.0
			if aiming:
				var direction:Vector2=target.pos-u.pos
				angle=atan2(-direction.x,-direction.y)-model.rotation.y
			part.rotation.y=lerp_angle(part.rotation.y,angle,minf(1,dt*5))
			part.position.y=-recoil*0.035
			if part.has_node("Gun"):part.get_node("Gun").position.z=recoil*0.16
		elif str(part.name).begins_with("Soldier"):
			var index:=int(str(part.name).trim_prefix("Soldier"))
			if index>=u.members.size():
				part.visible=false
				continue
			var member:Dictionary=u.members[index]
			var member_pos:Vector2=positions[index] if index<positions.size() else member.pos
			# Garrisoned soldiers are inside the building: hidden, marked by the HUD.
			part.visible=member.hp>0 and u.get("garrison",-1)<0 and not member.get("indoors",false)
			if not part.visible:continue
			var member_moving:bool=member.travel>0.001
			var reload:bool=member.get("reload_until",0.0)>sim.time
			var local:Vector3=inverse_heading*Vector3(member_pos.x-center.x,0,member_pos.y-center.y)
			# Soldiers inside a dug trench stand in it: drop the figure below ground level.
			local.y=-0.55 if member.get("in_trench",false) else 0.0
			part.position=local
			part.rotation.y=lerp_angle(part.rotation.y,atan2(-member.facing.x,-member.facing.y)-model.rotation.y,minf(1,dt*9))
			var member_recoil:=maxf(0,1-(sim.time-member.last_shot)/0.24)
			var reaction:=maxf(0,1-(sim.time-member.last_hit)/0.5)
			var member_aiming:bool=member.target>=0
			if not part.has_meta("rig"):
				part.set_meta("rig",[part.get_node("Upper"),part.get_node("Upper/Weapon"),part.get_node("LegL"),part.get_node("LegR")])
			var rig:Array=part.get_meta("rig")
			var body:Node3D=rig[0]
			var prone:bool=member.get("posture","")=="PRONE"
			var crouched:bool=member.get("posture","")=="CROUCHED"
			body.rotation.z=sin(index*1.7)*0.07*reaction
			body.position.y=lerpf(body.position.y,0.24 if prone else (-0.18 if crouched or maxf(member.suppression,u.suppression)>0.6 else 0.0),minf(1,dt*10))
			body.position.z=lerpf(body.position.z,0.75 if prone else 0.0,minf(1,dt*10))
			body.rotation.x=lerpf(body.rotation.x,-PI/2 if prone else ((-0.12 if member_moving else 0.0)-member_recoil*0.09),minf(1,dt*10))
			var weapon:Node3D=rig[1]
			weapon.rotation.x=lerpf(weapon.rotation.x,PI/2 if prone else (-0.65 if reload else (0.0 if member_aiming else (-0.24 if member_moving else -0.12))),minf(1,dt*6))
			weapon.position.z=member_recoil*0.035
			for side in [-1,1]:
				var leg:Node3D=rig[2 if side<0 else 3]
				if sim.scenario.get("autonomy",false):
					if prone:
						leg.scale=Vector3.ONE
						leg.rotation=Vector3(-PI/2,0,0)
						leg.get_node("Knee").basis=Basis.IDENTITY
						leg.get_node("Knee/Foot").basis=Basis.IDENTITY
						leg.position=Vector3(side*0.095,0.3,0.1)
					else:
						leg.scale=Vector3.ONE
						plant_foot(leg,member,side,model.rotation.y+part.rotation.y,member_moving,crouched,member_pos)
				else:leg.rotation.x=sin(member.phase)*0.42*side if member_moving else (0.22*side if member_aiming else 0.0)

		elif part.name=="Rotor":part.rotation.y=sim.time*45
		elif str(part.name).begins_with("Prop"):part.rotation.y=sim.time*75
		elif str(part.name).begins_with("Wheel"):part.rotation.x=phase
	if u.kind=="helo" or u.kind=="drone":
		model.rotation.x=lerpf(model.rotation.x,-0.07 if moving else 0.0,minf(1,dt*4))
		model.position.y=sin(sim.time*2+u.id)*0.08
	elif u.kind=="boat":
		model.rotation.z=sin(sim.time*1.4+u.id)*0.012
	else:
		model.position.y=0.0 # Flat ground: no synthetic chassis vibration.

static func plant_foot(leg:Node3D,member:Dictionary,side:int,yaw:float,moving:bool,crouched:bool=false,display_pos:Vector2=Vector2(INF,INF)) -> void:
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
	if leg.has_node("Knee"):
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
		leg.position=hip
		leg.basis=Basis(Quaternion(Vector3.DOWN,(joint-hip).normalized()))
		var knee:Node3D=leg.get_node("Knee")
		var lower:=Basis(Quaternion(Vector3.DOWN,(ankle-joint).normalized()))
		knee.basis=leg.basis.inverse()*lower
		knee.get_node("Foot").basis=lower.inverse()
		return
	var anchor:=Vector3(side*0.035,-0.65,-0.13 if side<0 else 0.09)
	var angle:float=clampf(atan2(-local.z,0.65)-atan2(-anchor.z,0.65),-0.55,0.55)
	leg.rotation.x=angle
	leg.position=local-leg.basis*anchor
	leg.position.y+=absf(sin(angle))*0.125 # Keep the pitched boot sole above the ground.
