// Geometry, generated rather than loaded. Each mesh carries two normals per
// vertex: the real one for lighting, and a `smooth` one that points the same
// way on every face sharing that corner. The outline pass pushes vertices out
// along the smooth normal, which keeps a hard-edged box's outline closed at
// the corners instead of splitting open.

import {cross, normalize, sub} from "./math.js"

const mesh = (positions, normals, smooth, indices) => ({
  positions: new Float32Array(positions),
  normals: new Float32Array(normals),
  smooth: new Float32Array(smooth),
  indices: new Uint16Array(indices),
})

// A cube spanning -1..1, to be scaled by a box's half-extents.
export const boxMesh = () => {
  const positions = []
  const normals = []
  const smooth = []
  const indices = []

  for (let axis = 0; axis < 3; axis++) {
    for (const sign of [-1, 1]) {
      const u = (axis + 1) % 3
      const v = (axis + 2) % 3
      const base = positions.length / 3

      for (const [a, b] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) {
        const p = [0, 0, 0]
        p[axis] = sign
        p[u] = a
        p[v] = b
        const n = [0, 0, 0]
        n[axis] = sign
        positions.push(...p)
        normals.push(...n)
        smooth.push(...normalize(p))
      }

      // wound counter-clockwise seen from outside
      if (sign > 0) indices.push(base, base + 1, base + 2, base, base + 2, base + 3)
      else indices.push(base, base + 2, base + 1, base, base + 3, base + 2)
    }
  }

  return mesh(positions, normals, smooth, indices)
}

export const sphereMesh = (segments = 28, rings = 18) => {
  const positions = []
  const indices = []

  for (let r = 0; r <= rings; r++) {
    const phi = (r / rings) * Math.PI
    for (let s = 0; s <= segments; s++) {
      const theta = (s / segments) * 2 * Math.PI
      positions.push(Math.sin(phi) * Math.cos(theta), Math.cos(phi), Math.sin(phi) * Math.sin(theta))
    }
  }

  for (let r = 0; r < rings; r++) {
    for (let s = 0; s < segments; s++) {
      const a = r * (segments + 1) + s
      const b = a + segments + 1
      indices.push(a, a + 1, b, b, a + 1, b + 1)
    }
  }

  return mesh(positions, positions, positions, indices)
}

// A ring of radius 1 lying in the xy plane, so its hole faces along z.
export const torusMesh = (tube = 0.09, segments = 36, sides = 10) => {
  const positions = []
  const normals = []
  const indices = []

  for (let i = 0; i <= segments; i++) {
    const u = (i / segments) * 2 * Math.PI
    for (let j = 0; j <= sides; j++) {
      const v = (j / sides) * 2 * Math.PI
      const n = [Math.cos(v) * Math.cos(u), Math.cos(v) * Math.sin(u), Math.sin(v)]
      positions.push(Math.cos(u) + tube * n[0], Math.sin(u) + tube * n[1], tube * n[2])
      normals.push(...n)
    }
  }

  for (let i = 0; i < segments; i++) {
    for (let j = 0; j < sides; j++) {
      const a = i * (sides + 1) + j
      const b = a + sides + 1
      indices.push(a, b, a + 1, b, b + 1, a + 1)
    }
  }

  return mesh(positions, normals, normals, indices)
}

// An octahedron with flat faces: the collectible.
export const gemMesh = () => {
  const top = [0, 1, 0]
  const bottom = [0, -1, 0]
  const waist = [[0.62, 0, 0], [0, 0, -0.62], [-0.62, 0, 0], [0, 0, 0.62]]
  const positions = []
  const normals = []
  const smooth = []
  const indices = []

  const face = (a, b, c) => {
    const n = normalize(cross(sub(b, a), sub(c, a)))
    const base = positions.length / 3
    for (const p of [a, b, c]) {
      positions.push(...p)
      normals.push(...n)
      smooth.push(...normalize(p))
    }
    indices.push(base, base + 1, base + 2)
  }

  for (let i = 0; i < 4; i++) {
    const a = waist[i]
    const b = waist[(i + 1) % 4]
    face(top, a, b)
    face(bottom, b, a)
  }

  return mesh(positions, normals, smooth, indices)
}

export const buildMeshes = () => ({
  box: boxMesh(),
  sphere: sphereMesh(),
  torus: torusMesh(),
  gem: gemMesh(),
})
