#!/usr/bin/env node
// Splits a Bash command line into the simple commands it runs, so guard.sh
// applies its rules to argv arrays and not to text. It looks inside quotes,
// groups, $( ), backticks, `bash -c`, `eval`, `xargs` and `find -exec`, and it
// drops wrappers (env, sudo, command, exec, time, nohup, a path before the
// name) and the options git takes before its subcommand.
//
//   node command.mjs < command          JSON: {"ok":true,"commands":[{"argv":[...],"redirects":[{"op":">","target":"x"}]}]}
//   node command.mjs --lines < command  one line per command, fields split by the unit separator (0x1f):
//                                       C name arg...     R op target     X when the text does not parse
//
// It is not a shell. A command whose name is built at run time comes out with
// the name "?", and text it cannot read comes out as not ok; guard.sh decides
// what to do with both.
import { readFileSync } from 'node:fs';
import { basename } from 'node:path';
import { fileURLToPath } from 'node:url';

class Unparsed extends Error {}

const MAX_DEPTH = 8;
const KEYWORDS = new Set(['if', 'then', 'elif', 'else', 'while', 'until', 'do', '!', '{', '}', 'time', 'fi', 'done', 'esac']);
const SHELLS = new Set(['bash', 'sh', 'zsh', 'dash', 'ksh']);
const ASSIGNMENT = /^[A-Za-z_][A-Za-z0-9_]*(\[[^\]]*\])?\+?=/;

// wrapper: the options of its own that take a value
const WRAPPERS = {
  command: [],
  builtin: [],
  exec: ['-a'],
  nohup: [],
  sudo: ['-u', '-g', '-h', '-p', '-C', '-D', '-R', '-T', '-U', '-r', '-t'],
  doas: ['-u', '-C'],
  env: ['-u', '-C', '-S'],
  nice: ['-n'],
  ionice: ['-c', '-n', '-p'],
  stdbuf: ['-i', '-o', '-e'],
  timeout: ['-s', '-k'],
  caffeinate: ['-t', '-w'],
  setsid: [],
  xargs: ['-n', '-I', '-P', '-L', '-s', '-d', '-E', '-a', '-J', '-R', '-S'],
};
const GIT_OPTIONS_WITH_VALUE = new Set(['-C', '-c', '--git-dir', '--work-tree', '--namespace', '--super-prefix', '--config-env']);

function closing(text, from, quote) {
  for (let at = from; at < text.length; at++) {
    if (text[at] === '\\' && quote !== "'") at++;
    else if (text[at] === quote) return at;
  }
  throw new Unparsed(`no closing ${quote}`);
}

// The index of the ")" that closes the "(" at `open`.
function closingParen(text, open) {
  let depth = 0;
  for (let at = open; at < text.length; at++) {
    const char = text[at];
    if (char === '\\') at++;
    else if (char === "'" || char === '"' || char === '`') at = closing(text, at + 1, char);
    else if (char === '(') depth++;
    else if (char === ')' && --depth === 0) return at;
  }
  throw new Unparsed('no closing )');
}

// Command text that runs inside a word: $( ), backticks, <( ).
function substitutions(text, inner) {
  for (let at = 0; at < text.length; at++) {
    const char = text[at];
    if (char === '\\') at++;
    else if (char === "'") at = closing(text, at + 1, "'");
    else if (char === '`') {
      const end = closing(text, at + 1, '`');
      inner.push(text.slice(at + 1, end));
      at = end;
    } else if ((char === '$' || char === '<' || char === '>') && text[at + 1] === '(') {
      const end = closingParen(text, at + 1);
      inner.push(text.slice(at + 2, end));
      at = end;
    }
  }
}

function tokenize(text, inner) {
  const tokens = [];
  const heredocs = [];
  let word = null;
  let at = 0;

  const add = piece => {
    word = (word ?? '') + piece;
  };
  const flush = () => {
    if (word !== null) tokens.push({ type: 'word', value: word });
    word = null;
  };
  const operator = (value, length = value.length) => {
    flush();
    tokens.push({ type: 'op', value });
    at += length;
  };
  const redirect = (op, length = op.length) => {
    let fd = null;
    if (word !== null && /^[0-9]+$/.test(word)) {
      fd = word;
      word = null;
    }
    flush();
    tokens.push({ type: 'redirect', op, fd });
    at += length;
  };
  const substitution = open => {
    const end = closingParen(text, open);
    inner.push(text.slice(open + 1, end));
    add(text.slice(at, end + 1));
    at = end + 1;
  };

  const readHeredocs = () => {
    for (const { delimiter, quoted, stripTabs } of heredocs.splice(0)) {
      const body = [];
      while (at < text.length) {
        let end = text.indexOf('\n', at);
        if (end === -1) end = text.length;
        const line = text.slice(at, end);
        at = Math.min(end + 1, text.length);
        if ((stripTabs ? line.replace(/^\t+/, '') : line) === delimiter) break;
        body.push(line);
      }
      if (!quoted) substitutions(body.join('\n').replace(/['"]/g, ' '), inner);
    }
  };

  const heredoc = () => {
    flush();
    at += 2;
    const stripTabs = text[at] === '-';
    if (stripTabs) at++;
    while (text[at] === ' ' || text[at] === '\t') at++;
    let delimiter = '';
    let quoted = false;
    while (at < text.length && !/[\s;&|<>()]/.test(text[at])) {
      const char = text[at];
      if (char === "'" || char === '"') {
        const end = closing(text, at + 1, char);
        delimiter += text.slice(at + 1, end);
        quoted = true;
        at = end + 1;
      } else if (char === '\\') {
        delimiter += text[at + 1] ?? '';
        quoted = true;
        at += 2;
      } else {
        delimiter += char;
        at++;
      }
    }
    if (!delimiter) throw new Unparsed('heredoc with no delimiter');
    heredocs.push({ delimiter, quoted, stripTabs });
  };

  const doubleQuoted = () => {
    const end = closing(text, at + 1, '"');
    const body = text.slice(at + 1, end);
    substitutions(body.replace(/'/g, ' '), inner);
    add(body.replace(/\\([$`"\\\n])/g, '$1'));
    at = end + 1;
  };

  while (at < text.length) {
    const char = text[at];
    const next = text[at + 1];
    if (char === '\\') {
      if (next !== '\n') add(next ?? '');
      at += 2;
    } else if (char === "'") {
      const end = closing(text, at + 1, "'");
      add(text.slice(at + 1, end));
      at = end + 1;
    } else if (char === '"') doubleQuoted();
    else if (char === '`') {
      const end = closing(text, at + 1, '`');
      inner.push(text.slice(at + 1, end));
      add(text.slice(at, end + 1));
      at = end + 1;
    } else if (char === '$' && next === '(') substitution(at + 1);
    else if (char === '$' && next === '{') {
      const end = closing(text, at + 2, '}');
      substitutions(text.slice(at + 2, end), inner);
      add(text.slice(at, end + 1));
      at = end + 1;
    } else if (char === '$' && next === "'") {
      const end = closing(text, at + 2, "'");
      add(text.slice(at + 2, end));
      at = end + 1;
    } else if (char === ' ' || char === '\t') {
      flush();
      at++;
    } else if (char === '\n') {
      operator('\n');
      readHeredocs();
    } else if (char === '#' && word === null) {
      while (at < text.length && text[at] !== '\n') at++;
    } else if (char === ';') operator(';', next === ';' || next === '&' ? 2 : 1);
    else if (char === '&' && next === '&') operator('&&');
    else if (char === '&' && next === '>') redirect('&>', text[at + 2] === '>' ? 3 : 2);
    else if (char === '&') operator('&');
    else if (char === '|') operator('|', next === '|' || next === '&' ? 2 : 1);
    else if (char === '(' && word !== null && word.endsWith('=')) {
      const end = closingParen(text, at);
      substitutions(text.slice(at + 1, end), inner);
      add(text.slice(at, end + 1));
      at = end + 1;
    }
    else if (char === '(' || char === ')') operator(char);
    else if ((char === '<' || char === '>') && next === '(') substitution(at + 1);
    else if (char === '<' && next === '<' && text[at + 2] === '<') redirect('<<<');
    else if (char === '<' && next === '<') heredoc();
    else if (char === '<') redirect(next === '&' ? '<&' : next === '>' ? '<>' : '<');
    else if (char === '>') redirect(next === '>' ? '>>' : next === '&' ? '>&' : next === '|' ? '>|' : '>');
    else {
      add(char);
      at++;
    }
  }
  flush();
  return tokens;
}

// The simple commands of the tokens: words and redirects up to each operator.
function simpleCommands(tokens) {
  const commands = [];
  let current = { words: [], redirects: [] };
  const finish = () => {
    if (current.words.length || current.redirects.length) commands.push(current);
    current = { words: [], redirects: [] };
  };
  for (let index = 0; index < tokens.length; index++) {
    const token = tokens[index];
    if (token.type === 'op') finish();
    else if (token.type === 'word') current.words.push(token.value);
    else {
      const target = tokens[index + 1];
      if (target?.type !== 'word') throw new Unparsed('redirect with no target');
      index++;
      const duplicatesFd = (token.op === '>&' || token.op === '<&') && /^([0-9]+|-)$/.test(target.value);
      if (!duplicatesFd) current.redirects.push({ op: token.op, target: target.value });
    }
  }
  finish();
  return commands;
}

function withoutOwnOptions(words, withValue) {
  let index = 1;
  while (index < words.length) {
    const word = words[index];
    if (word === '--') return words.slice(index + 1);
    if (ASSIGNMENT.test(word)) index++;
    else if (!word.startsWith('-') || word === '-') break;
    else index += withValue.includes(word) ? 2 : 1;
  }
  return words.slice(index);
}

// `bash -c STRING`: the string, or null when the shell runs a file.
function shellString(words) {
  let runsString = false;
  for (let index = 1; index < words.length; index++) {
    const word = words[index];
    if (/^[-+]o$/.test(word) || word === '-O' || word === '--rcfile' || word === '--init-file') index++;
    else if (word.startsWith('--')) continue;
    else if (/^[-+]/.test(word)) runsString ||= word.startsWith('-') && word.includes('c');
    else return runsString ? word : null;
  }
  return null;
}

function findExecs(words) {
  const found = [];
  for (let index = 1; index < words.length; index++) {
    if (!/^-(exec|execdir|ok|okdir)$/.test(words[index])) continue;
    let end = index + 1;
    while (end < words.length && words[end] !== ';' && words[end] !== '+') end++;
    found.push(words.slice(index + 1, end));
    index = end;
  }
  return found;
}

// A config key whose value git runs as a command, so a read-only subcommand is no longer read-only.
const GIT_CONFIG_RUNS = /^(alias\.|pager\.|core\.(fsmonitor|pager|editor|sshcommand|hookspath|gitproxy)|diff\.external|.*\.(textconv|command|helper|cmd|driver))/i;

function gitArgv(words) {
  let index = 1;
  while (index < words.length && words[index].startsWith('-')) {
    const value = words[index + 1] ?? '';
    if ((words[index] === '-c' || words[index] === '--config-env') && GIT_CONFIG_RUNS.test(value)) {
      return ['git', 'config-that-runs-a-command'];
    }
    index += GIT_OPTIONS_WITH_VALUE.has(words[index]) ? 2 : 1;
  }
  const globalFlags = words.slice(1, index).filter(word => word === '--help' || word === '--version');
  return ['git', ...(index < words.length ? words.slice(index) : globalFlags)];
}

function expand(words, redirects, out, depth) {
  let rest = [...words];
  while (rest.length && (KEYWORDS.has(rest[0]) || ASSIGNMENT.test(rest[0]))) rest.shift();
  if (rest[0] === '-p' && words.includes('time')) rest.shift();
  if (!rest.length) {
    if (redirects.length) out.push({ argv: [], redirects });
    return;
  }

  const name = /^[$`]/.test(rest[0]) ? '?' : basename(rest[0]);
  const emit = argv => out.push({ argv, redirects });
  const inside = text => {
    if (depth >= MAX_DEPTH) throw new Unparsed('nested too deep');
    for (const command of parse(text, depth + 1)) out.push({ ...command, redirects: [...command.redirects, ...redirects] });
  };

  if (name === 'command' && /^-[vV]$/.test(rest[1] ?? '')) emit([name, ...rest.slice(1)]);
  else if (name in WRAPPERS) {
    let wrapped = withoutOwnOptions(rest, WRAPPERS[name]);
    if (name === 'timeout') wrapped = wrapped.slice(1);
    if (wrapped.length) expand(wrapped, redirects, out, depth);
    else emit([name]);
  } else if (name === 'eval') inside(rest.slice(1).join(' '));
  else if (SHELLS.has(name)) {
    const script = shellString(rest);
    if (script === null) emit([name, ...rest.slice(1)]);
    else inside(script);
  } else if (name === 'find') {
    emit([name, ...rest.slice(1)]);
    for (const exec of findExecs(rest)) if (exec.length) expand(exec, [], out, depth);
  } else if (name === 'git') emit(gitArgv(rest));
  else emit([name, ...rest.slice(1)]);
}

export function parse(text, depth = 0) {
  const inner = [];
  const out = [];
  for (const { words, redirects } of simpleCommands(tokenize(text, inner))) expand(words, redirects, out, depth);
  for (const piece of inner) {
    if (depth >= MAX_DEPTH) throw new Unparsed('nested too deep');
    out.push(...parse(piece, depth + 1));
  }
  return out;
}

export function read(text) {
  try {
    return { ok: true, commands: parse(text) };
  } catch (error) {
    if (!(error instanceof Unparsed)) throw error;
    return { ok: false, reason: error.message };
  }
}

const SEPARATOR = '\x1f';
const oneLine = value => value.replace(/[\n\x1f]/g, ' ');

function lines(result) {
  if (!result.ok) return 'X';
  const printed = [];
  for (const { argv, redirects } of result.commands) {
    if (argv.length) printed.push(['C', ...argv].map(oneLine).join(SEPARATOR));
    for (const { op, target } of redirects) printed.push(['R', op, oneLine(target)].join(SEPARATOR));
  }
  return printed.join('\n');
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  let result;
  try {
    result = read(readFileSync(0, 'utf8'));
  } catch {
    result = { ok: false, reason: 'the reader failed' };
  }
  console.log(process.argv[2] === '--lines' ? lines(result) : JSON.stringify(result));
}
