class_name ChunkModification

static func _get_affected_voxels(chunks_instance, global_center_pos: Vector3, r: float) -> Dictionary:
	var CHUNK_SIDE_SIZE: int = chunks_instance.CHUNK_SIDE_SIZE
	var CHUNK_SIZE: float = chunks_instance.CHUNK_SIZE.x
	var NUM_CHUNKS_SIDE: Vector3i = chunks_instance.NUM_CHUNKS_SIDE
	var cell_size: float = CHUNK_SIZE / (CHUNK_SIDE_SIZE - 1)

	var world_offset = Vector3(
		-0.5 * NUM_CHUNKS_SIDE.x * CHUNK_SIZE,
		-0.5 * NUM_CHUNKS_SIDE.y * CHUNK_SIZE,
		-0.5 * NUM_CHUNKS_SIDE.z * CHUNK_SIZE
	)

	var center_voxel = (global_center_pos - world_offset) / cell_size
	var cv = Vector3i(roundi(center_voxel.x), roundi(center_voxel.y), roundi(center_voxel.z))
	var r_voxels: int = ceili(r / cell_size)

	var max_gx = NUM_CHUNKS_SIDE.x * (CHUNK_SIDE_SIZE - 1)
	var max_gy = NUM_CHUNKS_SIDE.y * (CHUNK_SIDE_SIZE - 1)
	var max_gz = NUM_CHUNKS_SIDE.z * (CHUNK_SIDE_SIZE - 1)

	var cs = CHUNK_SIDE_SIZE - 1
	var r_sq: float = r * r

	# returns {chunk_id: [local_idx, ...]}
	# NOTE: voxels on chunk boundaries are only assigned to the chunk they fall in,
	# not also to the neighboring chunk's last row — fix if visible seams appear.
	var result: Dictionary = {}

	for dx in range(-r_voxels, r_voxels + 1):
		for dy in range(-r_voxels, r_voxels + 1):
			for dz in range(-r_voxels, r_voxels + 1):
				var gx = cv.x + dx
				var gy = cv.y + dy
				var gz = cv.z + dz

				if gx < 0 or gy < 0 or gz < 0:
					continue
				if gx >= max_gx or gy >= max_gy or gz >= max_gz:
					continue

				var voxel_world = world_offset + Vector3(gx, gy, gz) * cell_size
				if voxel_world.distance_squared_to(global_center_pos) > r_sq:
					continue

				var chunk_x = gx / cs
				var chunk_y = gy / cs
				var chunk_z = gz / cs

				var lx = gx % cs
				var ly = gy % cs
				var lz = gz % cs

				# If a local coord is 0 the voxel sits on a chunk boundary and
				# is also the last voxel (index cs) of the neighbouring chunk.
				# Iterate all combinations (up to 8 chunks share a corner voxel).
				var x_offsets = [-1, 0] if (lx == 0 and chunk_x > 0) else [0]
				var y_offsets = [-1, 0] if (ly == 0 and chunk_y > 0) else [0]
				var z_offsets = [-1, 0] if (lz == 0 and chunk_z > 0) else [0]

				for ox in x_offsets:
					for oy in y_offsets:
						for oz in z_offsets:
							var ncx = chunk_x + ox
							var ncy = chunk_y + oy
							var ncz = chunk_z + oz
							var nlx = cs if ox == -1 else lx
							var nly = cs if oy == -1 else ly
							var nlz = cs if oz == -1 else lz
							var nchunk_id = ncx * NUM_CHUNKS_SIDE.y * NUM_CHUNKS_SIDE.z \
										  + ncy * NUM_CHUNKS_SIDE.z \
										  + ncz
							var nlocal_idx = nlx * CHUNK_SIDE_SIZE * CHUNK_SIDE_SIZE \
										   + nly * CHUNK_SIDE_SIZE \
										   + nlz
							if nchunk_id not in result:
								result[nchunk_id] = []
							if nlocal_idx not in result[nchunk_id]:
								result[nchunk_id].append(nlocal_idx)

	return result


static func spherical_uniform_set_delta(chunks_instance, global_center_pos: Vector3, r: float, value: float) -> void:
	var affected = _get_affected_voxels(chunks_instance, global_center_pos, r)
	for chunk_id in affected:
		var chunk_instance = chunks_instance.get_child(chunk_id)
		var delta = {}
		for local_idx in affected[chunk_id]:
			delta[local_idx] = value
		chunk_instance.apply_changes(delta)


static func spherical_uniform_add_delta(chunks_instance, global_center_pos: Vector3, r: float, delta: float) -> void:
	var affected = _get_affected_voxels(chunks_instance, global_center_pos, r)
	for chunk_id in affected:
		var chunk_instance = chunks_instance.get_child(chunk_id)
		var chunk_delta = {}
		for local_idx in affected[chunk_id]:
			var current = chunk_instance.point_values[local_idx] if local_idx < chunk_instance.point_values.size() else 0.0
			chunk_delta[local_idx] = clamp(current + delta, -1.0, 1.0)
		chunk_instance.apply_changes(chunk_delta)


static func _voxel_weight(chunks_instance, chunk_instance, local_idx: int, global_center_pos: Vector3, r: float) -> float:
	var SS: int = chunks_instance.CHUNK_SIDE_SIZE
	var cell_size: float = chunks_instance.CHUNK_SIZE.x / (SS - 1)
	var lx = local_idx / (SS * SS)
	var ly = (local_idx / SS) % SS
	var lz = local_idx % SS
	var voxel_world = chunk_instance.position + Vector3(lx, ly, lz) * cell_size
	var t = voxel_world.distance_to(global_center_pos)
	return 1.0 - t / r


static func spherical_smooth_set_delta(chunks_instance, global_center_pos: Vector3, r: float, value: float) -> void:
	var affected = _get_affected_voxels(chunks_instance, global_center_pos, r)
	for chunk_id in affected:
		var chunk_instance = chunks_instance.get_child(chunk_id)
		var delta = {}
		for local_idx in affected[chunk_id]:
			var weight = _voxel_weight(chunks_instance, chunk_instance, local_idx, global_center_pos, r)
			delta[local_idx] = value * weight
		chunk_instance.apply_changes(delta)


static func spherical_smooth_add_delta(chunks_instance, global_center_pos: Vector3, r: float, delta: float) -> void:
	var affected = _get_affected_voxels(chunks_instance, global_center_pos, r)
	for chunk_id in affected:
		var chunk_instance = chunks_instance.get_child(chunk_id)
		var chunk_delta = {}
		for local_idx in affected[chunk_id]:
			var current = chunk_instance.point_values[local_idx] if local_idx < chunk_instance.point_values.size() else 0.0
			var weight = _voxel_weight(chunks_instance, chunk_instance, local_idx, global_center_pos, r)
			chunk_delta[local_idx] = clamp(current + delta * weight, -1.0, 1.0)
		chunk_instance.apply_changes(chunk_delta)
