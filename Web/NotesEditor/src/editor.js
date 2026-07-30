import { Editor, Extension } from '@tiptap/core'
import CodeBlockLowlight from '@tiptap/extension-code-block-lowlight'
import Image from '@tiptap/extension-image'
import { TableKit } from '@tiptap/extension-table'
import TaskItem from '@tiptap/extension-task-item'
import TaskList from '@tiptap/extension-task-list'
import { Markdown } from '@tiptap/markdown'
import StarterKit from '@tiptap/starter-kit'
import DOMPurify from 'dompurify'
import hljs from 'highlight.js'
import katex from 'katex'
import 'katex/dist/katex.min.css'
import { common, createLowlight } from 'lowlight'
import mermaid from 'mermaid'
import { Plugin, PluginKey } from '@tiptap/pm/state'
import { Decoration, DecorationSet } from '@tiptap/pm/view'
import { patchNormalizedMarkdown } from './source-fidelity.js'

const lowlight = createLowlight(common)
const root = document.querySelector('#editor')
const source = document.querySelector('#source')
const status = document.querySelector('#status')

let documentID = null
let documentVersion = 0
let originalSource = ''
let normalizedBaseline = ''
let sourceModeOriginal = ''
let sourceModeBaseline = ''
let mode = 'wysiwyg'
let isLoading = false
let forcePlainTextPaste = false
let diagramSequence = 0
let lastActiveHeadingIndex
let activeHeadingViewportFrame = null
let ui = {}

const translations = {
  'zh-Hans': {
    editor: 'Markdown 编辑器',
    sourceEditor: 'Markdown 源码编辑器',
    math: '数学公式',
    formulaError: '公式错误',
    cannotRender: '无法渲染',
    mermaid: 'Mermaid 图表',
    renderingDiagram: '正在渲染图表…',
    mermaidError: 'Mermaid 错误',
    copy: '复制',
    copied: '已复制',
    copyCode: '复制代码块',
    attachment: '附件',
    tableActions: '表格操作',
    addRow: '在下方添加行',
    deleteRow: '删除行',
    addColumn: '在右侧添加列',
    deleteColumn: '删除列',
    alignLeft: '左对齐',
    alignCenter: '居中对齐',
    alignRight: '右对齐',
  },
  en: {
    editor: 'Markdown editor',
    sourceEditor: 'Markdown source editor',
    math: 'Math formula',
    formulaError: 'Formula error',
    cannotRender: 'Unable to render',
    mermaid: 'Mermaid diagram',
    renderingDiagram: 'Rendering diagram…',
    mermaidError: 'Mermaid error',
    copy: 'Copy',
    copied: 'Copied',
    copyCode: 'Copy code block',
    attachment: 'Attachment',
    tableActions: 'Table actions',
    addRow: 'Add row below',
    deleteRow: 'Delete row',
    addColumn: 'Add column to the right',
    deleteColumn: 'Delete column',
    alignLeft: 'Align left',
    alignCenter: 'Align center',
    alignRight: 'Align right',
  },
}

function setLanguage(language) {
  const resolved = language === 'en' ? 'en' : 'zh-Hans'
  ui = translations[resolved]
  document.documentElement.lang = resolved
  root.setAttribute('aria-label', ui.editor)
  source.setAttribute('aria-label', ui.sourceEditor)
}

setLanguage('zh-Hans')

function routedResourceURL(sourceURL) {
  if (!sourceURL || sourceURL.startsWith('data:')) return sourceURL
  try {
    const parsed = new URL(sourceURL)
    if (parsed.protocol === 'https:') {
      return `breath-note-resource://remote?url=${encodeURIComponent(sourceURL)}`
    }
    return ''
  } catch {
    return `breath-note-resource://local?path=${encodeURIComponent(sourceURL)}`
  }
}

const SecureImage = Image.extend({
  renderHTML({ HTMLAttributes }) {
    return ['img', {
      ...HTMLAttributes,
      src: routedResourceURL(HTMLAttributes.src),
    }]
  },
})

mermaid.initialize({
  startOnLoad: false,
  securityLevel: 'strict',
  htmlLabels: false,
  suppressErrorRendering: true,
})

function renderMath(sourceText, displayMode) {
  const container = document.createElement(displayMode ? 'div' : 'span')
  container.className = displayMode ? 'math-preview block' : 'math-preview inline'
  container.contentEditable = 'false'
  container.setAttribute('aria-label', `${ui.math}: ${sourceText}`)
  try {
    katex.render(sourceText, container, {
      displayMode,
      throwOnError: true,
      strict: 'warn',
      trust: false,
    })
  } catch (error) {
    container.className += ' render-error'
    container.textContent = `${ui.formulaError}: ${
      error instanceof Error ? error.message : ui.cannotRender
    }`
  }
  return container
}

function renderMermaid(sourceText) {
  const container = document.createElement('div')
  container.className = 'mermaid-preview'
  container.contentEditable = 'false'
  container.setAttribute('aria-label', ui.mermaid)
  container.textContent = ui.renderingDiagram
  const id = `breath-mermaid-${diagramSequence += 1}`
  void mermaid.render(id, sourceText).then(({ svg }) => {
    if (!container.isConnected) return
    container.innerHTML = DOMPurify.sanitize(svg, {
      USE_PROFILES: { svg: true, svgFilters: true },
      FORBID_TAGS: ['script', 'foreignObject'],
      FORBID_ATTR: ['onload', 'onclick', 'onerror'],
    })
  }).catch((error) => {
    if (!container.isConnected) return
    container.className += ' render-error'
    container.textContent = `${ui.mermaidError}: ${
      error instanceof Error ? error.message : ui.cannotRender
    }`
  })
  return container
}

function codeActions(sourceText) {
  const container = document.createElement('div')
  container.className = 'code-actions'
  container.contentEditable = 'false'

  const lineNumbers = document.createElement('span')
  lineNumbers.className = 'code-line-numbers'
  lineNumbers.textContent = Array.from(
    { length: Math.max(1, sourceText.split('\n').length) },
    (_, index) => String(index + 1),
  ).join('\n')
  container.append(lineNumbers)

  const copyButton = document.createElement('button')
  copyButton.type = 'button'
  copyButton.className = 'copy-code'
  copyButton.textContent = ui.copy
  copyButton.setAttribute('aria-label', ui.copyCode)
  copyButton.addEventListener('click', async () => {
    await navigator.clipboard.writeText(sourceText)
    copyButton.textContent = ui.copied
    setTimeout(() => { copyButton.textContent = ui.copy }, 1200)
  })
  container.append(copyButton)
  return container
}

const RenderedMarkdown = Extension.create({
  name: 'breathRenderedMarkdown',
  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: new PluginKey('breathRenderedMarkdown'),
        props: {
          decorations(state) {
            const decorations = []
            state.doc.descendants((node, position) => {
              if (node.type.name === 'codeBlock') {
                decorations.push(Decoration.widget(
                  position + node.nodeSize,
                  () => codeActions(node.textContent),
                  { side: -1, key: `code-${position}-${node.textContent.length}` },
                ))
                if ((node.attrs.language || '').toLowerCase() === 'mermaid') {
                  decorations.push(Decoration.widget(
                    position + node.nodeSize,
                    () => renderMermaid(node.textContent),
                    { side: 1, key: `mermaid-${position}-${node.textContent}` },
                  ))
                }
              }
              if (!node.isText || !node.text) return
              const patterns = [
                { expression: /\$\$([^$]+)\$\$/g, display: true },
                { expression: /(?<!\$)\$([^$\n]+)\$(?!\$)/g, display: false },
              ]
              for (const pattern of patterns) {
                for (const match of node.text.matchAll(pattern.expression)) {
                  const start = position + (match.index ?? 0)
                  const end = start + match[0].length
                  decorations.push(Decoration.inline(start, end, {
                    class: 'math-source',
                  }))
                  decorations.push(Decoration.widget(
                    end,
                    () => renderMath(match[1], pattern.display),
                    {
                      side: 1,
                      key: `math-${start}-${match[0]}`,
                    },
                  ))
                }
              }
            })
            return DecorationSet.create(state.doc, decorations)
          },
        },
      }),
    ]
  },
})

const editor = new Editor({
  element: root,
  extensions: [
    StarterKit.configure({ codeBlock: false }),
    CodeBlockLowlight.configure({ lowlight }),
    SecureImage.configure({ allowBase64: true }),
    TableKit.configure({ table: { resizable: false } }),
    TaskList,
    TaskItem.configure({ nested: true }),
    Markdown.configure({
      markedOptions: { gfm: true },
    }),
    RenderedMarkdown,
  ],
  content: '',
  contentType: 'markdown',
  injectCSS: false,
  onUpdate: () => {
    if (isLoading || mode !== 'wysiwyg') return
    const nextNormalized = editor.getMarkdown()
    const markdown = patchedMarkdown(nextNormalized)
    originalSource = markdown
    normalizedBaseline = nextNormalized
    source.value = markdown
    post('editorChange', { content: markdown })
    reportActiveHeading(activeHeadingFromEditorSelection())
  },
  onSelectionUpdate: () => {
    if (isLoading || mode !== 'wysiwyg') return
    reportActiveHeading(activeHeadingFromEditorSelection())
  },
  editorProps: {
    transformPastedHTML(html) {
      return DOMPurify.sanitize(html, {
        FORBID_TAGS: ['script', 'iframe', 'object', 'embed'],
        FORBID_ATTR: ['onerror', 'onload', 'onclick', 'onfocus'],
      })
    },
    handlePaste(view, event) {
      if (forcePlainTextPaste) {
        forcePlainTextPaste = false
        const text = event.clipboardData?.getData('text/plain') ?? ''
        view.dispatch(view.state.tr.insertText(text))
        return true
      }
      const files = Array.from(event.clipboardData?.files ?? [])
      if (files.length > 0) {
        event.preventDefault()
        files.forEach(importAttachmentFile)
        return true
      }
      return false
    },
    handleDrop(_view, event) {
      const files = Array.from(event.dataTransfer?.files ?? [])
      if (files.length === 0) return false
      event.preventDefault()
      files.forEach(importAttachmentFile)
      return true
    },
    handleClick(view, position, event) {
      const anchor = event.target.closest?.('a')
      if (!anchor) return false
      event.preventDefault()
      post('openLink', { href: anchor.getAttribute('href') || '' })
      return true
    },
  },
})

function sanitizeMarkdownForPreview(markdown) {
  const protectedSegments = []
  const protectedMarkdown = markdown.replace(
    /(^|\n)(`{3,}|~{3,})[^\n]*\n[\s\S]*?\n\2(?=\n|$)|`+[^`\n]*`+/g,
    (segment) => {
      const token = `BREATHPROTECTED${protectedSegments.length}TOKEN`
      protectedSegments.push(segment)
      return token
    },
  )
  const sanitized = DOMPurify.sanitize(protectedMarkdown, {
    FORBID_TAGS: ['script', 'iframe', 'object', 'embed', 'form'],
    FORBID_ATTR: [
      'onerror', 'onload', 'onclick', 'onfocus', 'onmouseover',
      'srcdoc',
    ],
    ALLOW_UNKNOWN_PROTOCOLS: false,
  })
  return sanitized.replace(
    /BREATHPROTECTED(\d+)TOKEN/g,
    (_match, index) => protectedSegments[Number(index)] ?? '',
  )
}

function importAttachmentFile(file) {
  const reader = new FileReader()
  reader.addEventListener('load', () => {
    const result = String(reader.result ?? '')
    const separator = result.indexOf(',')
    if (separator < 0) return
    post('importAttachment', {
      filename: file.name || ui.attachment,
      mimeType: file.type || 'application/octet-stream',
      base64: result.slice(separator + 1),
    })
  })
  reader.readAsDataURL(file)
}

document.addEventListener('keydown', (event) => {
  if (event.metaKey && event.shiftKey && event.key.toLowerCase() === 'v') {
    forcePlainTextPaste = true
  }
})

root.addEventListener('contextmenu', (event) => {
  const cell = event.target.closest?.('td, th')
  if (!cell) return
  event.preventDefault()
  document.querySelector('#table-menu')?.remove()
  const menu = document.createElement('div')
  menu.id = 'table-menu'
  menu.setAttribute('role', 'menu')
  menu.setAttribute('aria-label', ui.tableActions)
  menu.contentEditable = 'false'
  const commands = [
    [ui.addRow, () => editor.chain().focus().addRowAfter().run()],
    [ui.deleteRow, () => editor.chain().focus().deleteRow().run()],
    [ui.addColumn, () => editor.chain().focus().addColumnAfter().run()],
    [ui.deleteColumn, () => editor.chain().focus().deleteColumn().run()],
    [ui.alignLeft, () => editor.chain().focus().setCellAttribute('textAlign', 'left').run()],
    [ui.alignCenter, () => editor.chain().focus().setCellAttribute('textAlign', 'center').run()],
    [ui.alignRight, () => editor.chain().focus().setCellAttribute('textAlign', 'right').run()],
  ]
  commands.forEach(([label, command]) => {
    const button = document.createElement('button')
    button.type = 'button'
    button.setAttribute('role', 'menuitem')
    button.tabIndex = 0
    button.textContent = label
    button.addEventListener('click', () => {
      command()
      menu.remove()
    })
    menu.append(button)
  })
  menu.style.left = `${event.clientX}px`
  menu.style.top = `${event.clientY}px`
  document.body.append(menu)
  menu.querySelector('button')?.focus()
  menu.addEventListener('keydown', (keyboardEvent) => {
    const buttons = Array.from(menu.querySelectorAll('button'))
    const current = buttons.indexOf(document.activeElement)
    if (keyboardEvent.key === 'Escape') {
      keyboardEvent.preventDefault()
      menu.remove()
      editor.commands.focus()
    } else if (keyboardEvent.key === 'ArrowDown') {
      keyboardEvent.preventDefault()
      buttons[(current + 1) % buttons.length]?.focus()
    } else if (keyboardEvent.key === 'ArrowUp') {
      keyboardEvent.preventDefault()
      buttons[(current - 1 + buttons.length) % buttons.length]?.focus()
    }
  })
})

document.addEventListener('pointerdown', (event) => {
  const menu = document.querySelector('#table-menu')
  if (menu && !menu.contains(event.target)) menu.remove()
})

function post(name, payload = {}) {
  const handler = window.webkit?.messageHandlers?.breathNotes
  if (!handler || !documentID) return
  handler.postMessage({
    name,
    documentID,
    version: documentVersion,
    ...payload,
  })
}

function renderedHeadings() {
  return Array.from(root.querySelectorAll('h1, h2, h3, h4, h5, h6'))
}

function activeHeadingFromViewport() {
  const headings = renderedHeadings()
  if (headings.length === 0) return null
  const activationY = Math.min(160, Math.max(72, window.innerHeight * 0.18))
  let activeIndex = 0
  headings.forEach((heading, index) => {
    if (heading.getBoundingClientRect().top <= activationY) {
      activeIndex = index
    }
  })
  return activeIndex
}

function activeHeadingFromEditorSelection() {
  let headingIndex = -1
  let activeIndex = null
  const selectionPosition = editor.state.selection.from
  editor.state.doc.descendants((node, position) => {
    if (node.type.name !== 'heading') return
    headingIndex += 1
    if (position <= selectionPosition) activeIndex = headingIndex
  })
  return activeIndex ?? (headingIndex >= 0 ? 0 : null)
}

function sourceHeadings() {
  return Array.from(
    source.value.matchAll(/^(#{1,6})[ \t]+.+$/gm),
    (match) => ({
      start: match.index ?? 0,
      end: (match.index ?? 0) + match[0].length,
      line: source.value.slice(0, match.index ?? 0).split('\n').length - 1,
    }),
  )
}

function activeHeadingFromSourceSelection() {
  const headings = sourceHeadings()
  if (headings.length === 0) return null
  let activeIndex = 0
  headings.forEach((heading, index) => {
    if (heading.start <= source.selectionStart) activeIndex = index
  })
  return activeIndex
}

function activeHeadingFromSourceViewport() {
  const headings = sourceHeadings()
  if (headings.length === 0) return null
  const lineHeight = Number.parseFloat(
    window.getComputedStyle(source).lineHeight,
  ) || 23
  const activationLine = (source.scrollTop + 72) / lineHeight
  let activeIndex = 0
  headings.forEach((heading, index) => {
    if (heading.line <= activationLine) activeIndex = index
  })
  return activeIndex
}

function reportActiveHeading(index) {
  const normalized = Number.isInteger(index) && index >= 0 ? index : null
  if (lastActiveHeadingIndex === normalized) return
  lastActiveHeadingIndex = normalized
  post('activeHeadingChange', { index: normalized })
}

function scheduleActiveHeadingFromViewport() {
  if (mode !== 'wysiwyg' || activeHeadingViewportFrame !== null) return
  activeHeadingViewportFrame = window.requestAnimationFrame(() => {
    activeHeadingViewportFrame = null
    reportActiveHeading(activeHeadingFromViewport())
  })
}

window.addEventListener(
  'scroll',
  scheduleActiveHeadingFromViewport,
  { passive: true },
)

function patchedMarkdown(nextNormalized) {
  return patchNormalizedMarkdown(
    originalSource,
    normalizedBaseline,
    nextNormalized,
  )
}

function beginSourceMode(markdown) {
  sourceModeOriginal = markdown
  source.value = markdown
  sourceModeBaseline = source.value
}

function sourceMarkdown() {
  return patchNormalizedMarkdown(
    sourceModeOriginal,
    sourceModeBaseline,
    source.value,
  )
}

function setMode(nextMode) {
  if (nextMode === mode) return
  if (nextMode === 'source') {
    beginSourceMode(patchedMarkdown(editor.getMarkdown()))
    mode = 'source'
  } else {
    const markdown = sourceMarkdown()
    isLoading = true
    editor.commands.setContent(sanitizeMarkdownForPreview(markdown), {
      contentType: 'markdown',
      emitUpdate: false,
    })
    isLoading = false
    originalSource = markdown
    normalizedBaseline = editor.getMarkdown()
    mode = 'wysiwyg'
  }
  document.body.dataset.mode = mode
  post('modeChange', { mode })
  reportActiveHeading(
    mode === 'source'
      ? activeHeadingFromSourceSelection()
      : activeHeadingFromViewport(),
  )
}

source.addEventListener('input', () => {
  if (isLoading || mode !== 'source') return
  const markdown = sourceMarkdown()
  sourceModeOriginal = markdown
  sourceModeBaseline = source.value
  post('editorChange', { content: markdown })
  reportActiveHeading(activeHeadingFromSourceSelection())
})

source.addEventListener('selectionchange', () => {
  if (mode === 'source') {
    reportActiveHeading(activeHeadingFromSourceSelection())
  }
})

source.addEventListener(
  'scroll',
  () => {
    if (mode === 'source') {
      reportActiveHeading(activeHeadingFromSourceViewport())
    }
  },
  { passive: true },
)

window.breathNotes = {
  load(payload) {
    documentID = payload.documentID
    documentVersion = payload.version
    setLanguage(payload.language)
    originalSource = payload.content ?? ''
    mode = payload.mode ?? 'wysiwyg'
    isLoading = true
    editor.commands.setContent(sanitizeMarkdownForPreview(originalSource), {
      contentType: 'markdown',
      emitUpdate: false,
    })
    normalizedBaseline = editor.getMarkdown()
    beginSourceMode(originalSource)
    document.body.dataset.mode = mode
    document.body.dataset.theme = payload.theme ?? 'github'
    document.body.dataset.appearance = payload.appearance ?? 'light'
    document.body.classList.toggle(
      'plain-text',
      payload.kind === 'plainText',
    )
    this.setPreferences(
      payload.showsCodeLineNumbers === true,
      payload.spellCheckEnabled !== false,
    )
    isLoading = false
    status.textContent = ''
    lastActiveHeadingIndex = undefined
    post('ready')
    window.requestAnimationFrame(() => {
      reportActiveHeading(
        mode === 'source'
          ? activeHeadingFromSourceSelection()
          : activeHeadingFromViewport(),
      )
    })
  },
  setMode,
  setLanguage,
  setTheme(theme, appearance) {
    document.body.dataset.theme = theme
    document.body.dataset.appearance = appearance
  },
  setPreferences(showsCodeLineNumbers, spellCheckEnabled) {
    document.body.classList.toggle(
      'show-code-line-numbers',
      showsCodeLineNumbers,
    )
    root.querySelector('.ProseMirror')?.setAttribute(
      'spellcheck',
      spellCheckEnabled ? 'true' : 'false',
    )
    source.spellcheck = spellCheckEnabled
    root.querySelectorAll('pre, code, a').forEach((element) => {
      element.setAttribute('spellcheck', 'false')
    })
  },
  insertAttachment(path, mimeType, filename) {
    const isImage = /^image\//.test(mimeType || '')
    const escapedPath = path.replaceAll('(', '\\(').replaceAll(')', '\\)')
    const label = (filename || ui.attachment)
      .replaceAll('[', '\\[')
      .replaceAll(']', '\\]')
    const markdown = isImage
      ? `![${label}](${escapedPath})`
      : `[${label}](${escapedPath})`
    if (mode === 'source') {
      const start = source.selectionStart
      const end = source.selectionEnd
      source.setRangeText(markdown, start, end, 'end')
      source.dispatchEvent(new InputEvent('input', { bubbles: true }))
    } else if (isImage) {
      editor.chain().focus().setImage({
        src: path,
        alt: filename || ui.attachment,
      }).run()
    } else {
      editor.chain().focus().insertContent(markdown).run()
    }
  },
  currentMarkdown() {
    return mode === 'source'
      ? sourceMarkdown()
      : patchedMarkdown(editor.getMarkdown())
  },
  focus() {
    if (mode === 'source') source.focus()
    else editor.commands.focus()
  },
  undo() {
    if (mode === 'source') document.execCommand('undo')
    else editor.commands.undo()
  },
  redo() {
    if (mode === 'source') document.execCommand('redo')
    else editor.commands.redo()
  },
  find(query, backwards = false) {
    return window.find(query, false, backwards, true, false, true, false)
  },
  scrollToHeading(index, behavior = 'smooth') {
    if (!Number.isInteger(index) || index < 0) return false
    if (mode === 'source') {
      const heading = sourceHeadings()[index]
      if (!heading) return false
      const lineHeight = Number.parseFloat(
        window.getComputedStyle(source).lineHeight,
      ) || 23
      source.focus()
      source.setSelectionRange(heading.start, heading.end)
      source.scrollTop = Math.max(
        0,
        heading.line * lineHeight - source.clientHeight * 0.2,
      )
    } else {
      const heading = renderedHeadings()[index]
      if (!heading) return false
      const top = window.scrollY
        + heading.getBoundingClientRect().top
        - 72
      window.scrollTo({ top: Math.max(0, top), behavior })
    }
    reportActiveHeading(index)
    return true
  },
  activeHeadingIndex() {
    return lastActiveHeadingIndex ?? null
  },
  highlightCode(language, code) {
    if (language && hljs.getLanguage(language)) {
      return hljs.highlight(code, { language }).value
    }
    return hljs.highlightAuto(code).value
  },
}

post('booted')
