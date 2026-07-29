import { diffChars } from 'diff'

export function buildBaselineMap(original, normalized) {
  let lineNormalized = ''
  const lineEndingMap = [0]
  for (let index = 0; index < original.length; index += 1) {
    if (original[index] === '\r' && original[index + 1] === '\n') {
      lineNormalized += '\n'
      index += 1
    } else {
      lineNormalized += original[index]
    }
    lineEndingMap[lineNormalized.length] = index + 1
  }

  const changes = diffChars(lineNormalized, normalized)
  const map = new Array(normalized.length + 1)
  let originalOffset = 0
  let normalizedOffset = 0
  map[0] = 0
  for (const change of changes) {
    if (change.added) {
      for (let index = 0; index < change.value.length; index += 1) {
        map[normalizedOffset + index] = originalOffset
      }
      normalizedOffset += change.value.length
      map[normalizedOffset] = originalOffset
    } else if (change.removed) {
      originalOffset += change.value.length
      if (map[normalizedOffset] === undefined) {
        map[normalizedOffset] = originalOffset
      }
    } else {
      for (let index = 0; index < change.value.length; index += 1) {
        map[normalizedOffset + index] = originalOffset + index
      }
      originalOffset += change.value.length
      normalizedOffset += change.value.length
      map[normalizedOffset] = originalOffset
    }
  }
  map[normalized.length] = lineNormalized.length
  return map.map((offset) => lineEndingMap[offset] ?? original.length)
}

export function patchNormalizedMarkdown(
  original,
  normalizedBaseline,
  nextNormalized,
) {
  if (nextNormalized === normalizedBaseline) return original
  let prefix = 0
  const maxPrefix = Math.min(normalizedBaseline.length, nextNormalized.length)
  while (
    prefix < maxPrefix
    && normalizedBaseline[prefix] === nextNormalized[prefix]
  ) {
    prefix += 1
  }
  let suffix = 0
  const maxSuffix = Math.min(
    normalizedBaseline.length - prefix,
    nextNormalized.length - prefix,
  )
  while (
    suffix < maxSuffix
    && normalizedBaseline[normalizedBaseline.length - suffix - 1]
      === nextNormalized[nextNormalized.length - suffix - 1]
  ) {
    suffix += 1
  }
  const map = buildBaselineMap(original, normalizedBaseline)
  const originalStart = map[prefix] ?? prefix
  const baselineEnd = normalizedBaseline.length - suffix
  const originalEnd = baselineEnd === prefix
    ? originalStart
    : map[baselineEnd] ?? original.length
  const insertedEnd = nextNormalized.length - suffix
  return (
    original.slice(0, originalStart)
    + nextNormalized.slice(prefix, insertedEnd)
    + original.slice(originalEnd)
  )
}
