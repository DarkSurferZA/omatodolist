import { readFileSync } from "node:fs"

// Loads a `.pragma library` QML JS module under Node: strip the pragma line
// (the only QML-specific syntax these files use) and evaluate the rest with
// `new Function`, returning the requested top-level names.
export function loadQmlLib(path, names) {
  const src = readFileSync(path, "utf8").replace(/^\s*\.pragma library\s*$/m, "")
  const body = src + "\nreturn { " + names.map(function(n) { return n + ": " + n }).join(", ") + " };"
  return new Function(body)()
}
