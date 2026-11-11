// Bundles the game into one self-contained page: dist/loose-leaf.html.
// Styles and script are inlined; nothing is fetched at run time. The file has
// no <html>/<head>/<body> of its own because the artifact host supplies them
// (and a browser opening it directly copes without).

import {build} from "esbuild"
import {existsSync, mkdirSync, readFileSync, writeFileSync} from "node:fs"

const here = new URL(".", import.meta.url).pathname
const entry = ["main.ts", "main.js"].map(f => `${here}src/${f}`).find(existsSync)

const result = await build({
  entryPoints: [entry],
  bundle: true,
  minify: true,
  format: "iife",
  target: "es2020",
  write: false,
})

const script = result.outputFiles[0].text.replaceAll("</script", "<\\/script")
const style = readFileSync(`${here}src/style.css`, "utf8")
const body = readFileSync(`${here}src/page.html`, "utf8")

const page = `<title>Loose Leaf</title>
<meta name="claude:viewport-fit-sides" content="cover">
<style>
${style}</style>
${body}<script>
${script}</script>
`

mkdirSync(`${here}dist`, {recursive: true})
writeFileSync(`${here}dist/loose-leaf.html`, page)
console.log(`dist/loose-leaf.html ${(page.length / 1024).toFixed(1)}kb`)
