#!/usr/bin/env python3
"""Regressions for reproducible regional content and invalid editor mutations."""
import copy
import json
import unittest

from build_region_maps import ROOT, BLUEPRINT_DIR, OUTPUT_DIR, compile_blueprint, encode_json, validate_compiled
from regional_map_schema import validate_blueprint


class RegionalAuthoringTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.blueprints = {p.stem: json.loads(p.read_text()) for p in BLUEPRINT_DIR.glob("*.json")}
        cls.configs = {p.stem: json.loads(p.read_text()) for p in OUTPUT_DIR.glob("*.json")}

    def test_all_three_maps_reproduce_and_are_connected(self):
        self.assertEqual(set(self.blueprints), {"bayhead_rail_valley", "limestone_pass", "south_inlet"})
        for ident, data in self.blueprints.items():
            with self.subTest(map=ident):
                self.assertEqual(validate_blueprint(data), [])
                before = copy.deepcopy(data)
                output = compile_blueprint(data)
                self.assertEqual(data, before, "compile must not mutate an editor's live draft")
                self.assertEqual(encode_json(output), (OUTPUT_DIR/f"{ident}.json").read_text())
                self.assertEqual(output["map_renderer"], "harbor")
                self.assertGreater(output["building_count"], 15)

    def test_catalogue_resolves_every_external_map(self):
        manifest=json.loads((ROOT/"resources/regions/black_sea_region.json").read_text())
        ids={b["id"] for b in manifest["battlefields"]}
        for item in manifest["battlefields"]:
            self.assertEqual(item["id"],item["scenario_id"])
            self.assertTrue(set(item["connections"]) <= ids)
            if "map_path" in item:
                path=ROOT/item["map_path"].removeprefix("res://")
                self.assertEqual(json.loads(path.read_text())["id"],item["id"])
        self.assertEqual(len(ids),4)

    def test_road_cannot_cross_water_without_a_bridge(self):
        data=copy.deepcopy(self.blueprints["bayhead_rail_valley"])
        data["streets"].append({"name":"Invalid crossing","width":12,"points":[[20,16],[20,100]],"class":"street","purpose":"road"})
        self.assertTrue(any("overlaps water" in e for e in validate_blueprint(data)))

    def test_road_cannot_run_through_a_ridge(self):
        data=copy.deepcopy(self.blueprints["bayhead_rail_valley"])
        data["rock_parcels"].append([85,190,25,12])
        self.assertTrue(any("intersects a solid rock" in e for e in validate_blueprint(data)))

    def test_non_finite_or_self_crossing_input_is_rejected(self):
        data=copy.deepcopy(self.blueprints["south_inlet"])
        data["scenario"]["size"][0]=float("nan")
        self.assertTrue(validate_blueprint(data))
        data=copy.deepcopy(self.blueprints["south_inlet"])
        data["scenario"]["water_polygons"]=[[[20,20],[80,80],[20,80],[80,20]]]
        self.assertTrue(any("polygon" in e for e in validate_blueprint(data)))

    def test_floating_land_assets_and_beached_boats_are_rejected(self):
        data=copy.deepcopy(self.blueprints["south_inlet"])
        data["decor"].append({"id":"transformer.pad_mounted","position":[50,50],"domain":"sea"})
        self.assertTrue(any("must be supported by land" in e for e in validate_blueprint(data)))
        data["decor"][-1]={"id":"small_boat.rowing","position":[400,250],"domain":"land"}
        self.assertTrue(any("must be supported by sea" in e for e in validate_blueprint(data)))

    def test_rail_vehicles_need_a_real_aligned_track(self):
        data=copy.deepcopy(self.blueprints["bayhead_rail_valley"])
        data["decor"][0]["position"]=[250,210]
        self.assertTrue(any("align with an authored railway" in e for e in validate_blueprint(data)))

    def test_landmark_must_belong_to_its_named_district(self):
        data=copy.deepcopy(self.blueprints["bayhead_rail_valley"])
        data["landmarks"][0]["position"]=[410,290]
        self.assertTrue(any("inside its named district" in e for e in validate_blueprint(data)))

    def test_explicit_object_cannot_be_silently_omitted(self):
        data=copy.deepcopy(self.blueprints["limestone_pass"])
        data["decor"].append({"id":"concrete_barrier.jersey","position":[250,166],"context":"invalid on objective"})
        with self.assertRaisesRegex(ValueError,"Cannot place concrete_barrier"):
            compile_blueprint(data)

    def test_disconnected_objective_cannot_be_saved(self):
        data=copy.deepcopy(self.configs["limestone_pass"])
        data["blocks"].append([224,0,8,320])
        self.assertTrue(any("no conservative land route" in e for e in validate_compiled(data)))

    def test_invalid_initial_body_is_reported(self):
        data=copy.deepcopy(self.configs["south_inlet"])
        data["player_force"][0]["position"]=[50,50]
        self.assertTrue(any("player_force 1" in e for e in validate_compiled(data)))


if __name__ == "__main__":
    unittest.main()
