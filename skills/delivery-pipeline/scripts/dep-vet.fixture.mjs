// Stand-in for the npm registry and OSV in tests. Prints its port, then serves until killed.
import { createServer } from 'node:http';

const ago = d => new Date(Date.now() - d * 86400000).toISOString();
const pkg = (created, versions, scripts = {}) => {
  const names = Object.keys(versions);
  return {
    'dist-tags': { latest: names.at(-1) },
    time: { created: ago(created), ...Object.fromEntries(names.map(v => [v, ago(versions[v])])) },
    versions: Object.fromEntries(names.map(v => [v, { scripts }])),
  };
};
const registry = {
  lodash: pkg(4000, { '4.17.20': 2000, '4.17.21': 1500 }),
  '@scope/tool': pkg(900, { '1.0.0': 800 }),
  'young-pkg': pkg(3, { '0.0.1': 3 }),
  'fresh-version': pkg(900, { '1.0.0': 800, '2.0.0': 1 }),
  'has-script': pkg(900, { '1.0.0': 800 }, { postinstall: 'node build.js' }),
  'evil-pkg': pkg(900, { '1.0.0': 800 }),
};
const advisories = { 'lodash@4.17.20': ['GHSA-35jh-r3h4-6jhm'], 'evil-pkg@1.0.0': ['MAL-2025-0001'] };

const server = createServer((req, res) => {
  const json = (code, body) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(body)); };
  if (req.method === 'POST') {
    let body = '';
    req.on('data', d => (body += d)).on('end', () => {
      const queries = JSON.parse(body).queries;
      json(200, { results: queries.map(q => ({ vulns: (advisories[`${q.package.name}@${q.version}`] || []).map(id => ({ id })) })) });
    });
    return;
  }
  const name = decodeURIComponent(req.url.slice(1));
  registry[name] ? json(200, registry[name]) : json(404, { error: 'Not found' });
});
server.listen(0, '127.0.0.1', () => console.log(server.address().port));
