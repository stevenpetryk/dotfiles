const path = require("node:path")
const childProcess = require("node:child_process")

const cwd = process.cwd()

const PNPM_ROOT = path.join(process.env.HOME, "src/discord")
const YARN_ROOT = path.join(process.env.HOME, "src/discord-yarn")

/** @type {string} */
let CURRENT_ROOT
if (cwd.startsWith(PNPM_ROOT)) {
  CURRENT_ROOT = PNPM_ROOT
}
if (cwd.startsWith(YARN_ROOT)) {
  CURRENT_ROOT = YARN_ROOT
}
if (!CURRENT_ROOT) throw new Error("Must be in a repo.")

const relPath = path.relative(CURRENT_ROOT, cwd)

function test(root) {
  const testRoot = path.join(root, relPath)
  const pkg = process.argv[2]

  function nodeExec(cmd, symlinks) {
    childProcess.execSync(`node -e "${cmd}"`, {
      cwd: testRoot,
      stdio: "inherit",
      env: { ...process.env, NODE_PRESERVE_SYMLINKS: symlinks },
    })
  }

  nodeExec(`console.log('  ' + require.resolve('${pkg}'))`, 1)
  nodeExec(`console.log('  ' + require.resolve('${pkg}'))`, 0)
  nodeExec(`console.log('  ' + require('${pkg}/package.json').version)`, 0)
}

console.log("pnpm:")
test(PNPM_ROOT)

console.log("\nyarn:")
test(YARN_ROOT)

console.log(relPath)
