extends "res://tools/asset_gallery.gd"
func run()->void:
	await super.run()
	await self_test()
