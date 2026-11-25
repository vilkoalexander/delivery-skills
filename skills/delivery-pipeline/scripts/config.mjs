#!/usr/bin/env node
// The project's delivery config, docs/review/delivery.json: what the stack is,
// which command each static step runs per workspace, and the project's own
// patterns. The gate runs what this file names and guesses nothing.
//
//   node config.mjs check            validate; silent when fine, exit 2 with the reason
//   node config.mjs get <key>        a scalar as is; a pattern list as one ERE; nothing when unset
//                                    (`writing` is ste100 when unset)
//   node config.mjs plan <path>...   the steps the changed paths call for, tab-separated:
//                                    RUN|SKIP  workspace  step  command-or-reason
//   node config.mjs init             write a first draft from what the repo has; never overwrites
//
//   DELIVERY_CONFIG   path of the file (default: <git root>/docs/review/delivery.json)
//
// A step is a command string, `false` for "this workspace has none", or
// { "run": "...", "files": "<ERE>" } to run only when a changed path matches.
// Commands run in the workspace directory; {files} becomes the changed paths
// that still exist, relative to it.
//
// Two pattern dialects, by who reads the pattern. `check` compiles each one with its reader:
//   POSIX ERE (grep, bash)   risk.high, risk.medium, secrets.allow, shared
//   JavaScript RegExp (node) a step's `files`, deps.allow
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

export const STEPS = ['typecheck', 'lint', 'format', 'test'];
// escapes and erosion: read by scans that are gone; a config that still has them stays valid.
const KEYS = ['stack', 'workspaces', 'writing', 'risk', 'secrets', 'escapes', 'erosion', 'deps', 'shared'];
const WRITING = ['ste100', 'free'];
const DEFAULTS = { writing: 'ste100' };
const CODE = '\\.[cm]?[jt]sx?$';

function git(...args) {
  try {
    return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return '';
  }
}

export const root = () => git('rev-parse', '--show-toplevel') || process.cwd();
export const file = () => process.env.DELIVERY_CONFIG || join(root(), 'docs/review/delivery.json');
export const ere = patterns => (patterns || []).map(pattern => `(${pattern})`).join('|');

class Invalid extends Error {}

function invalid(message) {
  throw new Invalid(message);
}

const isOff = step => step === false || step === null;
const commandOf = step => (step && typeof step === 'object' ? step.run : step);

const compiles = {
  ere: pattern => spawnSync('grep', ['-E', '--', pattern], { input: '' }).status <= 1,
  js: pattern => {
    try {
      new RegExp(pattern);
      return true;
    } catch {
      return false;
    }
  },
};
const DIALECT = { ere: 'POSIX ERE', js: 'JavaScript' };

function checkPattern(path, name, pattern, dialect) {
  if (!compiles[dialect](pattern)) invalid(`${path}: ${name} is not a valid ${DIALECT[dialect]} pattern: ${pattern}`);
}

function checkPatternList(path, name, value, dialect) {
  if (value === undefined) return;
  const isList = Array.isArray(value) && value.every(pattern => typeof pattern === 'string');
  if (!isList) invalid(`${path}: ${name} must be a list of patterns`);
  if (dialect) for (const pattern of value) checkPattern(path, name, pattern, dialect);
}

function checkDays(path, name, value) {
  if (value !== undefined && !(typeof value === 'number' && value >= 0)) {
    invalid(`${path}: ${name} must be a number of days, 0 or more`);
  }
}

function checkWorkspaces(path, workspaces) {
  const named = workspaces && typeof workspaces === 'object' && Object.keys(workspaces).length;
  if (!named) invalid(`${path}: workspaces must name at least one directory ("." for the root)`);

  for (const [dir, steps] of Object.entries(workspaces)) {
    if (!steps || typeof steps !== 'object') invalid(`${path}: workspaces["${dir}"] must be an object of steps`);

    for (const [name, step] of Object.entries(steps)) {
      if (isOff(step)) continue;
      const command = commandOf(step);
      const oneLine = typeof command === 'string' && command.trim() && !/[\t\n]/.test(command);
      if (!oneLine) invalid(`${path}: workspaces["${dir}"].${name} must be a one-line command, false, or { run, files }`);
      if (typeof step === 'object' && typeof step.files !== 'string') {
        invalid(`${path}: workspaces["${dir}"].${name}.files must be a pattern`);
      }
      if (typeof step === 'object') checkPattern(path, `workspaces["${dir}"].${name}.files`, step.files, 'js');
    }
  }
}

// Reads and validates the config. `optional` is for callers that only want a
// pattern or a setting: no file is then an empty config, and workspaces may be missing.
export function load({ optional = false } = {}) {
  const path = file();
  if (!existsSync(path)) {
    if (optional) return {};
    invalid(`no ${relative(process.cwd(), path) || path} — write one with: bash static-gate.sh init`);
  }

  let config;
  try {
    config = JSON.parse(readFileSync(path, 'utf8'));
  } catch (error) {
    invalid(`${path}: ${error.message}`);
  }

  for (const key of Object.keys(config)) {
    if (!KEYS.includes(key)) invalid(`${path}: unknown key "${key}" (known: ${KEYS.join(', ')})`);
  }
  checkPatternList(path, 'stack', config.stack);
  checkPatternList(path, 'shared', config.shared, 'ere');
  checkPatternList(path, 'risk.high', config.risk?.high, 'ere');
  checkPatternList(path, 'risk.medium', config.risk?.medium, 'ere');
  checkPatternList(path, 'secrets.allow', config.secrets?.allow, 'ere');
  checkPatternList(path, 'deps.allow', config.deps?.allow, 'js');
  checkDays(path, 'deps.minAgeDays', config.deps?.minAgeDays);
  checkDays(path, 'deps.minVersionDays', config.deps?.minVersionDays);
  if (config.writing !== undefined && !WRITING.includes(config.writing)) {
    invalid(`${path}: writing must be one of: ${WRITING.join(', ')}`);
  }

  if (optional && config.workspaces === undefined) return config;
  checkWorkspaces(path, config.workspaces);
  return config;
}

const normalizeDir = dir => dir.replace(/^\.\//, '').replace(/\/+$/, '') || '.';
const shellQuote = text => `'${text.replace(/'/g, `'\\''`)}'`;
const isInside = (path, dir) => dir === '.' || path === dir || path.startsWith(dir + '/');
const relativeTo = (dir, path) => (dir === '.' ? path : path.slice(dir.length + 1));

// Groups the changed paths by the workspace that owns them: the deepest directory wins.
function groupByWorkspace(workspaces, paths) {
  const deepestFirst = Object.keys(workspaces)
    .map(dir => [normalizeDir(dir), workspaces[dir]])
    .sort((a, b) => b[0].length - a[0].length);

  const touched = new Map();
  const orphans = [];
  for (const path of paths) {
    const owner = deepestFirst.find(([dir]) => isInside(path, dir));
    if (!owner) {
      orphans.push(path);
      continue;
    }
    const [dir, steps] = owner;
    if (!touched.has(dir)) touched.set(dir, { steps, paths: [] });
    touched.get(dir).paths.push(path);
  }
  return { touched, orphans };
}

// One row for one step of one workspace: [RUN|SKIP, dir, step, command or reason]. Null when the step has nothing to do.
function planStep(base, dir, name, step, changed) {
  if (step === undefined) return ['SKIP', dir, name, `no command for ${dir}; set one, or false`];
  if (isOff(step)) return null;

  const command = commandOf(step);
  const relevant = typeof step === 'string' ? changed : changed.filter(path => new RegExp(step.files).test(path));
  if (!relevant.length) return null;
  if (!command.includes('{files}')) return ['RUN', dir, name, command];

  const existing = relevant.filter(path => existsSync(join(base, path)));
  if (!existing.length) return ['SKIP', dir, name, 'every matching path was deleted'];
  const files = existing.map(path => shellQuote(relativeTo(dir, path))).join(' ');
  return ['RUN', dir, name, command.replaceAll('{files}', files)];
}

export function plan(config, paths) {
  const base = root();
  const { touched, orphans } = groupByWorkspace(config.workspaces, paths);
  const rows = [];
  for (const [dir, { steps, paths: changed }] of touched) {
    const names = new Set([...Object.keys(steps), ...STEPS]);
    for (const name of names) {
      const row = planStep(base, dir, name, steps[name], changed);
      if (row) rows.push(row);
    }
  }
  if (orphans.length) {
    const shown = orphans.slice(0, 3).join(', ') + (orphans.length > 3 ? ', …' : '');
    rows.push(['SKIP', '-', 'workspace', `${orphans.length} path(s) under no workspace: ${shown}`]);
  }
  return rows;
}

const isInsideAnother = (dir, dirs) => dirs.some(other => other !== dir && isInside(dir, other));

// The workspaces and stack of the Gradle and Maven builds: one workspace per outermost build root.
function draftJvm(base, tracked) {
  const list = (...patterns) => tracked(...patterns).split('\n').filter(Boolean);
  const dirsOf = paths => [...new Set(paths.map(path => normalizeDir(dirname(path))))];
  const read = path => {
    try {
      return readFileSync(join(base, path), 'utf8');
    } catch {
      return '';
    }
  };

  const gradleFiles = list('build.gradle', 'build.gradle.kts', '*/build.gradle', '*/build.gradle.kts');
  const settings = list('settings.gradle', 'settings.gradle.kts', '*/settings.gradle', '*/settings.gradle.kts');
  const poms = list('pom.xml', '*/pom.xml');
  const gradleDirs = dirsOf(settings.length ? settings : gradleFiles);
  const pomDirs = dirsOf(poms);
  const roots = [
    ...gradleDirs.filter(dir => !isInsideAnother(dir, gradleDirs)).map(dir => ({ dir, tool: 'gradle' })),
    ...pomDirs.filter(dir => !isInsideAnother(dir, pomDirs)).map(dir => ({ dir, tool: 'maven' })),
  ];

  const workspaces = {};
  let buildText = '';
  for (const { dir, tool } of roots) {
    const buildFiles = [...gradleFiles, ...poms].filter(path => isInside(path, dir));
    const text = buildFiles.map(read).join('\n') + read(join(dir, 'gradle.properties'));
    buildText += text;
    const wrapper = tool === 'gradle' ? 'gradlew' : 'mvnw';
    const command = existsSync(join(base, dir, wrapper)) ? `./${wrapper}` : tool === 'gradle' ? 'gradle' : 'mvn';
    const sources = '\\.(java|kt)$';
    const anythingBuilt = '\\.(java|kt|sql|ya?ml|properties|gradle|kts|xml)$';
    const gradle = tool === 'gradle';

    workspaces[dir] = {
      typecheck: { run: gradle ? `${command} -q compileJava compileTestJava` : `${command} -q test-compile`, files: sources },
      lint: /checkstyle/i.test(text)
        ? { run: gradle ? `${command} -q checkstyleMain checkstyleTest` : `${command} -q checkstyle:check`, files: sources }
        : false,
      format: /spotless/i.test(text)
        ? { run: gradle ? `${command} -q spotlessCheck` : `${command} -q spotless:check`, files: sources }
        : false,
      test: { run: gradle ? `${command} test` : `${command} -q test`, files: anythingBuilt },
    };
  }

  const stack = [];
  if (/spring-boot|org\.springframework/.test(buildText)) stack.push('spring');
  if (/data-jpa|hibernate|jakarta\.persistence/.test(buildText)) stack.push('jpa');
  return { workspaces, stack };
}

// The workspaces and stack of the Go modules: one workspace per go.mod.
function draftGo(base, tracked) {
  const modules = tracked('go.mod', '*/go.mod')
    .split('\n')
    .filter(path => path && !/(^|\/)(vendor|node_modules|testdata)\//.test(path))
    .sort();
  const has = (dir, pattern) => {
    try {
      return readdirSync(join(base, dir)).some(name => pattern.test(name));
    } catch {
      return false;
    }
  };
  const lintConfig = /^\.golangci\.(ya?ml|toml|json)$/;
  const sources = '\\.go$';
  const anythingBuilt = '\\.(go|mod|sum|sql|html|gohtml|tmpl|templ)$';

  const workspaces = {};
  let moduleText = '';
  for (const path of modules) {
    const dir = normalizeDir(dirname(path));
    try {
      moduleText += readFileSync(join(base, path), 'utf8');
    } catch {
      // an unreadable go.mod still gets the default steps
    }
    const linted = has(dir, lintConfig) || has('.', lintConfig);
    workspaces[dir] = {
      typecheck: { run: 'go build ./...', files: sources },
      lint: { run: linted ? 'golangci-lint run ./...' : 'go vet ./...', files: sources },
      format: { run: 'test -z "$(gofmt -l .)"', files: sources },
      test: { run: 'go test ./...', files: anythingBuilt },
    };
  }

  const stack = [];
  if (modules.length) stack.push('go');
  if (/github\.com\/a-h\/templ/.test(moduleText)) stack.push('templ');
  const templates = ['*.html', '*.gohtml', '*.tmpl', '*.templ'];
  if (git('grep', '--untracked', '-lE', 'hx-(get|post|put|patch|delete|boost)=', '--', ...templates)) stack.push('htmx');
  return { workspaces, stack };
}

// One directory that holds two builds (a package.json beside a Gradle, Maven or Go one): a step both
// sides have runs both commands, the second under `<step>-<suffix>`.
function mergeSteps(first, second, suffix) {
  const merged = { ...first };
  for (const [name, step] of Object.entries(second)) {
    const other = first[name];
    if (other === undefined || isOff(other)) merged[name] = step;
    else if (!isOff(step)) merged[`${name}-${suffix}`] = step;
  }
  return merged;
}

// A first draft of the config, guessed from the lockfile, the package.json files, the Gradle, Maven and
// Go builds, and the config files beside them.
function draft() {
  const base = root();
  const readJson = path => {
    try {
      return JSON.parse(readFileSync(join(base, path), 'utf8'));
    } catch {
      return {};
    }
  };
  const dirHas = (dir, pattern) => {
    try {
      return readdirSync(join(base, dir)).some(name => pattern.test(name));
    } catch {
      return false;
    }
  };
  const tracked = (...patterns) => git('ls-files', '-co', '--exclude-standard', '--', ...patterns);
  const dependenciesOf = manifest => ({ ...manifest.dependencies, ...manifest.devDependencies });

  let packageManager = 'npm';
  if (dirHas('.', /^pnpm-lock\.yaml$/)) packageManager = 'pnpm';
  else if (dirHas('.', /^yarn\.lock$/)) packageManager = 'yarn';
  else if (dirHas('.', /^bun\.lockb?$/)) packageManager = 'bun';
  const exec = { npm: 'npx --no-install', pnpm: 'pnpm exec', yarn: 'yarn run', bun: 'bun x' }[packageManager];

  const rootManifest = readJson('package.json');
  const manifests = tracked('package.json', '*/package.json')
    .split('\n')
    .filter(path => path && !path.includes('node_modules/'))
    .sort();

  const workspaces = {};
  const allDependencies = {};
  for (const path of manifests) {
    const dir = normalizeDir(dirname(path));
    const manifest = readJson(path);
    const dependencies = { ...dependenciesOf(rootManifest), ...dependenciesOf(manifest) };
    const scripts = manifest.scripts || {};
    Object.assign(allDependencies, dependenciesOf(manifest));
    const hereOrRootHas = pattern => dirHas(dir, pattern) || dirHas('.', pattern);

    const steps = {};
    if (scripts.typecheck) {
      steps.typecheck = { run: `${packageManager} run typecheck`, files: CODE };
    } else if (dirHas(dir, /^tsconfig\.json$/)) {
      steps.typecheck = { run: `${exec} tsc --noEmit -p tsconfig.json`, files: '\\.[cm]?tsx?$' };
    }
    if (hereOrRootHas(/^(eslint\.config\.|\.eslintrc)/) || manifest.eslintConfig) {
      steps.lint = { run: `${exec} eslint --max-warnings=0 --no-warn-ignored {files}`, files: '\\.([cm]?[jt]sx?|vue|svelte)$' };
    }
    if (hereOrRootHas(/^(\.prettierrc|prettier\.config\.)/) || manifest.prettier || rootManifest.prettier) {
      steps.format = `${exec} prettier --check --ignore-unknown {files}`;
    }
    if (dependencies.vitest) {
      steps.test = { run: `${exec} vitest related --run {files}`, files: CODE };
    } else if (dependencies.jest) {
      steps.test = { run: `${exec} jest --findRelatedTests {files}`, files: CODE };
    } else if (scripts.test) {
      steps.test = { run: `${packageManager} test`, files: CODE };
    }
    const usesPrisma = dependencies.prisma || dependencies['@prisma/client'];
    if (usesPrisma && tracked(dir === '.' ? '*.prisma' : `${dir}/*.prisma`)) {
      steps.prisma = { run: `${exec} prisma validate`, files: '\\.prisma$' };
    }

    if (dir === '.' || Object.keys(steps).length) workspaces[dir] = steps;
  }
  const jvm = draftJvm(base, tracked);
  for (const [dir, steps] of Object.entries(jvm.workspaces)) {
    workspaces[dir] = mergeSteps(workspaces[dir] || {}, steps, 'jvm');
  }
  const go = draftGo(base, tracked);
  for (const [dir, steps] of Object.entries(go.workspaces)) {
    workspaces[dir] = mergeSteps(workspaces[dir] || {}, steps, 'go');
  }
  workspaces['.'] ||= {};

  const stackMarkers = {
    nestjs: '@nestjs/core',
    angular: '@angular/core',
    'react-native': 'react-native',
    expo: 'expo',
    next: 'next',
    react: 'react',
    prisma: '@prisma/client',
    htmx: 'htmx.org',
  };
  const stack = [
    ...new Set([...Object.keys(stackMarkers).filter(name => allDependencies[stackMarkers[name]]), ...jvm.stack, ...go.stack]),
  ];
  return { stack, writing: DEFAULTS.writing, workspaces };
}

function printValue(key) {
  const config = { ...DEFAULTS, ...load({ optional: true }) };
  const value = (key || '').split('.').reduce((object, part) => object?.[part], config);
  if (value === undefined || value === null) return;
  if (Array.isArray(value)) console.log(ere(value));
  else if (typeof value === 'object') console.log(JSON.stringify(value));
  else console.log(String(value));
}

function writeDraft() {
  const path = file();
  if (existsSync(path)) invalid(`${path} exists; edit it`);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify(draft(), null, 2) + '\n');
  console.log(`wrote ${relative(process.cwd(), path)} — every command in it is a guess from your build files. Read it, fix it, commit it.`);
  console.log('A step the gate should never run for a workspace is `false`; a missing step is reported as skipped on every run.');
}

function main([command, ...args]) {
  switch (command) {
    case 'check':
      load();
      return;
    case 'get':
      printValue(args[0]);
      return;
    case 'plan':
      for (const row of plan(load(), args)) console.log(row.join('\t'));
      return;
    case 'init':
      writeDraft();
      return;
    default:
      console.error('usage: config.mjs check | get <key> | plan <path>... | init');
      process.exit(2);
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    if (!(error instanceof Invalid)) throw error;
    console.error(`delivery config: ${error.message}`);
    process.exit(2);
  }
}
