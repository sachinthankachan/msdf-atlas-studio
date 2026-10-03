# Contributor verification test
class_name KerningExtractor
extends RefCounted

static func extract_kerning(font_path: String, codepoints: PackedInt32Array, em_size: int = 1000) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if font_path.is_empty() or codepoints.size() < 2:
		return result

	var font: FontFile = null
	if font_path.begins_with("res://"):
		if ResourceLoader.exists(font_path):
			font = load(font_path) as FontFile

	if not font:
		var bytes := FileAccess.get_file_as_bytes(font_path)
		if bytes.is_empty():
			return result
		font = FontFile.new()
		font.data = bytes

	if not font:
		return result

	var test_size: int = max(64, em_size)
	var cp_count: int = codepoints.size()

	var glyph_indices: Dictionary = {}
	for i in range(cp_count):
		var cp: int = codepoints[i]
		if _is_kernable_codepoint(cp):
			var gid: int = font.get_glyph_index(test_size, cp, 0)
			if gid > 0:
				glyph_indices[cp] = gid

	var kernable_cps: Array = glyph_indices.keys()
	var kern_count: int = kernable_cps.size()
	if kern_count < 2:
		return result

	var ts: TextServer = TextServerManager.get_primary_interface()
	var font_rids: Array[RID] = font.get_rids()
	var font_rid: RID = font_rids[0] if not font_rids.is_empty() else RID()

	var glyph_to_cps: Dictionary = {}
	for cp in kernable_cps:
		var gid: int = glyph_indices[cp]
		if not glyph_to_cps.has(gid):
			glyph_to_cps[gid] = []
		glyph_to_cps[gid].append(cp)

	var pair_list: Array = []
	if font_rid.is_valid() and ts:
		pair_list = ts.font_get_kerning_list(font_rid, test_size)

	if not pair_list.is_empty():
		for p in pair_list:
			var g1: int = p.x
			var g2: int = p.y
			if glyph_to_cps.has(g1) and glyph_to_cps.has(g2):
				var k_vec: Vector2 = ts.font_get_kerning(font_rid, test_size, Vector2i(g1, g2))
				var adv_em: float = snappedf(k_vec.x / float(test_size), 0.0001)
				if absf(k_vec.x) > 0.05 and adv_em >= -0.35 and adv_em <= 0.35:
					for cp1 in glyph_to_cps[g1]:
						for cp2 in glyph_to_cps[g2]:
							result.append({
								"unicode1": cp1,
								"unicode2": cp2,
								"advance": adv_em
							})
	elif not font_rid.is_valid():
		for i in range(kern_count):
			var cp1: int = kernable_cps[i]
			var g1: int = glyph_indices[cp1]
			for j in range(kern_count):
				var cp2: int = kernable_cps[j]
				var g2: int = glyph_indices[cp2]
				var k_vec: Vector2 = font.get_kerning(0, test_size, Vector2i(g1, g2))
				var adv_em: float = snappedf(k_vec.x / float(test_size), 0.0001)
				if absf(k_vec.x) > 0.05 and adv_em >= -0.35 and adv_em <= 0.35:
					result.append({
						"unicode1": cp1,
						"unicode2": cp2,
						"advance": adv_em
					})

	# opentype gpos shaping pass if font lacks legacy kern table
	if result.is_empty() and ts and not font_rids.is_empty():
		var shaped: RID = ts.create_shaped_text()
		var single_shaped: RID = ts.create_shaped_text()
		var unkerned_adv: Dictionary = {}

		for cp in kernable_cps:
			ts.shaped_text_clear(single_shaped)
			ts.shaped_text_add_string(single_shaped, String.chr(cp), font_rids, test_size)
			ts.shaped_text_shape(single_shaped)
			unkerned_adv[cp] = ts.shaped_text_get_width(single_shaped)
		ts.free_rid(single_shaped)

		for i in range(kern_count):
			var cp1: int = kernable_cps[i]
			var a1: float = unkerned_adv.get(cp1, 0.0)
			if a1 <= 0.0:
				continue

			for j in range(kern_count):
				var cp2: int = kernable_cps[j]
				var a2: float = unkerned_adv.get(cp2, 0.0)
				if a2 <= 0.0:
					continue

				ts.shaped_text_clear(shaped)
				ts.shaped_text_add_string(shaped, String.chr(cp1) + String.chr(cp2), font_rids, test_size)
				ts.shaped_text_shape(shaped)

				# make sure harfbuzz formed two distinct glyphs so we skip ligatures like fi
				var shaped_glyphs: Array = ts.shaped_text_get_glyphs(shaped)
				if shaped_glyphs.size() != 2:
					continue

				var pair_w: float = ts.shaped_text_get_width(shaped)
				var diff: float = pair_w - (a1 + a2)
				var adv_em: float = snappedf(diff / float(test_size), 0.0001)

				if absf(diff) > 0.1 and adv_em >= -0.35 and adv_em <= 0.35:
					result.append({
						"unicode1": cp1,
						"unicode2": cp2,
						"advance": adv_em
					})

		ts.free_rid(shaped)

	return result

static func _is_kernable_codepoint(cp: int) -> bool:
	if cp < 32 or (cp >= 127 and cp < 160):
		return false
	# cjk ideographs, hangul, and private use characters do not use pair kerning
	if (cp >= 0x2E80 and cp <= 0x9FFF) or (cp >= 0xAC00 and cp <= 0xD7AF) or (cp >= 0xE000 and cp <= 0xF8FF):
		return false
	return true
