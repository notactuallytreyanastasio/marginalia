// Geometry, generated rather than loaded. Each mesh carries two normals per
// vertex: the real one for lighting, and a `smooth` one that points the same
// way on every face sharing that corner. The outline pass pushes vertices out
// along the smooth normal, which keeps a hard-edged box's outline closed at
// the corners instead of splitting open.

import {cross, normalize, sub} from "./math.ts"
import type {MeshData, Meshes, Vec3} from "./types.ts"

const mesh = (
  positions: readonly number[],
  normals: readonly number[],
  smooth: readonly number[],
  indices: readonly number[],
): MeshData => ({
  positions: new Float32Array(positions),
  normals: new Float32Array(normals),
  smooth: new Float32Array(smooth),
  indices: new Uint16Array(indices),
})

// A vector with `value` on one axis and zeros elsewhere.
const onAxis = (axis: number, value: number): Vec3 => [
  axis === 0 ? value : 0,
  axis === 1 ? value : 0,
  axis === 2 ? value : 0,
]

// A cube spanning -1..1, to be scaled by a box's half-extents.
export const boxMesh = (): MeshData => {
  const positions: number[] = []
  const normals: number[] = []
  const smooth: number[] = []
  const indices: number[] = []

  for (let axis = 0; axis < 3; axis++) {
    for (const sign of [-1, 1]) {
      const u = (axis + 1) % 3
      const v = (axis + 2) % 3
      const base = positions.length / 3

      for (const [a, b] of [[-1, -1], [1, -1], [1, 1], [-1, 1]] as const) {
        const p = add3(onAxis(axis, sign), onAxis(u, a), onAxis(v, b))
        positions.push(...p)
        normals.push(...onAxis(axis, sign))
        smooth.push(...normalize(p))
      }

      // wound counter-clockwise seen from outside
      if (sign > 0) indices.push(base, base + 1, base + 2, base, base + 2, base + 3)
      else indices.push(base, base + 2, base + 1, base, base + 3, base + 2)
    }
  }

  return mesh(positions, normals, smooth, indices)
}

const add3 = (a: Vec3, b: Vec3, c: Vec3): Vec3 => [a[0] + b[0] + c[0], a[1] + b[1] + c[1], a[2] + b[2] + c[2]]

export const sphereMesh = (segments = 28, rings = 18): MeshData => {
  const positions: number[] = []
  const indices: number[] = []

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
export const torusMesh = (tube = 0.09, segments = 36, sides = 10): MeshData => {
  const positions: number[] = []
  const normals: number[] = []
  const indices: number[] = []

  for (let i = 0; i <= segments; i++) {
    const u = (i / segments) * 2 * Math.PI
    for (let j = 0; j <= sides; j++) {
      const v = (j / sides) * 2 * Math.PI
      const n: Vec3 = [Math.cos(v) * Math.cos(u), Math.cos(v) * Math.sin(u), Math.sin(v)]
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
export const gemMesh = (): MeshData => {
  const top: Vec3 = [0, 1, 0]
  const bottom: Vec3 = [0, -1, 0]
  const w0: Vec3 = [0.62, 0, 0]
  const w1: Vec3 = [0, 0, -0.62]
  const w2: Vec3 = [-0.62, 0, 0]
  const w3: Vec3 = [0, 0, 0.62]
  // each waist corner paired with the next one round
  const edges = [[w0, w1], [w1, w2], [w2, w3], [w3, w0]] as const
  const positions: number[] = []
  const normals: number[] = []
  const smooth: number[] = []
  const indices: number[] = []

  const face = (a: Vec3, b: Vec3, c: Vec3): void => {
    const n = normalize(cross(sub(b, a), sub(c, a)))
    const base = positions.length / 3
    for (const p of [a, b, c]) {
      positions.push(...p)
      normals.push(...n)
      smooth.push(...normalize(p))
    }
    indices.push(base, base + 1, base + 2)
  }

  for (const [a, b] of edges) {
    face(top, a, b)
    face(bottom, b, a)
  }

  return mesh(positions, normals, smooth, indices)
}

// A prism standing on the y axis: radius 1, from y = -1 to y = 1, closed at
// both ends. Smooth sides shade as a round cylinder; faceted sides give each
// face its own normal, which reads as a cut, low-poly edge. Either way the
// outline normal is the corner's direction from the centre, the same on the
// side and the cap that meet there, so the ink stays closed round the rim.
const prismMesh = (segments: number, faceted: boolean): MeshData => {
  const positions: number[] = []
  const normals: number[] = []
  const smooth: number[] = []
  const indices: number[] = []

  const corner = (theta: number, y: number): Vec3 => [Math.cos(theta), y, Math.sin(theta)]
  const vertex = (p: Vec3, n: Vec3): number => {
    positions.push(...p)
    normals.push(...n)
    smooth.push(...normalize(p))
    return positions.length / 3 - 1
  }

  for (let s = 0; s < segments; s++) {
    const a = (s / segments) * 2 * Math.PI
    const b = ((s + 1) / segments) * 2 * Math.PI
    const middle = (a + b) / 2
    const na: Vec3 = faceted ? [Math.cos(middle), 0, Math.sin(middle)] : [Math.cos(a), 0, Math.sin(a)]
    const nb: Vec3 = faceted ? na : [Math.cos(b), 0, Math.sin(b)]
    const a0 = vertex(corner(a, -1), na)
    const a1 = vertex(corner(a, 1), na)
    const b0 = vertex(corner(b, -1), nb)
    const b1 = vertex(corner(b, 1), nb)
    // counter-clockwise seen from outside
    indices.push(a0, a1, b1, a0, b1, b0)
  }

  for (const y of [-1, 1]) {
    const up: Vec3 = [0, y, 0]
    const center = positions.length / 3
    positions.push(0, y, 0)
    normals.push(...up)
    smooth.push(...up)
    const rim: number[] = []
    for (let s = 0; s < segments; s++) rim.push(vertex(corner((s / segments) * 2 * Math.PI, y), up))
    for (let s = 0; s < segments; s++) {
      const here = rim[s]
      const next = rim[(s + 1) % segments]
      if (here === undefined || next === undefined) continue
      if (y > 0) indices.push(center, next, here)
      else indices.push(center, here, next)
    }
  }

  return mesh(positions, normals, smooth, indices)
}

export const cylinderMesh = (segments = 24): MeshData => prismMesh(segments, false)

// A coin or plate: few, flat sides, to be scaled thin.
export const discMesh = (segments = 10): MeshData => prismMesh(segments, true)

export const buildMeshes = (): Meshes => ({
  box: boxMesh(),
  sphere: sphereMesh(),
  torus: torusMesh(),
  gem: gemMesh(),
  cylinder: cylinderMesh(),
  disc: discMesh(),
})
