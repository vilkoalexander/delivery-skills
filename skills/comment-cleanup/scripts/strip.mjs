#!/usr/bin/env node
// Prints the source on stdin with its comments and its whitespace outside
// strings removed, one line per source line that still holds code. Two
// versions of a file that print the same differ in comments only.
//
// Usage: node strip.mjs <file-name> < source
// A comment that a tool reads stays in the output: removing it changes behaviour.
import { readFileSync } from 'node:fs';

const name = process.argv[2] ?? '';
const source = readFileSync(0, 'utf8');
const markup = /\.(html?|vue|svelte|xml|svg)$/i.test(name);

const directive =
  /eslint-(disable|enable)|@ts-(expect-error|ignore|nocheck|check)|prettier-ignore|biome-ignore|(istanbul|c8|v8) ignore|webpack[A-Z]|@vite-ignore|<reference |@(jest|vitest)-environment|sourceMappingURL/;
const regexMayFollow = new Set([...'(,=:[!&|?{};+-*%~^']);
const regexMayFollowWord = /(^|[^A-Za-z0-9_$])(return|typeof|case|in|of|delete|void|throw|new|else|do)$/;

let out = '';
let position = 0;

const keep = (text) => {
  out += text;
};
const keepLiteral = (text) => {
  out += text.replace(/\n/g, '\\n');
};
const lastCode = () => out.replace(/\n+$/, '').slice(-1);

function comment(text) {
  if (directive.test(text)) keepLiteral(text.replace(/\s+/g, ' '));
}

function quoted(quote) {
  let end = position + 1;
  while (end < source.length && source[end] !== quote && source[end] !== '\n') {
    end += source[end] === '\\' ? 2 : 1;
  }
  if (source[end] === quote) end += 1;
  keepLiteral(source.slice(position, end));
  position = end;
}

function template() {
  keep('`');
  position += 1;
  while (position < source.length && source[position] !== '`') {
    if (source[position] === '\\') {
      keepLiteral(source.slice(position, position + 2));
      position += 2;
    } else if (source.startsWith('${', position)) {
      keep('${');
      position += 2;
      code('}');
    } else {
      keepLiteral(source[position]);
      position += 1;
    }
  }
  keep('`');
  position += 1;
}

function regexLiteral() {
  let end = position + 1;
  let inClass = false;
  while (end < source.length && source[end] !== '\n') {
    const char = source[end];
    if (char === '\\') end += 1;
    else if (char === '[') inClass = true;
    else if (char === ']') inClass = false;
    else if (char === '/' && !inClass) break;
    end += 1;
  }
  if (source[end] !== '/') return false;
  keepLiteral(source.slice(position, end + 1));
  position = end + 1;
  return true;
}

function startsRegex() {
  const before = lastCode();
  return before === '' || regexMayFollow.has(before) || regexMayFollowWord.test(out.slice(-12));
}

function jsxComment() {
  const match = /^\{\s*\/\*[\s\S]*?\*\/\s*\}/.exec(source.slice(position));
  if (!match) return false;
  comment(match[0]);
  position += match[0].length;
  return true;
}

function code(until) {
  let depth = 0;
  while (position < source.length) {
    const char = source[position];
    if (until && char === until && depth === 0) {
      keep(char);
      position += 1;
      return;
    }
    if (markup) {
      if (source.startsWith('<!--', position)) {
        const end = source.indexOf('-->', position);
        position = end < 0 ? source.length : end + 3;
      } else {
        keep(/[ \t\r]/.test(char) ? '' : char);
        position += 1;
      }
      continue;
    }
    if (char === '{' && jsxComment()) continue;
    if (source.startsWith('/*', position)) {
      const end = source.indexOf('*/', position + 2);
      const stop = end < 0 ? source.length : end + 2;
      comment(source.slice(position, stop));
      position = stop;
    } else if (source.startsWith('//', position) && source[position - 1] !== ':') {
      const end = source.indexOf('\n', position);
      const stop = end < 0 ? source.length : end;
      comment(source.slice(position, stop));
      position = stop;
    } else if (char === '"' || char === "'") {
      quoted(char);
    } else if (char === '`') {
      template();
    } else if (char === '/' && startsRegex() && regexLiteral()) {
      continue;
    } else {
      if (char === '{') depth += 1;
      if (char === '}') depth -= 1;
      keep(/[ \t\r]/.test(char) ? '' : char);
      position += 1;
    }
  }
}

code();
process.stdout.write(
  out
    .split('\n')
    .filter((line) => line !== '')
    .join('\n') + '\n',
);
