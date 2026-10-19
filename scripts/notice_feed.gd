extends RefCounted
# Player messages (battle.notify and sim "warning"/"order_report" events) sorted
# by level, with repeats merged and a cap on the banners on screen.
#   ALERT  rare and important (incoming fire, assault, loss): banner + warn chime
#   INFO   a failed order or a notable result: banner, no chime
#   LOW    routine progress: dim, short banner, first to go when the stack is full
#   CURSOR order acknowledgement: small tag beside the pointer, no banner
#   DROP   not shown (the panel, marker or sound already says it)
# A sim event names its level in "notice" ("alert", "info", "low", "cursor",
# "drop", or "vehicle": a player vehicle effect, by VEHICLE_EFFECTS); events
# without one are alerts.
enum {ALERT,INFO,LOW,CURSOR,DROP}
const LEVELS:={"alert":ALERT,"info":INFO,"low":LOW,"cursor":CURSOR,"drop":DROP}
const SECONDS:=[5.0,3.5,2.0,1.5,0.0]
const MERGE_SECONDS:=4.0 # an alert repeated this soon does not chime again
const MAX_BANNERS:=3
# Player vehicle effects: a loss alerts the first time for its kind, then is
# info; what stops it moving is a banner; fire, gun out and repairs are short
# low banners; crew and sights show only as panel tags (hud.damage_tags).
const VEHICLE_EFFECTS:={"catastrophic":"loss","destroyed":"loss","sunk":"loss","crashed":"loss","abandoned":"info","mobility":"info","flooding":"info","tail_rotor":"info","hydraulics":"info","forced_landing":"info","crew":"drop","optics":"drop","repaired_crew":"drop","repaired_optics":"drop"}

# Banners oldest first: {text, key, level, count, left}.
var banners:Array=[]
var cursor_text:=""
var cursor_left:=0.0
# Most recent shown text of any level (tests and battle.toast read it).
var latest:=""
var lost_kinds:={}
var clock:=0.0
var chimed:={} # key -> clock of its last chime
# Counts for probes: offered by level, banners started, repeats merged into a
# shown banner, banners pushed out early, newcomers refused (stack full of more
# important ones), cursor tags, chimes.
var stats:={"offered":[0,0,0,0,0],"banners":0,"merged":0,"evicted":0,"refused":0,"cursor":0,"chimes":0}
var record=null # an Array makes push() append [level, text] (probes)

# Repeat key: the text without its numbers ("3 / 4 sections" matches "4 / 4").
static func key_of(text:String)->String:
	var out:=""
	for c in text:
		if not (c>="0" and c<="9"):out+=c
	return out

# Level of a sim event; a vehicle loss alerts for the first of each kind.
func event_level(event:Dictionary)->int:
	var notice:String=str(event.get("notice","alert"))
	if notice=="vehicle":notice=VEHICLE_EFFECTS.get(str(event.get("effect","")),"low")
	if notice=="loss":
		var kind:String=str(event.get("kind",""))
		if lost_kinds.has(kind):return INFO
		lost_kinds[kind]=true
		return ALERT
	return LEVELS.get(notice,ALERT)

# Shows text at level; true when the warn chime should play (a fresh alert,
# not a merged repeat).
func push(text:String,level:int)->bool:
	stats.offered[level]+=1
	if record!=null:record.append([level,text])
	if level==DROP or text=="":return false
	latest=text
	if level==CURSOR:
		cursor_text=text
		cursor_left=SECONDS[CURSOR]
		stats.cursor+=1
		return false
	var key:=key_of(text)
	for item in banners:
		if item.key==key:
			item.text=text
			item.count+=1
			item.level=mini(item.level,level)
			item.left=maxf(item.left,SECONDS[item.level])
			stats.merged+=1
			return false
	if banners.size()>=MAX_BANNERS and not _evict(level):
		stats.refused+=1
		return false
	banners.append({"text":text,"key":key,"level":level,"count":1,"left":SECONDS[level]})
	stats.banners+=1
	if level!=ALERT or clock<float(chimed.get(key,-INF))+MERGE_SECONDS:return false
	chimed[key]=clock
	stats.chimes+=1
	return true

# Frees a slot for a banner of level: the oldest of the least important
# banners goes, if it is no more important than the newcomer.
func _evict(level:int)->bool:
	var worst:=-1
	for i in banners.size():
		if worst<0 or banners[i].level>banners[worst].level:worst=i
	if worst<0 or banners[worst].level<level:return false
	banners.remove_at(worst)
	stats.evicted+=1
	return true

func advance(dt:float)->void:
	clock+=dt
	cursor_left=maxf(0.0,cursor_left-dt)
	for i in range(banners.size()-1,-1,-1):
		banners[i].left-=dt
		if banners[i].left<=0.0:banners.remove_at(i)

# Banner line as drawn: text plus " ×N" for merged repeats.
static func line(item:Dictionary)->String:
	return str(item.text)+(" ×%d" % item.count if int(item.count)>1 else "")

func clear()->void:
	banners.clear()
	cursor_text=""
	cursor_left=0.0
