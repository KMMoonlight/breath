import assert from 'node:assert/strict'
import test from 'node:test'
import { patchNormalizedMarkdown } from '../src/source-fidelity.js'

test('an unchanged normalized document returns the exact original bytes', () => {
  const original = '\uFEFF---\r\nname: "Breath"\r\n---\r\n\r\n# Title  \r\n'
  const normalized = '---\nname: Breath\n---\n\n# Title\n'
  assert.equal(
    patchNormalizedMarkdown(original, normalized, normalized),
    original,
  )
})

test('a local edit preserves untouched CRLF and trailing spaces', () => {
  const original = '# Title\r\n\r\nOriginal.\r\n\r\nUntouched  \r\n'
  const normalized = '# Title\n\nOriginal.\n\nUntouched\n'
  const edited = '# Title\n\nEdited.\n\nUntouched\n'
  assert.equal(
    patchNormalizedMarkdown(original, normalized, edited),
    '# Title\r\n\r\nEdited.\r\n\r\nUntouched  \r\n',
  )
})

test('unknown syntax outside an edit remains byte-for-byte intact', () => {
  const original = ':::future option="x"\r\nopaque\r\n:::\r\n\r\nHello\r\n'
  const normalized = 'opaque\n\nHello\n'
  const edited = 'opaque\n\nHello world\n'
  assert.equal(
    patchNormalizedMarkdown(original, normalized, edited),
    ':::future option="x"\r\nopaque\r\n:::\r\n\r\nHello world\r\n',
  )
})

test('sequential distant edits preserve source between the edits', () => {
  const original = [
    '---\r\n',
    'title:  Keep spacing\r\n',
    '---\r\n',
    '\r\n',
    '# First\r\n',
    '\r\n',
    '```swift\r\n',
    'let value =  1  \r\n',
    '```\r\n',
    '\r\n',
    '# Last\r\n',
  ].join('')
  const firstBaseline = original.replaceAll('\r\n', '\n')
  const firstNormalized = firstBaseline.replace('# First', '# Updated first')
  const afterFirst = patchNormalizedMarkdown(
    original,
    firstBaseline,
    firstNormalized,
  )
  const secondNormalized = firstNormalized.replace('# Last', '# Updated last')
  const afterSecond = patchNormalizedMarkdown(
    afterFirst,
    firstNormalized,
    secondNormalized,
  )

  assert.equal(
    afterSecond,
    original
      .replace('# First', '# Updated first')
      .replace('# Last', '# Updated last'),
  )
  assert.match(afterSecond, /let value =  1  \r\n/)
})
