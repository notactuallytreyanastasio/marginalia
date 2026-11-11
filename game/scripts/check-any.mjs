// Fails if src/ or test/ contain a way of switching the type checker off:
// the `any` type, a double cast through `unknown`, or a ts-ignore style
// directive. tsc's noImplicitAny catches the implicit kind; this catches the
// ones written on purpose.
//
// Comments and string literals are blanked out before the code is searched,
// so the English word "any" in either is fine. The directives live in
// comments, so those are looked for in the raw text instead.

import {readdirSync, readFileSync, statSync} from "node:fs"
import {join, relative} from "node:path"

const here = new URL("..", import.meta.url).pathname
const ROOTS = ["src", "test"]
const SOURCE = /\.(ts|tsx|mts|cts|js|mjs)$/

const CODE_RULES = [
  // `any` as a word, but not a property such as `options.any`
  {pattern: /(?<![.\w$])any(?![\w$])/g, says: "the type `any`"},
  {pattern: /\bas\s+unknown\s+as\b/g, says: "a cast through `unknown`"},
]
const RAW_RULES = [{pattern: /@ts-(ignore|expect-error|nocheck)\b/g, says: "a @ts- directive"}]

const files = dir =>
  readdirSync(dir).flatMap(name => {
    const path = join(dir, name)
    if (statSync(path).isDirectory()) return files(path)
    return SOURCE.test(name) ? [path] : []
  })

// Replaces every comment and string literal with spaces, keeping newlines so
// line numbers still match. Template literals keep their ${...} parts, which
// are code. Regex literals are not recognised; none of this code uses one
// with a quote or comment marker in it.
const blank = source => {
  let out = ""
  let i = 0
  // one entry per open template literal: how many { deep its current ${ is
  const templates = []
  const space = text => text.replace(/[^\n]/g, " ")

  const skipString = quote => {
    let j = i + 1
    while (j < source.length && source[j] !== quote && source[j] !== "\n") j += source[j] === "\\" ? 2 : 1
    out += space(source.slice(i, j + 1))
    i = j + 1
  }

  // from just inside a backtick (or just after a closing `}` of ${...}) to the
  // end of the template or the next ${
  const skipTemplateText = () => {
    let j = i
    while (j < source.length) {
      if (source[j] === "\\") j += 2
      else if (source[j] === "`") {
        out += space(source.slice(i, j + 1))
        i = j + 1
        return
      } else if (source[j] === "$" && source[j + 1] === "{") {
        out += space(source.slice(i, j + 2))
        i = j + 2
        templates.push(0)
        return
      } else j++
    }
    out += space(source.slice(i))
    i = source.length
  }

  while (i < source.length) {
    const c = source[i]
    const next = source[i + 1]

    if (c === "/" && next === "/") {
      const end = source.indexOf("\n", i)
      const stop = end === -1 ? source.length : end
      out += space(source.slice(i, stop))
      i = stop
    } else if (c === "/" && next === "*") {
      const end = source.indexOf("*/", i + 2)
      const stop = end === -1 ? source.length : end + 2
      out += space(source.slice(i, stop))
      i = stop
    } else if (c === '"' || c === "'") {
      skipString(c)
    } else if (c === "`") {
      out += " "
      i++
      skipTemplateText()
    } else if (templates.length > 0 && c === "{") {
      templates[templates.length - 1]++
      out += c
      i++
    } else if (templates.length > 0 && c === "}") {
      if (templates[templates.length - 1] === 0) {
        templates.pop()
        out += " "
        i++
        skipTemplateText()
      } else {
        templates[templates.length - 1]--
        out += c
        i++
      }
    } else {
      out += c
      i++
    }
  }
  return out
}

const lineOf = (text, index) => text.slice(0, index).split("\n").length

const problems = []
for (const root of ROOTS) {
  for (const file of files(join(here, root))) {
    const raw = readFileSync(file, "utf8")
    const code = blank(raw)
    const report = (text, rules) => {
      for (const {pattern, says} of rules) {
        for (const match of text.matchAll(pattern)) {
          problems.push(`${relative(here, file)}:${lineOf(text, match.index)}: ${says}`)
        }
      }
    }
    report(code, CODE_RULES)
    report(raw, RAW_RULES)
  }
}

if (problems.length > 0) {
  console.error(problems.join("\n"))
  console.error(`check:any: ${problems.length} problem${problems.length === 1 ? "" : "s"}`)
  process.exit(1)
}
console.log("check:any: clean")
