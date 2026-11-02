class_name InfantryCoordination
extends RefCounted

# Local, bounded cooperation. A stationary body is not evidence of covering fire.
# These roles use current known contacts and the same weapon ray as actual fire.
static func covering_weapon(u:Dictionary,member:Dictionary,sim,threat:Dictionary)->String:
	var weapon:String=sim.section_weapon(u,member)
	if weapon=="atgm" and not threat.get("members",[]).is_empty() and not sim.Garrison.inside(threat):weapon="rifle"
	return weapon

static func can_cover(u:Dictionary,member:Dictionary,sim,threat:Dictionary)->bool:
	if not sim.alive(threat) or threat.team==u.team or not sim.contact_known(u,threat):return false
	if not sim.auto_target_ok(u,threat):return false
	var weapon:=covering_weapon(u,member,sim,threat)
	if not sim.Infantry.ready_to_cover(u,member,sim.time,weapon):return false
	if sim.time<float(member.get("hull_yield",{}).get("until",-INF)):return false
	if not sim.engagement_allowed(u,int(threat.id)):return false
	# Do not promise fire that this actor owes to a different player target.
	# A blocked or unknown order still permits useful local covering fire.
	var ordered:Dictionary=sim.get_unit(sim.ordered_target(u))
	if not ordered.is_empty() and ordered.id!=threat.id and sim.alive(ordered) and ordered.team!=u.team and sim.contact_known(u,ordered) and sim.engagement_allowed(u,int(ordered.id)):
		if sim.weapon_reaches(covering_weapon(u,member,sim,ordered),member.pos,ordered,sim.SOLDIER_CHECKS):return false
	# An urgent threat which just interrupted cover must not be forgotten by
	# the next role review while the same soldier is still engaging it.
	var current:Dictionary=sim.get_unit(int(member.get("target",-1)))
	if sim.alive(current) and current.team!=u.team and sim.urgent_target_rank(u,current)>sim.urgent_target_rank(u,threat) and sim.contact_known(u,current) and sim.engagement_allowed(u,int(current.id)):
		if sim.weapon_reaches(weapon,member.pos,current,sim.SOLDIER_CHECKS):return false
	return sim.weapon_reaches(weapon,member.pos,threat,sim.SOLDIER_CHECKS)

# The firing executor uses the same reciprocal role as movement. A covering
# label alone must never choose an unrelated weapon or keep an obsolete task.
static func covering_target(u:Dictionary,member:Dictionary,sim)->Dictionary:
	var mover_id:=str(member.get("cover_for",""))
	if mover_id.is_empty():return {}
	var mover:Dictionary=sim.Infantry.member_by_id(u,mover_id)
	if mover.is_empty() or mover.hp<=0 or str(mover.get("covered_by",""))!=str(member.member_id):return {}
	var throwing:bool=sim.Infantry.task_busy(mover) and mover.get("task_kind","")=="throw"
	if mover.get("cover_phase","") not in ["SEEKING","SETTLING"] and not throwing:return {}
	var threat:Dictionary=sim.get_unit(int(mover.get("support_threat",-1)))
	return threat if can_cover(u,member,sim,threat) else {}

static func release_support(u:Dictionary,member:Dictionary,sim,reason:String)->void:
	var mover:Dictionary=sim.Infantry.member_by_id(u,str(member.get("cover_for","")))
	if not mover.is_empty() and str(mover.get("covered_by",""))==str(member.member_id):
		mover.erase("covered_by")
		if mover.get("coord_reason","")!="defensive_shelter":mover["coord_reason"]="cover_lost"
	member.erase("cover_for")
	if member.get("coord_reason","")=="covering_teammate":member.erase("coord_reason")
	var action:Dictionary=sim.actions.active(u,"member:%s:support"%member.get("member_id",member.index))
	if not action.is_empty():sim.actions.cancel(u,action,sim.time,reason)

static func _partner(u:Dictionary,mover:Dictionary,sim,threat:Dictionary)->Dictionary:
	for peer in u.members:
		if peer.member_id==mover.member_id or not str(peer.get("cover_for","")).is_empty():continue
		if can_cover(u,peer,sim,threat):return peer
	return {}

static func _assign(u:Dictionary,mover:Dictionary,partner:Dictionary,sim,threat:Dictionary)->void:
	mover["covered_by"]=str(partner.member_id)
	mover["support_threat"]=int(threat.id)
	mover["coord_reason"]="covered_bound"
	partner["cover_for"]=str(mover.member_id)
	partner["coord_reason"]="covering_teammate"
	sim.actions.observe_existing(u,"member:%s:support"%partner.member_id,"cover_partner",sim.time,
		{"member":str(mover.member_id),"threat":int(threat.id)},"covering_teammate")

static func clear(u:Dictionary,sim)->void:
	for member in u.members:
		member.erase("cover_for");member.erase("covered_by");member.erase("support_threat");member.erase("coord_reason")
		var action:Dictionary=sim.actions.active(u,"member:%s:support"%member.get("member_id",member.index))
		if not action.is_empty():sim.actions.cancel(u,action,sim.time,"support_released")

# Review is O(section members squared), with at most three weapon probes per
# candidate (explicit, urgent, support). A lost supporter is replaced; an
# already exposed mover finishes its short validated route to shelter instead
# of freezing in the street.
static func review(u:Dictionary,sim)->void:
	if u.members.is_empty():return
	for member in u.members:member.erase("cover_for")
	for mover in u.members:
		var throwing:bool=sim.Infantry.task_busy(mover) and mover.get("task_kind","")=="throw"
		if mover.hp<=0 or (mover.get("cover_phase","") not in ["SEEKING","SETTLING"] and not throwing):
			mover.erase("covered_by");mover.erase("support_threat")
			if mover.get("coord_reason","") in ["covered_bound","cover_lost","emergency_bound","defensive_shelter"]:mover.erase("coord_reason")
			continue
		if not mover.has("support_threat"):continue
		var threat:Dictionary=sim.get_unit(int(mover.support_threat))
		var peer:Dictionary=sim.Infantry.member_by_id(u,str(mover.get("covered_by","")))
		if peer.is_empty() or not str(peer.get("cover_for","")).is_empty() or not can_cover(u,peer,sim,threat):
			peer=_partner(u,mover,sim,threat)
		if not peer.is_empty():_assign(u,mover,peer,sim,threat)
		else:
			mover.erase("covered_by")
			if mover.get("coord_reason","")!="defensive_shelter":mover["coord_reason"]="cover_lost"
	for member in u.members:
		if not str(member.get("cover_for","")).is_empty():continue
		if member.get("coord_reason","")=="covering_teammate":member.erase("coord_reason")
		var action:Dictionary=sim.actions.active(u,"member:%s:support"%member.get("member_id",member.index))
		if not action.is_empty():sim.actions.complete(u,action,sim.time,"support_released")

# Cover supplies a body-clear, bounded route. An observed weapon the section
# cannot engage must not make it wait in that weapon's lane until the first
# casualty. This exception only permits reaching an actual screened shelter;
# it neither invents a covering partner nor permits an exposed advance/flank.
static func _defensive_shelter(u:Dictionary,member:Dictionary,sim,threat:Dictionary,slot:Dictionary)->bool:
	if not sim.contact_known(u,threat) or sim.effective_unit(u,str(threat.kind)):return false
	if not slot.get("screened",false) or not sim.terrain.cover(slot.pos):return false
	if slot.pos.distance_to(u.pos)>sim.Infantry.Cover.LEASH or slot.get("path",[]).is_empty():return false
	if not sim.Infantry.Cover.sees(sim,threat,member.pos) or sim.Infantry.Cover.sees(sim,threat,slot.pos):return false
	return true

static func begin_bound(u:Dictionary,member:Dictionary,sim,threat:Dictionary,slot:Dictionary)->bool:
	if threat.is_empty():return true
	var peer:=_partner(u,member,sim,threat)
	if not peer.is_empty():
		_assign(u,member,peer,sim,threat)
		return true
	if _defensive_shelter(u,member,sim,threat,slot):
		member.erase("covered_by")
		member["coord_reason"]="defensive_shelter"
		member["support_threat"]=int(threat.id)
		return true
	# Immediate survival does not require a teammate who no longer exists. The
	# exception is explicit in diagnostics, and cannot justify an ordinary flank.
	var incoming:bool=sim.time-float(u.get("fired_on",-100.0))<2.0 or sim.time-float(member.get("last_hit",-100.0))<2.0
	var exposed:bool=not sim.terrain.cover(member.pos) or (not sim.can_fire(u,threat) and not slot.get("screened",false))
	if incoming and exposed and sim.terrain.cover(slot.pos):
		member["coord_reason"]="emergency_bound"
		member["support_threat"]=int(threat.id)
		return true
	member["coord_reason"]="waiting_for_cover"
	return false

static func status(u:Dictionary)->String:
	var covering:=0
	var moving:=0
	var unsupported:=0
	var throwing:=0
	var defensive:=false
	for member in u.members:
		if member.hp<=0:continue
		if not str(member.get("cover_for","")).is_empty():covering+=1
		if member.get("task_kind","")=="throw":throwing+=1
		if member.get("cover_phase","") in ["SEEKING","SETTLING"]:
			moving+=1
			if str(member.get("covered_by","")).is_empty():unsupported+=1
			if member.get("coord_reason","")=="defensive_shelter":defensive=true
	if covering>0:return "%d covering · %d throwing"%[covering,throwing] if throwing>0 else "%d covering · %d moving"%[covering,moving]
	if defensive:return "Seeking shelter · no effective covering weapon"
	if unsupported>0:return "Seeking shelter · cover unavailable"
	return ""
