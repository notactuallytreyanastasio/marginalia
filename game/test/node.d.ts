// Just enough of node:test and node:assert/strict for the tests to typecheck,
// written out here so the only dev dependencies are typescript and esbuild.
// Node itself supplies the real modules when `npm test` runs.

declare module "node:test" {
  export default function test(name: string, body: () => void | Promise<void>): Promise<void>
}

declare module "node:assert/strict" {
  interface Assert {
    ok(value: unknown, message?: string): asserts value
    equal<T>(actual: unknown, expected: T, message?: string): asserts actual is T
    notEqual(actual: unknown, expected: unknown, message?: string): void
    deepEqual<T>(actual: unknown, expected: T, message?: string): asserts actual is T
    fail(message?: string): never
  }
  const assert: Assert
  export default assert
}
