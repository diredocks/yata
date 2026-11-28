import { Editor } from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import Underline from '@tiptap/extension-underline';
import Link from '@tiptap/extension-link';
import Placeholder from '@tiptap/extension-placeholder';
import DOMPurify from 'dompurify';

interface ThemeVars {
  bg?: string;
  fg?: string;
  muted?: string;
  accent?: string;
  isDark?: boolean;
}

interface InitOptions {
  html?: string;
  editable?: boolean;
  placeholder?: string;
  theme?: ThemeVars;
}

const styleEl = document.createElement('style');
styleEl.textContent = `
  :root {
    --bg: transparent;
    --fg: #1f1f1f;
    --muted: #6e6e6e;
    --accent: #2564cf;
  }
  * { box-sizing: border-box; }
  html, body {
    margin: 0;
    padding: 0;
    background: var(--bg);
    color: var(--fg);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    font-size: 16px;
    line-height: 1.5;
    -webkit-tap-highlight-color: transparent;
    word-wrap: break-word;
    overflow-wrap: break-word;
  }
  .note-surface {
    width: 100%;
    padding: 0;
    outline: none;
  }
  .ProseMirror {
    min-height: 200px;
    padding: 16px;
    outline: none;
  }
  .ProseMirror p.is-editor-empty:first-child::before {
    content: attr(data-placeholder);
    float: left;
    color: var(--muted);
    pointer-events: none;
    height: 0;
  }
  .note-surface p { margin: 0 0 0.5em 0; }
  .note-surface p:last-child { margin-bottom: 0; }
  .note-surface h1 { font-size: 20pt; font-weight: 700; margin: 0.4em 0; }
  .note-surface h2 { font-size: 17pt; font-weight: 600; margin: 0.35em 0; }
  .note-surface ul, .note-surface ol { padding-left: 1.4em; margin: 0.3em 0; }
  .note-surface a { color: var(--accent); text-decoration: underline; }
  .note-surface table { border-collapse: collapse; max-width: 100%; }
  .note-surface td, .note-surface th { border: 1px solid rgba(128,128,128,0.35); padding: 4px 8px; }
  .note-surface img { max-width: 100%; height: auto; }
`;
document.head.appendChild(styleEl);

const previewEl = document.getElementById('preview') as HTMLDivElement;
const editorEl = document.getElementById('editor') as HTMLDivElement;

let editor: Editor | null = null;
let suppressChange = false;
let changeTimer: number | null = null;

function postToFlutter(payload: Record<string, unknown>) {
  const bridge = (window as unknown as { YataBridge?: { postMessage: (msg: string) => void } }).YataBridge;
  if (bridge && typeof bridge.postMessage === 'function') {
    bridge.postMessage(JSON.stringify(payload));
  }
}

function applyTheme(theme?: ThemeVars) {
  if (!theme) return;
  const root = document.documentElement.style;
  if (theme.bg) root.setProperty('--bg', theme.bg);
  if (theme.fg) root.setProperty('--fg', theme.fg);
  if (theme.muted) root.setProperty('--muted', theme.muted);
  if (theme.accent) root.setProperty('--accent', theme.accent);
}

function sanitizeHtml(raw: string): string {
  return DOMPurify.sanitize(raw, {
    ALLOWED_URI_REGEXP: /^(?:(?:https?|mailto|tel):|[^a-z]|[a-z+.-]+(?:[^a-z+.-:]|$))/i,
  });
}

function extractBodyContent(raw: string): string {
  if (!raw) return '';
  const match = raw.match(/<body[^>]*>([\s\S]*?)<\/body>/i);
  return match ? match[1] : raw;
}

function emitFormatState() {
  if (!editor) return;
  const headingLevel = editor.isActive('heading', { level: 1 })
    ? 1
    : editor.isActive('heading', { level: 2 })
      ? 2
      : 0;
  postToFlutter({
    type: 'formatState',
    state: {
      bold: editor.isActive('bold'),
      italic: editor.isActive('italic'),
      underline: editor.isActive('underline'),
      strike: editor.isActive('strike'),
      bulletList: editor.isActive('bulletList'),
      orderedList: editor.isActive('orderedList'),
      headingLevel,
      canUndo: editor.can().undo(),
      canRedo: editor.can().redo(),
      canUnlink: editor.isActive('link'),
    },
  });
}

function scheduleContentChanged() {
  if (changeTimer !== null) {
    window.clearTimeout(changeTimer);
  }
  changeTimer = window.setTimeout(() => {
    if (!editor) return;
    postToFlutter({
      type: 'contentChanged',
      html: editor.getHTML(),
      plainText: editor.getText({ blockSeparator: '\n' }),
    });
  }, 250);
}

function ensureEditor(placeholder: string) {
  if (editor) return editor;
  editor = new Editor({
    element: editorEl,
    extensions: [
      StarterKit.configure({
        heading: { levels: [1, 2] },
      }),
      Underline,
      Link.configure({
        openOnClick: false,
        autolink: true,
      }),
      Placeholder.configure({
        placeholder,
      }),
    ],
    onUpdate: () => {
      if (suppressChange) return;
      emitFormatState();
      scheduleContentChanged();
    },
    onSelectionUpdate: () => {
      emitFormatState();
    },
  });
  return editor;
}

const resizeObserver = new ResizeObserver(() => {
  if (!previewEl.hidden) {
    postToFlutter({
      type: 'heightChanged',
      height: Math.ceil(previewEl.scrollHeight),
    });
  }
});
resizeObserver.observe(previewEl);

previewEl.addEventListener('click', (e) => {
  const target = e.target as HTMLElement | null;
  const anchor = target?.closest('a');
  if (anchor && anchor.getAttribute('href')) {
    e.preventDefault();
    postToFlutter({ type: 'linkTap', url: anchor.getAttribute('href') });
    return;
  }
  postToFlutter({ type: 'tapEmpty' });
});

const YataEditor = {
  init(opts: InitOptions = {}) {
    applyTheme(opts.theme);
    const editable = Boolean(opts.editable);
    const bodyHtml = extractBodyContent(opts.html || '');

    if (editable) {
      previewEl.hidden = true;
      editorEl.hidden = false;
      const ed = ensureEditor(opts.placeholder || 'Add note');
      suppressChange = true;
      ed.commands.setContent(sanitizeHtml(bodyHtml), false);
      suppressChange = false;
      emitFormatState();
    } else {
      editorEl.hidden = true;
      previewEl.hidden = false;
      previewEl.innerHTML = sanitizeHtml(bodyHtml);
      postToFlutter({
        type: 'heightChanged',
        height: Math.ceil(previewEl.scrollHeight),
      });
    }
  },

  setTheme(theme: ThemeVars) {
    applyTheme(theme);
  },

  setContent(html: string, editable = true) {
    this.init({ html, editable });
  },

  exec(cmd: string, arg?: string) {
    if (!editor) return;
    const chain = editor.chain().focus();
    switch (cmd) {
      case 'bold':
        chain.toggleBold().run();
        break;
      case 'italic':
        chain.toggleItalic().run();
        break;
      case 'underline':
        chain.toggleUnderline().run();
        break;
      case 'strike':
        chain.toggleStrike().run();
        break;
      case 'bulletList':
        chain.toggleBulletList().run();
        break;
      case 'orderedList':
        chain.toggleOrderedList().run();
        break;
      case 'heading1':
        chain.toggleHeading({ level: 1 }).run();
        break;
      case 'heading2':
        chain.toggleHeading({ level: 2 }).run();
        break;
      case 'paragraph':
        chain.setParagraph().run();
        break;
      case 'setLink':
        if (arg) chain.setLink({ href: arg }).run();
        break;
      case 'unsetLink':
        chain.unsetLink().run();
        break;
      case 'undo':
        chain.undo().run();
        break;
      case 'redo':
        chain.redo().run();
        break;
      case 'focus':
        editor.commands.focus('end');
        break;
    }
    emitFormatState();
  },

  getContent() {
    if (!editor) {
      return { html: previewEl.innerHTML, plainText: previewEl.innerText };
    }
    return {
      html: editor.getHTML(),
      plainText: editor.getText({ blockSeparator: '\n' }),
    };
  },
};

(window as unknown as { YataEditor: typeof YataEditor }).YataEditor = YataEditor;
postToFlutter({ type: 'ready' });
