extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Infantry=preload("res://scripts/infantry.gd")
var failures:=0
var checks:=0
func check(value:bool,label:String)->void:
 checks+=1
 if not value:failures+=1;printerr("FAIL: ",label)
func _init()->void:
 # Compare against an exhaustive actor candidate list every tick, including
 # independent cover leashes, blocked steering and immediate updates.
 for preset in [0,3,4]:
  var indexed=Sim.new(true,preset)
  var reference=Sim.new(true,preset)
  reference.use_actor_index=false
  for sim in [indexed,reference]:
   sim.issue(sim.living(0).filter(func(u):return sim.definitions[u.kind].domain=="land").map(func(u):return u.id),Vector2(46,22),"attack_move")
  for frame in 240:
   if frame==90:
    for sim in [indexed,reference]:sim.issue(sim.living(0).map(func(u):return u.id),Vector2(14,52),"move")
   indexed.tick(0.1);reference.tick(0.1)
   check(indexed.combat_rng.state==reference.combat_rng.state,"seeded combat unchanged")
   check(indexed.units==reference.units,"all authoritative unit/member states match exhaustive collision queries")
   indexed.events.clear();reference.events.clear()
 # Explicit cross-bucket movement in one tick and corpse/vehicle handling.
 var sim=Sim.new(false,3)
 var squad=sim.spawn("rifle",0,Vector2(14,56))
 sim.rebuild_actor_spatial();sim.ticking=true
 var actor:Dictionary=squad.members[0]
 var old:Vector2=actor.pos
 actor.pos=Vector2(30,60)
 sim.relocate_actor(squad,actor,old)
 var candidates:Array=sim.actor_candidates(actor.pos,actor.pos,0.8)
 check(candidates.any(func(e):return e.unit.id==squad.id and e.actor.index==actor.index),"relocated body appears immediately in new bucket")
 check(not sim.actor_candidates(old,old,0.8).any(func(e):return e.unit.id==squad.id and e.actor.index==actor.index),"old bucket does not retain moved body")
 var tank=sim.spawn("tank",0,Vector2(12,40))
 check(sim.actor_candidates(tank.pos,tank.pos,0.8).any(func(e):return e.unit.id==tank.id),"mid-tick spawn indexed")
 tank.hp=0
 for point in [Vector2(13,40),Vector2(14,52),Vector2(30,60),Vector2(17,56)]:
  sim.use_actor_index=true
  var accelerated:=Infantry.actor_clear(squad,actor,point,sim)
  sim.use_actor_index=false
  check(accelerated==Infantry.actor_clear(squad,actor,point,sim),"swept query and dead-body handling match exhaustive query")
 print("ACTOR SPATIAL: ",checks," checks, ",failures," failures")
 quit(0 if failures==0 else 1)
