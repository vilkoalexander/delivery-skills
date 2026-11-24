#!/usr/bin/env node
// The named functions of one source file and the cyclomatic complexity of
// each: one plus its branches. Reads the text, not a syntax tree: a body it
// cannot name counts toward the function around it, and a file whose brackets
// do not balance prints nothing and exits 3.
//
//   node complexity.mjs <js|java|kt> < source     name<TAB>line<TAB>complexity
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const NOT_A_FUNCTION = new Set(['if', 'for', 'while', 'switch', 'catch', 'with', 'synchronized', 'try', 'when', 'function', 'return']);
const OPENS_A_TYPE = new Set(['class', 'record', 'interface', 'enum', 'object']);
const BRANCHES = {
  js: /\b(?:if|for|while|case|catch)\b|&&|\|\||\?\?|\?/g,
  java: /\b(?:if|for|while|case|catch)\b|&&|\|\||\?/g,
  kt: /\b(?:if|for|while|catch)\b|&&|\|\||\?:/g,
};
const BLOCK = { kind: 'block' };

// Comments, strings and regex literals become spaces, so every offset and line stays where it was.
export function blank(source, lang) {
  const out = source.split('');
  const length = source.length;
  const isJs = lang === 'js';

  const wipe = (from, to) => {
    for (let at = from; at < to; at++) if (out[at] !== '\n') out[at] = ' ';
  };
  // 0 when the line ends first: an apostrophe in JSX text is not a string.
  const quotedEnd = (from, quote) => {
    let at = from + 1;
    while (at < length && source[at] !== quote) {
      if (source[at] === '\n') return 0;
      at += source[at] === '\\' ? 2 : 1;
    }
    return Math.min(at + 1, length);
  };
  const templateEnd = from => {
    let at = from + 1;
    while (at < length) {
      if (source[at] === '\\') at += 2;
      else if (source[at] === '`') return at + 1;
      else if (source[at] === '$' && source[at + 1] === '{') at = expressionEnd(at + 2);
      else at++;
    }
    return length;
  };
  const expressionEnd = from => {
    let at = from;
    let depth = 1;
    let previous = '{';
    while (at < length && depth > 0) {
      const literal = literalAt(at, previous);
      if (literal) {
        if (!literal.isComment) previous = '"';
        at = literal.end;
        continue;
      }
      const char = source[at];
      if (char === '{') depth++;
      if (char === '}') depth--;
      if (!/\s/.test(char)) previous = char;
      at++;
    }
    return at;
  };
  const regexEnd = from => {
    let at = from + 1;
    let inClass = false;
    while (at < length && source[at] !== '\n') {
      const char = source[at];
      if (char === '\\') at++;
      else if (char === '[') inClass = true;
      else if (char === ']') inClass = false;
      else if (char === '/' && !inClass) {
        at++;
        while (/[a-z]/.test(source[at] || '')) at++;
        return at;
      }
      at++;
    }
    return 0;
  };
  const startsRegex = (at, previous) =>
    previous === '' || '(,=:[!&|?{;'.includes(previous) || /\b(?:return|typeof)\s*$/.test(source.slice(Math.max(0, at - 8), at));

  // The comment, string, template or regex that starts at `at`; null when code does.
  const literalAt = (at, previous) => {
    const char = source[at];
    const next = source[at + 1];
    const until = (closer, from) => {
      const found = source.indexOf(closer, from);
      return found < 0 ? length : found + closer.length;
    };
    if (char === '/' && next === '/') {
      const newline = source.indexOf('\n', at);
      return { end: newline < 0 ? length : newline, isComment: true };
    }
    if (char === '/' && next === '*') return { end: until('*/', at + 2), isComment: true };
    let end = 0;
    if (!isJs && source.startsWith('"""', at)) end = until('"""', at + 3);
    else if (char === '"' || char === "'") end = quotedEnd(at, char);
    else if (isJs && char === '`') end = templateEnd(at);
    else if (isJs && char === '/' && startsRegex(at, previous)) end = regexEnd(at);
    return end ? { end, isComment: false } : null;
  };

  let at = 0;
  let previous = '';
  while (at < length) {
    const literal = literalAt(at, previous);
    if (literal) {
      wipe(at, literal.end);
      if (!literal.isComment) previous = '"';
      at = literal.end;
      continue;
    }
    if (!/\s/.test(source[at])) previous = source[at];
    at++;
  }
  return out.join('');
}

function lastCodeBefore(text, at) {
  let index = at - 1;
  while (index >= 0 && /\s/.test(text[index])) index--;
  return index;
}

function wordEndingAt(text, end) {
  let start = end;
  while (start >= 0 && /[\w$]/.test(text[start])) start--;
  if (start === end) return null;
  return { name: text.slice(start + 1, end + 1), start: start + 1 };
}

function lastOf(text, chars, before) {
  let index = before - 1;
  while (index >= 0 && !chars.includes(text[index])) index--;
  return index;
}

const skipGeneric = (text, at) => (text[at] === '>' && text[at - 1] !== '=' ? lastCodeBefore(text, text.lastIndexOf('<', at)) : at);

// `name = (…) => {` and `name: (…) => {` are functions; an arrow passed as an argument is not.
function arrowAt(text, arrow, openOf) {
  const last = lastCodeBefore(text, arrow);
  let open;
  if (text[last] === ')') {
    open = openOf.get(last);
  } else {
    const close = lastOf(text, ';{}(=)', last + 1);
    const hasReturnType = close >= 0 && text[close] === ')' && /^\s*:/.test(text.slice(close + 1, last + 1));
    open = hasReturnType ? openOf.get(close) : wordEndingAt(text, last)?.start;
  }
  if (open === undefined) return BLOCK;

  let at = skipGeneric(text, lastCodeBefore(text, open));
  const word = wordEndingAt(text, at);
  if (word?.name === 'async') at = lastCodeBefore(text, word.start);

  if (text[at] === ':') {
    const key = wordEndingAt(text, lastCodeBefore(text, at));
    return key ? { kind: 'function', name: key.name, at: key.start } : BLOCK;
  }
  if (text[at] !== '=' || '=!<>'.includes(text[at - 1])) return BLOCK;

  const from = Math.max(lastOf(text, ';{}(,', at) + 1, at - 300);
  const declared = /([A-Za-z_$][\w$]*)\s*(?:[?!]?:[^=]*)?$/.exec(text.slice(from, at));
  return declared ? { kind: 'function', name: declared[1], at: from + declared.index } : BLOCK;
}

function typeAt(text, brace) {
  const from = Math.max(lastOf(text, ';{}', brace) + 1, brace - 500);
  const declared = /\b(?:class|interface|enum|object|record)\s+([A-Za-z_$][\w$]*)/.exec(text.slice(from, brace));
  return declared ? { kind: 'type', name: declared[1] } : BLOCK;
}

// What the `{` at `brace` opens: a named function, a type, or a plain block.
function opens(text, brace, openOf, lang) {
  const last = lastCodeBefore(text, brace);
  if (last < 1) return BLOCK;
  if (text[last] === '>' && text[last - 1] === '=') return arrowAt(text, last - 1, openOf);

  const close = lastOf(text, ';{}(=)', brace);
  const afterParams = close >= 0 && text[close] === ')' ? text.slice(close + 1, brace) : null;
  if (afterParams === null || !/^\s*(?::|throws\s|$)/.test(afterParams)) return typeAt(text, brace);

  const open = openOf.get(close);
  if (open === undefined) return BLOCK;
  const name = wordEndingAt(text, skipGeneric(text, lastCodeBefore(text, open)));
  if (!name || NOT_A_FUNCTION.has(name.name)) return BLOCK;

  const before = wordEndingAt(text, lastCodeBefore(text, name.start))?.name;
  if (before === 'new') return BLOCK;
  if (OPENS_A_TYPE.has(before)) return { kind: 'type', name: name.name };
  if (lang === 'kt' && name.name !== 'constructor') {
    const line = text.slice(text.lastIndexOf('\n', name.start) + 1, name.start);
    if (!/\bfun\b/.test(line)) return typeAt(text, brace);
  }
  return { kind: 'function', name: name.name, at: name.start };
}

function branchOffsets(text, lang) {
  const offsets = new Set();
  for (const match of text.matchAll(BRANCHES[lang])) {
    if (match[0] === '?') {
      // Optional markers and wildcards are not a ternary: `a?.b`, `a?: T`, `f?()`, `List<?>`.
      const next = text[match.index + 1] || '';
      const previous = text[match.index - 1] || '';
      if ('.:?),>=;]('.includes(next) || '?<'.includes(previous)) continue;
    }
    offsets.add(match.index);
  }
  return offsets;
}

// Null when the brackets do not balance.
export function functions(source, lang) {
  const text = blank(source, lang);
  const branches = branchOffsets(text, lang);
  const openOf = new Map();
  const stack = [];
  const found = [];
  const closes = { ')': '(', ']': '[', '}': '{' };

  for (let at = 0; at < text.length; at++) {
    const char = text[at];
    if (branches.has(at)) {
      for (let depth = stack.length - 1; depth >= 0; depth--) {
        if (stack[depth].kind === 'function') {
          stack[depth].branches++;
          break;
        }
      }
    }
    if (char === '(' || char === '[') {
      stack.push({ char, at, kind: 'bracket' });
    } else if (char === '{') {
      const scope = opens(text, at, openOf, lang);
      const types = stack.filter(entry => entry.kind === 'type').map(entry => entry.own);
      stack.push({ ...scope, char, branches: 0, own: scope.name, name: [...types, scope.name].join('.') });
    } else if (char in closes) {
      const top = stack.pop();
      if (!top || top.char !== closes[char]) return null;
      if (char === ')') openOf.set(at, top.at);
      if (top.kind === 'function') found.push(top);
    }
  }
  if (stack.length) return null;

  const seen = new Map();
  return found
    .sort((a, b) => a.at - b.at)
    .map(unit => {
      const count = (seen.get(unit.name) || 0) + 1;
      seen.set(unit.name, count);
      return {
        name: count === 1 ? unit.name : `${unit.name}#${count}`,
        line: text.slice(0, unit.at).split('\n').length,
        complexity: unit.branches + 1,
      };
    });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const lang = process.argv[2];
  if (!BRANCHES[lang]) {
    console.error('usage: complexity.mjs <js|java|kt> < source');
    process.exit(2);
  }
  const units = functions(readFileSync(0, 'utf8'), lang);
  if (!units) process.exit(3);
  for (const unit of units) console.log(`${unit.name}\t${unit.line}\t${unit.complexity}`);
}
