class_name TacticalContext
extends RefCounted

# Observations contain copied facts, never references to live target units.
const MAX_AGE:=30.0
const MAX_TEAMS:=8
const TEAM_CONTACTS:=256
const MAX_OBSERVERS:=256
const LOCAL_CONTACTS:=32

var teams:Dictionary={}
var observers:Dictionary={}

func observe(team:int,target_id:int,kind:String,pos:Vector2,now:float,observer_id:int=-1,upload:bool=true)->void:
	if team<0 or target_id<0 or not is_finite(now) or not pos.is_finite():return
	var fact:Dictionary={"id":target_id,"kind":kind,"pos":pos,"observed_at":now,"observer_id":observer_id,"source":"sensor"}
	if observer_id>=0:
		if not observers.has(observer_id) or int(observers[observer_id].team)!=team:
			observers[observer_id]={"team":team,"contacts":{}}
		_store(observers[observer_id].contacts,fact,LOCAL_CONTACTS)
		_trim_groups(observers,MAX_OBSERVERS,true)
	if upload:
		if not teams.has(team):teams[team]={}
		_store(teams[team],fact,TEAM_CONTACTS)
		_trim_groups(teams,MAX_TEAMS,false)

func contact_for(u:Dictionary,target_id:int,now:float,connected:bool=true)->Dictionary:
	if connected:return team_contact(int(u.get("team",-1)),target_id,now)
	return local_for(int(u.get("id",-1)),target_id,now,int(u.get("team",-1)))

func team_contact(team:int,target_id:int,now:float)->Dictionary:
	return _read(teams.get(team,{}).get(target_id,{}),now)

func local_for(observer_id:int,target_id:int,now:float,team:int=-1)->Dictionary:
	var memory:Dictionary=observers.get(observer_id,{})
	if memory.is_empty() or (team>=0 and int(memory.team)!=team):return {}
	return _read(memory.contacts.get(target_id,{}),now)

func team_snapshot(team:int,now:float)->Array:
	return _snapshot(teams.get(team,{}),now)

func local_snapshot(observer_id:int,now:float,team:int=-1)->Array:
	var memory:Dictionary=observers.get(observer_id,{})
	if memory.is_empty() or (team>=0 and int(memory.team)!=team):return []
	return _snapshot(memory.contacts,now)

func forget_observer(observer_id:int)->void:
	observers.erase(observer_id)

func expire(now:float)->void:
	for team in teams.keys():
		_expire_contacts(teams[team],now)
		if teams[team].is_empty():teams.erase(team)
	for observer in observers.keys():
		_expire_contacts(observers[observer].contacts,now)
		if observers[observer].contacts.is_empty():observers.erase(observer)

func _read(fact:Dictionary,now:float)->Dictionary:
	if fact.is_empty() or not is_finite(now):return {}
	var age:float=maxf(0.0,now-float(fact.observed_at))
	if age>=MAX_AGE:return {}
	var copy:Dictionary=fact.duplicate(true)
	copy["age"]=age
	copy["confidence"]=clampf(1.0-age/MAX_AGE,0.0,1.0)
	return copy

func _snapshot(contacts:Dictionary,now:float)->Array:
	var result:Array=[]
	var ids:Array=contacts.keys()
	ids.sort()
	for id in ids:
		var fact:Dictionary=_read(contacts[id],now)
		if not fact.is_empty():result.append(fact)
	return result

func _store(contacts:Dictionary,fact:Dictionary,limit:int)->void:
	var id:int=fact.id
	var previous:Dictionary=contacts.get(id,{})
	if not previous.is_empty():
		if float(previous.observed_at)>float(fact.observed_at):return
		if float(previous.observed_at)==float(fact.observed_at) and int(previous.observer_id)<int(fact.observer_id):return
	contacts[id]=fact.duplicate(true)
	while contacts.size()>limit:
		var oldest:int=-1
		for key in contacts:
			if oldest<0 or float(contacts[key].observed_at)<float(contacts[oldest].observed_at) or (float(contacts[key].observed_at)==float(contacts[oldest].observed_at) and int(key)<oldest):oldest=key
		contacts.erase(oldest)

func _trim_groups(groups:Dictionary,limit:int,local:bool)->void:
	while groups.size()>limit:
		var oldest:int=-1
		var stamp:=INF
		for id in groups:
			var contacts:Dictionary=groups[id].contacts if local else groups[id]
			var newest:=-INF
			for fact in contacts.values():newest=maxf(newest,float(fact.observed_at))
			if newest<stamp or (newest==stamp and (oldest<0 or int(id)<oldest)):
				oldest=id;stamp=newest
		groups.erase(oldest)

func _expire_contacts(contacts:Dictionary,now:float)->void:
	for id in contacts.keys():
		if now-float(contacts[id].observed_at)>=MAX_AGE:contacts.erase(id)
